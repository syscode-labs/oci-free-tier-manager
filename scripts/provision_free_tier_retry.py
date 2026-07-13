#!/usr/bin/env python3
"""Provision OCI Always Free resources in a dedicated compartment with retry logic.

- Creates/uses a dedicated compartment and basic public network stack.
- Reads VM profile defaults from tofu/oci/terraform.tfvars.example.
- Launches VM.Standard.A1.Flex and VM.Standard.E2.1.Micro instances.
- Retries launches on capacity errors until targets are met.
"""

from __future__ import annotations

import argparse
import configparser
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
import math
from pathlib import Path
from typing import Any


def log(msg: str) -> None:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


class OciCliError(RuntimeError):
    pass


class OciCli:
    def __init__(self, profile: str, region: str | None = None) -> None:
        self.profile = profile
        self.region = region

    def run(self, args: list[str], expect_json: bool = True) -> Any:
        cmd = ["oci", "--profile", self.profile]
        if self.region:
            cmd.extend(["--region", self.region])
        cmd.extend(args)

        env = os.environ.copy()
        env.pop("OCI_OUTPUT_ENV_FILE", None)
        proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
        if proc.returncode != 0:
            raise OciCliError(
                proc.stderr.strip() or proc.stdout.strip() or "OCI CLI command failed"
            )

        if not expect_json:
            return proc.stdout.strip()

        if proc.stdout.strip() == "":
            return {"data": []}

        try:
            return json.loads(proc.stdout)
        except json.JSONDecodeError as exc:
            raise OciCliError(
                f"Failed to parse JSON output for command: {' '.join(cmd)}"
            ) from exc


CAPACITY_PATTERNS = [
    "Out of host capacity",
    "out of host capacity",
    "Out of capacity",
    "OutOfHostCapacity",
    "LimitExceeded",
]


def is_capacity_error(error_text: str) -> bool:
    return any(pat in error_text for pat in CAPACITY_PATTERNS)


def read_profile_values(profile: str) -> dict[str, str]:
    config_path = Path.home() / ".oci" / "config"
    parser = configparser.ConfigParser()
    parser.read(config_path)

    if profile not in parser:
        raise RuntimeError(f"Profile '{profile}' not found in {config_path}")

    section = parser[profile]
    required = ["tenancy", "user", "region"]
    missing = [key for key in required if key not in section]
    if missing:
        raise RuntimeError(
            f"Profile '{profile}' missing required keys: {', '.join(missing)}"
        )

    return {
        "tenancy": section["tenancy"].strip(),
        "user": section["user"].strip(),
        "region": section["region"].strip(),
    }


def parse_tfvars_profile(tfvars_file: Path) -> dict[str, float]:
    text = tfvars_file.read_text(encoding="utf-8")

    def get_number(name: str, default: float) -> float:
        match = re.search(
            rf"^{name}\s*=\s*([0-9]+(?:\.[0-9]+)?)", text, flags=re.MULTILINE
        )
        return float(match.group(1)) if match else default

    return {
        "ampere_instance_count": get_number("ampere_instance_count", 3),
        "ampere_ocpus_per_instance": get_number("ampere_ocpus_per_instance", 1.33),
        "ampere_memory_per_instance": get_number("ampere_memory_per_instance", 8),
        "ampere_boot_volume_size": get_number("ampere_boot_volume_size", 50),
        "micro_instance_count": get_number("micro_instance_count", 1),
        "micro_boot_volume_size": get_number("micro_boot_volume_size", 50),
    }


def resolve_ssh_public_key(path_value: str) -> str:
    candidates = [
        os.path.expanduser(path_value),
        str(Path.home() / ".ssh" / "id_ed25519.pub"),
        str(Path.home() / ".ssh" / "id_rsa.pub"),
        str(Path.home() / ".ssh" / "id_ecdsa.pub"),
    ]
    for candidate in candidates:
        if os.path.exists(candidate):
            return candidate
    raise RuntimeError(
        "No SSH public key file found. Checked: " + ", ".join(candidates)
    )


def first_match(
    items: list[dict[str, Any]], key: str, value: str
) -> dict[str, Any] | None:
    for item in items:
        if item.get(key) == value:
            return item
    return None


