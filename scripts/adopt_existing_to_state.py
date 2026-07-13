#!/usr/bin/env python3
"""Adopt existing OCI resources into OpenTofu state without recreating capacity slots."""

from __future__ import annotations

import argparse
import configparser
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


class DiscoveryError(RuntimeError):
    """Raised when OCI discovery cannot produce a safe, deterministic mapping."""


def read_adoption_toggle(tfvars_path: Path) -> bool:
    """Read adopt_existing_resources from tfvars and return its boolean value."""
    if not tfvars_path.exists():
        raise DiscoveryError(f"tfvars file not found: {tfvars_path}")

    pattern = re.compile(
        r"^\s*adopt_existing_resources\s*=\s*(true|false)\s*$", re.MULTILINE
    )
    text = tfvars_path.read_text(encoding="utf-8")
    match = pattern.search(text)
    if match is None:
        raise DiscoveryError(f"Missing 'adopt_existing_resources' in {tfvars_path}")
    return match.group(1) == "true"


def read_oci_profile(profile: str) -> dict[str, str]:
    """Read tenancy and region for a profile from ~/.oci/config."""
    config_path = Path.home() / ".oci" / "config"
    parser = configparser.ConfigParser()
    parser.read(config_path)

    if profile not in parser:
        raise DiscoveryError(f"OCI profile '{profile}' not found in {config_path}")

    section = parser[profile]
    missing = [k for k in ("tenancy", "region") if k not in section]
    if missing:
        raise DiscoveryError(
            f"OCI profile '{profile}' missing keys: {', '.join(missing)}"
        )

    return {
        "tenancy": section["tenancy"].strip(),
        "region": section["region"].strip(),
    }


def run_oci(profile: str, region: str, args: list[str]) -> Any:
    """Run OCI CLI command and parse JSON output."""
    cmd = ["oci", "--profile", profile, "--region", region] + args
    env = os.environ.copy()
    env.pop("OCI_OUTPUT_ENV_FILE", None)
    proc = subprocess.run(cmd, text=True, capture_output=True, env=env)
    if proc.returncode != 0:
        raise DiscoveryError(
            proc.stderr.strip() or proc.stdout.strip() or "oci command failed"
        )
    try:
        return json.loads(proc.stdout) if proc.stdout.strip() else {"data": []}
    except json.JSONDecodeError as exc:
        raise DiscoveryError(
            f"Failed to parse OCI JSON output for command: {' '.join(cmd)}"
        ) from exc


def parse_bucket_usage_bytes(objects_response: dict[str, Any]) -> int:
    """Return total bytes currently stored in a bucket from object list response."""
    total = 0
    for item in objects_response.get("data", []):
        size = item.get("size")
        if isinstance(size, int):
            total += size
    return total


def has_storage_quota_statement(statements: list[str]) -> bool:
    """Check if quota statements include object-storage storage-bytes cap."""
    for statement in statements:
        normalized = statement.lower().strip()
        if "object-storage" in normalized and "storage-bytes" in normalized:
            return True
    return False


def find_single(
    items: list[dict[str, Any]], *, label: str, **constraints: str
) -> dict[str, Any] | None:
    """Find exactly one resource matching all key/value constraints."""
    matches = []
    for item in items:
        if all(item.get(k) == v for k, v in constraints.items()):
            matches.append(item)

    if len(matches) > 1:
        raise DiscoveryError(f"Found multiple {label} resources matching {constraints}")
    return matches[0] if matches else None