def ensure_compartment(oci: OciCli, tenancy_ocid: str, name: str) -> str:
    compartments = oci.run(
        [
            "iam",
            "compartment",
            "list",
            "--compartment-id",
            tenancy_ocid,
            "--name",
            name,
            "--all",
            "--access-level",
            "ACCESSIBLE",
            "--compartment-id-in-subtree",
            "true",
            "--lifecycle-state",
            "ACTIVE",
        ]
    )["data"]

    for comp in compartments:
        if comp.get("name") == name:
            log(f"Using existing compartment '{name}' ({comp['id']})")
            return comp["id"]

    created = oci.run(
        [
            "iam",
            "compartment",
            "create",
            "--compartment-id",
            tenancy_ocid,
            "--name",
            name,
            "--description",
            "Dedicated compartment for OCI free-tier manager retry provisioning",
        ]
    )["data"]
    compartment_id = created["id"]
    log(f"Created compartment '{name}' ({compartment_id}), waiting for ACTIVE")

    while True:
        listed = oci.run(
            [
                "iam",
                "compartment",
                "list",
                "--compartment-id",
                tenancy_ocid,
                "--name",
                name,
                "--all",
                "--access-level",
                "ACCESSIBLE",
                "--compartment-id-in-subtree",
                "true",
            ]
        )["data"]
        if listed:
            active = [c for c in listed if c.get("lifecycle-state") == "ACTIVE"]
            if active:
                return active[0]["id"]
        time.sleep(5)


def ensure_vcn(
    oci: OciCli, compartment_id: str, name: str, cidr: str, dns_label: str
) -> str:
    vcns = oci.run(
        ["network", "vcn", "list", "--compartment-id", compartment_id, "--all"]
    )["data"]
    vcn = first_match(vcns, "display-name", name)
    if vcn:
        log(f"Using existing VCN '{name}' ({vcn['id']})")
        return vcn["id"]

    created = oci.run(
        [
            "network",
            "vcn",
            "create",
            "--compartment-id",
            compartment_id,
            "--display-name",
            name,
            "--cidr-block",
            cidr,
            "--dns-label",
            dns_label,
        ]
    )["data"]
    log(f"Created VCN '{name}' ({created['id']})")
    return created["id"]


def ensure_igw(oci: OciCli, compartment_id: str, vcn_id: str, name: str) -> str:
    igws = oci.run(
        [
            "network",
            "internet-gateway",
            "list",
            "--compartment-id",
            compartment_id,
            "--all",
        ]
    )["data"]
    for igw in igws:
        if igw.get("display-name") == name and igw.get("vcn-id") == vcn_id:
            log(f"Using existing IGW '{name}' ({igw['id']})")
            return igw["id"]

    created = oci.run(
        [
            "network",
            "internet-gateway",
            "create",
            "--compartment-id",
            compartment_id,
            "--vcn-id",
            vcn_id,
            "--display-name",
            name,
            "--is-enabled",
            "true",
        ]
    )["data"]
    log(f"Created IGW '{name}' ({created['id']})")
    return created["id"]


def ensure_route_table(
    oci: OciCli, compartment_id: str, vcn_id: str, igw_id: str, name: str
) -> str:
    rts = oci.run(
        ["network", "route-table", "list", "--compartment-id", compartment_id, "--all"]
    )["data"]
    for rt in rts:
        if rt.get("display-name") == name and rt.get("vcn-id") == vcn_id:
            log(f"Using existing route table '{name}' ({rt['id']})")
            return rt["id"]

    route_rules = json.dumps(
        [
            {
                "destination": "0.0.0.0/0",
                "destinationType": "CIDR_BLOCK",
                "networkEntityId": igw_id,
            }
        ]
    )
    created = oci.run(
        [
            "network",
            "route-table",
            "create",
            "--compartment-id",
            compartment_id,
            "--vcn-id",
            vcn_id,
            "--display-name",
            name,
            "--route-rules",
            route_rules,
        ]
    )["data"]
    log(f"Created route table '{name}' ({created['id']})")
    return created["id"]


def ensure_security_list(
    oci: OciCli, compartment_id: str, vcn_id: str, name: str
) -> str:
    sls = oci.run(
        [
            "network",
            "security-list",
            "list",
            "--compartment-id",
            compartment_id,
            "--all",
        ]
    )["data"]
    for sl in sls:
        if sl.get("display-name") == name and sl.get("vcn-id") == vcn_id:
            log(f"Using existing security list '{name}' ({sl['id']})")
            return sl["id"]

    ingress = [
        {
            "protocol": "6",
            "source": "0.0.0.0/0",
            "tcpOptions": {"destinationPortRange": {"min": 22, "max": 22}},
        },
        {
            "protocol": "6",
            "source": "0.0.0.0/0",
            "tcpOptions": {"destinationPortRange": {"min": 80, "max": 80}},
        },
        {
            "protocol": "6",
            "source": "0.0.0.0/0",
            "tcpOptions": {"destinationPortRange": {"min": 443, "max": 443}},
        },
        {"protocol": "1", "source": "0.0.0.0/0"},
    ]
    egress = [{"protocol": "all", "destination": "0.0.0.0/0"}]

    created = oci.run(
        [
            "network",
            "security-list",
            "create",
            "--compartment-id",
            compartment_id,
            "--vcn-id",
            vcn_id,
            "--display-name",
            name,
            "--ingress-security-rules",
            json.dumps(ingress),
            "--egress-security-rules",
            json.dumps(egress),
        ]
    )["data"]
    log(f"Created security list '{name}' ({created['id']})")
    return created["id"]


def ensure_subnet(
    oci: OciCli,
    compartment_id: str,
    vcn_id: str,
    route_table_id: str,
    security_list_id: str,
    name: str,
    cidr: str,
    dns_label: str,
) -> str:
    subnets = oci.run(
        ["network", "subnet", "list", "--compartment-id", compartment_id, "--all"]
    )["data"]
    for subnet in subnets:
        if subnet.get("display-name") == name and subnet.get("vcn-id") == vcn_id:
            log(f"Using existing subnet '{name}' ({subnet['id']})")
            return subnet["id"]

    created = oci.run(
        [
            "network",
            "subnet",
            "create",
            "--compartment-id",
            compartment_id,
            "--vcn-id",
            vcn_id,
            "--display-name",
            name,
            "--cidr-block",
            cidr,
            "--dns-label",
            dns_label,
            "--route-table-id",
            route_table_id,
            "--security-list-ids",
            json.dumps([security_list_id]),
        ]
    )["data"]
    log(f"Created subnet '{name}' ({created['id']})")
    return created["id"]


def get_availability_domains(oci: OciCli, tenancy_ocid: str) -> list[str]:
    ads = oci.run(
        ["iam", "availability-domain", "list", "--compartment-id", tenancy_ocid]
    )["data"]
    return [ad["name"] for ad in ads]


def find_latest_image(oci: OciCli, compartment_id: str, shape: str) -> str:
    images = oci.run(
        [
            "compute",
            "image",
            "list",
            "--compartment-id",
            compartment_id,
            "--operating-system",
            "Canonical Ubuntu",
            "--operating-system-version",
            "22.04",
            "--shape",
            shape,
            "--sort-by",
            "TIMECREATED",
            "--sort-order",
            "DESC",
            "--all",
        ]
    )["data"]
    if not images:
        raise RuntimeError(f"No Ubuntu 22.04 image found for shape {shape}")
    return images[0]["id"]


def list_existing_instances(
    oci: OciCli, compartment_id: str, name_prefix: str, shape: str
) -> list[dict[str, Any]]:
    instances = oci.run(
        ["compute", "instance", "list", "--compartment-id", compartment_id, "--all"]
    )["data"]
    keep_states = {"PROVISIONING", "RUNNING", "STARTING", "STOPPING", "STOPPED"}
    return [
        inst
        for inst in instances
        if inst.get("shape") == shape
        and inst.get("display-name", "").startswith(name_prefix)
        and inst.get("lifecycle-state") in keep_states
    ]