def sort_instances_for_mapping(instances: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Sort instances by display-name numeric suffix then full name for deterministic mapping."""
    suffix_re = re.compile(r".*-(\d+)$")

    def key(item: dict[str, Any]) -> tuple[int, int, str, str]:
        name = str(item.get("display-name", ""))
        match = suffix_re.match(name)
        if match:
            return (0, int(match.group(1)), name, str(item.get("id", "")))
        return (1, 0, name, str(item.get("id", "")))

    return sorted(instances, key=key)


def map_instances_to_addresses(
    *,
    discovered: list[dict[str, Any]],
    expected_count: int,
    address_prefix: str,
    shape_name: str,
) -> list[tuple[str, str]]:
    """Map discovered instances to indexed Terraform addresses safely."""
    ordered = sort_instances_for_mapping(discovered)
    if len(ordered) > expected_count:
        raise DiscoveryError(
            f"Found {len(ordered)} {shape_name} instances but configuration expects {expected_count}. "
            "Refusing to continue."
        )

    imports = []
    for idx, item in enumerate(ordered):
        imports.append((f"{address_prefix}[{idx}]", item["id"]))
    return imports


def discover_compartment_id(
    profile: str, region: str, tenancy_ocid: str, compartment_name: str
) -> str:
    """Resolve compartment OCID by name and fail if missing/ambiguous."""
    compartments = run_oci(
        profile,
        region,
        [
            "iam",
            "compartment",
            "list",
            "--compartment-id",
            tenancy_ocid,
            "--name",
            compartment_name,
            "--all",
            "--access-level",
            "ACCESSIBLE",
            "--compartment-id-in-subtree",
            "true",
            "--lifecycle-state",
            "ACTIVE",
        ],
    )["data"]
    if not compartments:
        raise DiscoveryError(
            f"Compartment '{compartment_name}' not found or not ACTIVE"
        )
    if len(compartments) > 1:
        raise DiscoveryError(
            f"Compartment name '{compartment_name}' is ambiguous ({len(compartments)} matches)"
        )
    return compartments[0]["id"]


def discover_imports(
    *,
    profile: str,
    region: str,
    compartment_id: str,
    expected_ampere: int,
    expected_micro: int,
) -> list[tuple[str, str]]:
    """Discover import mapping for known core resources and instances."""
    imports: list[tuple[str, str]] = []

    vcns = run_oci(
        profile,
        region,
        ["network", "vcn", "list", "--compartment-id", compartment_id, "--all"],
    )["data"]
    vcn = find_single(vcns, label="VCN", **{"display-name": "free-tier-vcn"})
    if vcn:
        imports.append(("oci_core_vcn.free_tier_vcn", vcn["id"]))

    igws = run_oci(
        profile,
        region,
        [
            "network",
            "internet-gateway",
            "list",
            "--compartment-id",
            compartment_id,
            "--all",
        ],
    )["data"]
    igw = find_single(
        igws, label="internet gateway", **{"display-name": "free-tier-igw"}
    )
    if igw:
        imports.append(("oci_core_internet_gateway.free_tier_igw", igw["id"]))

    route_tables = run_oci(
        profile,
        region,
        ["network", "route-table", "list", "--compartment-id", compartment_id, "--all"],
    )["data"]
    route_table = find_single(
        route_tables, label="route table", **{"display-name": "free-tier-route-table"}
    )
    if route_table:
        imports.append(
            ("oci_core_route_table.free_tier_route_table", route_table["id"])
        )

    security_lists = run_oci(
        profile,
        region,
        [
            "network",
            "security-list",
            "list",
            "--compartment-id",
            compartment_id,
            "--all",
        ],
    )["data"]
    security_list = find_single(
        security_lists,
        label="security list",
        **{"display-name": "free-tier-security-list"},
    )
    if security_list:
        imports.append(
            ("oci_core_security_list.free_tier_security_list", security_list["id"])
        )

    subnets = run_oci(
        profile,
        region,
        ["network", "subnet", "list", "--compartment-id", compartment_id, "--all"],
    )["data"]
    subnet = find_single(
        subnets, label="subnet", **{"display-name": "free-tier-subnet"}
    )
    if subnet:
        imports.append(("oci_core_subnet.free_tier_subnet", subnet["id"]))

    instances = run_oci(
        profile,
        region,
        ["compute", "instance", "list", "--compartment-id", compartment_id, "--all"],
    )["data"]
    keep_states = {"PROVISIONING", "RUNNING", "STARTING", "STOPPING", "STOPPED"}
    ampere = [
        i
        for i in instances
        if i.get("shape") == "VM.Standard.A1.Flex"
        and i.get("lifecycle-state") in keep_states
    ]
    micro = [
        i
        for i in instances
        if i.get("shape") == "VM.Standard.E2.1.Micro"
        and i.get("lifecycle-state") in keep_states
    ]

    imports.extend(
        map_instances_to_addresses(
            discovered=ampere,
            expected_count=expected_ampere,
            address_prefix="oci_core_instance.ampere_instance",
            shape_name="VM.Standard.A1.Flex",
        )
    )
    imports.extend(
        map_instances_to_addresses(
            discovered=micro,
            expected_count=expected_micro,
            address_prefix="oci_core_instance.micro_instance",
            shape_name="VM.Standard.E2.1.Micro",
        )
    )

    public_ips = run_oci(
        profile,
        region,
        ["network", "public-ip", "list", "--compartment-id", compartment_id, "--all"],
    )["data"]
    bastion = find_single(
        public_ips, label="public ip", **{"display-name": "bastion-ip"}
    )
    if bastion:
        imports.append(("oci_core_public_ip.bastion[0]", bastion["id"]))
    ingress = find_single(
        public_ips, label="public ip", **{"display-name": "k8s-ingress-ip"}
    )
    if ingress:
        imports.append(("oci_core_public_ip.ingress", ingress["id"]))

    return imports


def run_state_backend_preflight(
    *,
    profile: str,
    region: str,
    tenancy_ocid: str,
    state_compartment_name: str,
    state_bucket_name: str,
    max_state_bytes: int,
    require_storage_quota: bool,
) -> None:
    """Validate state bucket usage and quota constraints before adoption."""
    discover_compartment_id(profile, region, tenancy_ocid, state_compartment_name)
    namespace = run_oci(profile, region, ["os", "ns", "get"]).get("data")
    if not isinstance(namespace, str) or namespace == "":
        raise DiscoveryError("Failed to resolve Object Storage namespace for preflight")

    run_oci(
        profile,
        region,
        [
            "os",
            "bucket",
            "get",
            "--namespace-name",
            namespace,
            "--bucket-name",
            state_bucket_name,
        ],
    )

    objects = run_oci(
        profile,
        region,
        [
            "os",
            "object",
            "list",
            "--namespace-name",
            namespace,
            "--bucket-name",
            state_bucket_name,
            "--all",
        ],
    )
    used_bytes = parse_bucket_usage_bytes(objects)
    print(f"State bucket usage: {used_bytes} bytes")

    if max_state_bytes > 0 and used_bytes > max_state_bytes:
        raise DiscoveryError(
            f"State bucket usage {used_bytes} exceeds configured max-state-bytes {max_state_bytes}. "
            "Refusing adoption."
        )

    if require_storage_quota:
        quotas = run_oci(
            profile,
            region,
            ["limits", "quota", "list", "--compartment-id", tenancy_ocid, "--all"],
        )
        statements: list[str] = []
        for quota in quotas.get("data", []):
            for statement in quota.get("statements", []):
                if isinstance(statement, str):
                    statements.append(statement)
        if not has_storage_quota_statement(statements):
            raise DiscoveryError(
                "No object-storage storage-bytes quota found in tenancy quota policies. "
                "Refusing adoption."
            )


def run_imports(tf_dir: Path, imports: list[tuple[str, str]]) -> None:
    """Run tofu import for each discovered address/OCID pair."""
    for address, ocid in imports:
        cmd = ["tofu", "-chdir", str(tf_dir), "import", address, ocid]
        proc = subprocess.run(cmd, text=True, capture_output=True)
        if proc.returncode != 0:
            raise DiscoveryError(
                f"Import failed for {address} -> {ocid}\n{proc.stdout.strip()}\n{proc.stderr.strip()}".strip()
            )
        print(f"Imported {address} -> {ocid}")


def parse_args() -> argparse.Namespace:
    """Parse command-line options."""
    parser = argparse.ArgumentParser(
        description="Import existing OCI resources into tofu/oci state"
    )
    parser.add_argument("--profile", default="DEFAULT", help="OCI CLI profile name")
    parser.add_argument("--region", default="", help="OCI region override")
    parser.add_argument(
        "--compartment-name",
        required=True,
        help="OCI compartment name to discover resources from",
    )
    parser.add_argument(
        "--expected-ampere",
        type=int,
        default=3,
        help="Expected A1 instance count from TF config",
    )
    parser.add_argument(
        "--expected-micro",
        type=int,
        default=1,
        help="Expected E2.1.Micro count from TF config",
    )
    parser.add_argument(
        "--tf-dir", default="tofu/oci", help="Terraform/OpenTofu root directory"
    )
    parser.add_argument(
        "--tfvars-file",
        default="tofu/oci/terraform.tfvars",
        help="Terraform variables file path",
    )
    parser.add_argument(
        "--require-adoption-tfvar",
        action="store_true",
        help="Require adopt_existing_resources=true in --tfvars-file",
    )
    parser.add_argument(
        "--state-compartment-name",
        default="",
        help="State bucket compartment name for preflight",
    )
    parser.add_argument(
        "--state-bucket-name", default="", help="State bucket name for preflight"
    )
    parser.add_argument(
        "--max-state-bytes",
        type=int,
        default=0,
        help="Fail preflight if bucket usage exceeds this value; 0 disables usage cap check",
    )
    parser.add_argument(
        "--require-storage-quota",
        action="store_true",
        help="Require object-storage storage-bytes quota to exist before adoption",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Run tofu import commands (default is dry-run)",
    )
    return parser.parse_args()


def main() -> int:
    """Entry point."""
    args = parse_args()
    profile_data = read_oci_profile(args.profile)
    region = args.region or profile_data["region"]
    tenancy_ocid = profile_data["tenancy"]
    tf_dir = Path(args.tf_dir)
    tfvars_path = Path(args.tfvars_file)

    if args.require_adoption_tfvar and not read_adoption_toggle(tfvars_path):
        raise DiscoveryError(
            f"Refusing to adopt because adopt_existing_resources=false in {tfvars_path}. "
            "Set it to true explicitly."
        )

    compartment_id = discover_compartment_id(
        args.profile, region, tenancy_ocid, args.compartment_name
    )
    if args.state_bucket_name:
        state_compartment_name = args.state_compartment_name or args.compartment_name
        run_state_backend_preflight(
            profile=args.profile,
            region=region,
            tenancy_ocid=tenancy_ocid,
            state_compartment_name=state_compartment_name,
            state_bucket_name=args.state_bucket_name,
            max_state_bytes=args.max_state_bytes,
            require_storage_quota=args.require_storage_quota,
        )

    imports = discover_imports(
        profile=args.profile,
        region=region,
        compartment_id=compartment_id,
        expected_ampere=args.expected_ampere,
        expected_micro=args.expected_micro,
    )

    print(f"Compartment: {args.compartment_name} ({compartment_id})")
    print(f"Discovered {len(imports)} import candidates:")
    for address, ocid in imports:
        print(f"  {address} <- {ocid}")

    if not args.execute:
        print("Dry-run only. Re-run with --execute to import into state.")
        return 0

    run_imports(tf_dir, imports)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except DiscoveryError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