def capacity_available(
    oci: OciCli,
    tenancy_ocid: str,
    availability_domain: str,
    shape: str,
    shape_config: dict[str, Any] | None = None,
) -> bool:
    shape_availability: dict[str, Any] = {"instance-shape": shape}
    if shape_config:
        probe_ocpus = max(1, int(math.floor(float(shape_config["ocpus"]))))
        probe_memory = max(6.0, float(shape_config["memoryInGBs"]))
        shape_availability["instance-shape-config"] = {
            "ocpus": probe_ocpus,
            "memory-in-gbs": probe_memory,
        }

    report = oci.run(
        [
            "compute",
            "compute-capacity-report",
            "create",
            "--availability-domain",
            availability_domain,
            "--compartment-id",
            tenancy_ocid,
            "--shape-availabilities",
            json.dumps([shape_availability]),
        ]
    )
    entries = report.get("data", {}).get("shape-availabilities", [])
    if not entries:
        return False
    return entries[0].get("availability-status") == "AVAILABLE"


def launch_instance(
    oci: OciCli,
    *,
    compartment_id: str,
    subnet_id: str,
    ad: str,
    name: str,
    shape: str,
    image_id: str,
    boot_size: int,
    ssh_key_file: str,
    shape_config: dict[str, Any] | None = None,
) -> tuple[bool, str]:
    cmd = [
        "compute",
        "instance",
        "launch",
        "--availability-domain",
        ad,
        "--compartment-id",
        compartment_id,
        "--shape",
        shape,
        "--display-name",
        name,
        "--image-id",
        image_id,
        "--boot-volume-size-in-gbs",
        str(boot_size),
        "--subnet-id",
        subnet_id,
        "--assign-public-ip",
        "true",
        "--ssh-authorized-keys-file",
        ssh_key_file,
    ]

    if shape_config:
        cmd.extend(["--shape-config", json.dumps(shape_config)])

    try:
        data = oci.run(cmd)["data"]
        return True, data["id"]
    except OciCliError as exc:
        return False, str(exc)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Provision OCI Always Free resources with retry"
    )
    parser.add_argument("--profile", default="gf78", help="OCI CLI profile to use")
    parser.add_argument(
        "--compartment-name",
        default="gf78-free-tier-dedicated",
        help="Dedicated compartment name",
    )
    parser.add_argument(
        "--region", default="", help="OCI region override (default: from profile)"
    )
    parser.add_argument(
        "--ssh-key-file", default=str(Path.home() / ".ssh" / "id_rsa.pub")
    )
    parser.add_argument(
        "--retry-seconds",
        type=int,
        default=300,
        help="Seconds between capacity retry cycles",
    )
    parser.add_argument(
        "--max-attempts",
        type=int,
        default=0,
        help="0 = retry forever, otherwise stop after N cycles",
    )
    parser.add_argument(
        "--vm-profile-file",
        default="tofu/oci/terraform.tfvars.example",
        help="File to read VM profile defaults from",
    )
    args = parser.parse_args()

    profile_values = read_profile_values(args.profile)
    region = args.region or profile_values["region"]
    oci = OciCli(profile=args.profile, region=region)

    ssh_key_file = resolve_ssh_public_key(args.ssh_key_file)

    vm_profile = parse_tfvars_profile(Path(args.vm_profile_file))
    ampere_target = int(vm_profile["ampere_instance_count"])
    micro_target = int(vm_profile["micro_instance_count"])

    log(f"Profile={args.profile} Region={region}")
    log(
        "VM profile from repo: "
        f"ampere={ampere_target} "
        f"({vm_profile['ampere_ocpus_per_instance']} OCPU/"
        f"{vm_profile['ampere_memory_per_instance']}GB each), "
        f"micro={micro_target}"
    )

    tenancy_ocid = profile_values["tenancy"]
    compartment_id = ensure_compartment(oci, tenancy_ocid, args.compartment_name)

    vcn_id = ensure_vcn(
        oci,
        compartment_id,
        name="free-tier-vcn",
        cidr="10.0.0.0/16",
        dns_label="freetier",
    )
    igw_id = ensure_igw(oci, compartment_id, vcn_id, "free-tier-igw")
    route_table_id = ensure_route_table(
        oci, compartment_id, vcn_id, igw_id, "free-tier-route-table"
    )
    security_list_id = ensure_security_list(
        oci, compartment_id, vcn_id, "free-tier-security-list"
    )
    subnet_id = ensure_subnet(
        oci,
        compartment_id,
        vcn_id,
        route_table_id,
        security_list_id,
        name="free-tier-subnet",
        cidr="10.0.1.0/24",
        dns_label="subnet",
    )

    ads = get_availability_domains(oci, tenancy_ocid)
    if not ads:
        raise RuntimeError("No availability domains returned")

    ampere_image_id = find_latest_image(oci, compartment_id, "VM.Standard.A1.Flex")
    micro_image_id = find_latest_image(oci, compartment_id, "VM.Standard.E2.1.Micro")

    log(f"A1 image: {ampere_image_id}")
    log(f"Micro image: {micro_image_id}")

    attempt = 0
    while True:
        attempt += 1
        log(f"Launch cycle #{attempt}")

        existing_ampere = list_existing_instances(
            oci, compartment_id, "ampere-instance-", "VM.Standard.A1.Flex"
        )
        existing_micro = list_existing_instances(
            oci, compartment_id, "micro-instance-", "VM.Standard.E2.1.Micro"
        )

        log(f"Existing A1 instances: {len(existing_ampere)}/{ampere_target}")
        log(f"Existing Micro instances: {len(existing_micro)}/{micro_target}")

        for idx in range(len(existing_micro), micro_target):
            name = f"micro-instance-{idx + 1}"
            ad = ads[0]
            if not capacity_available(
                oci=oci,
                tenancy_ocid=tenancy_ocid,
                availability_domain=ad,
                shape="VM.Standard.E2.1.Micro",
            ):
                log(
                    f"Capacity unavailable for VM.Standard.E2.1.Micro in {ad}, skipping launch for now"
                )
                continue
            ok, detail = launch_instance(
                oci,
                compartment_id=compartment_id,
                subnet_id=subnet_id,
                ad=ad,
                name=name,
                shape="VM.Standard.E2.1.Micro",
                image_id=micro_image_id,
                boot_size=int(vm_profile["micro_boot_volume_size"]),
                ssh_key_file=ssh_key_file,
            )
            if ok:
                log(f"Launched {name}: {detail}")
            else:
                log(f"Launch failed for {name}: {detail}")
                if not is_capacity_error(detail):
                    raise RuntimeError(f"Non-capacity error launching {name}: {detail}")

        for idx in range(len(existing_ampere), ampere_target):
            name = f"ampere-instance-{idx + 1}"
            ad = ads[idx % len(ads)]
            shape_config = {
                "ocpus": vm_profile["ampere_ocpus_per_instance"],
                "memoryInGBs": vm_profile["ampere_memory_per_instance"],
            }
            if not capacity_available(
                oci=oci,
                tenancy_ocid=tenancy_ocid,
                availability_domain=ad,
                shape="VM.Standard.A1.Flex",
                shape_config=shape_config,
            ):
                log(
                    f"Capacity unavailable for VM.Standard.A1.Flex in {ad}, skipping launch for now"
                )
                continue
            ok, detail = launch_instance(
                oci,
                compartment_id=compartment_id,
                subnet_id=subnet_id,
                ad=ad,
                name=name,
                shape="VM.Standard.A1.Flex",
                image_id=ampere_image_id,
                boot_size=int(vm_profile["ampere_boot_volume_size"]),
                ssh_key_file=ssh_key_file,
                shape_config=shape_config,
            )
            if ok:
                log(f"Launched {name}: {detail}")
            else:
                log(f"Launch failed for {name}: {detail}")
                if not is_capacity_error(detail):
                    raise RuntimeError(f"Non-capacity error launching {name}: {detail}")

        existing_ampere = list_existing_instances(
            oci, compartment_id, "ampere-instance-", "VM.Standard.A1.Flex"
        )
        existing_micro = list_existing_instances(
            oci, compartment_id, "micro-instance-", "VM.Standard.E2.1.Micro"
        )

        if (
            len(existing_ampere) >= ampere_target
            and len(existing_micro) >= micro_target
        ):
            log("Target profile satisfied. Provisioning complete.")
            log(f"Compartment: {compartment_id}")
            log(f"VCN: {vcn_id}")
            log(f"Subnet: {subnet_id}")
            return 0

        if args.max_attempts > 0 and attempt >= args.max_attempts:
            log("Reached max attempts before satisfying target profile.")
            return 2

        log(
            f"Capacity not yet sufficient. Sleeping {args.retry_seconds}s before next cycle..."
        )
        time.sleep(args.retry_seconds)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        log(f"ERROR: {exc}")
        sys.exit(1)
