#!/usr/bin/env python3
"""Query live tenancy usage and fail outside OCI Always Free compute/storage limits."""

from __future__ import annotations

import argparse
import json
import subprocess
from typing import Any

from check_free_tier_plan import (
    A1_SHAPE,
    ALLOWED_SHAPES,
    MAX_A1_INSTANCES,
    MAX_A1_OCPUS,
    MAX_A1_RAM_GB,
    MAX_LOAD_BALANCERS,
    MAX_MICRO_INSTANCES,
    MAX_STORAGE_GB,
    MICRO_SHAPE,
)

TERMINAL_STATES = {"TERMINATING", "TERMINATED"}


def oci(profile: str, *args: str) -> Any:
    result = subprocess.run(
        ["oci", "--profile", profile, *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout or '{"data": []}')


def inventory(
    profile: str, tenancy_ocid: str
) -> tuple[list[dict], list[dict], list[dict], list[dict], list[dict], list[dict]]:
    compartments = [tenancy_ocid]
    compartments.extend(
        item["id"]
        for item in oci(
            profile,
            "iam",
            "compartment",
            "list",
            "--compartment-id",
            tenancy_ocid,
            "--compartment-id-in-subtree",
            "true",
            "--all",
        )["data"]
        if item["lifecycle-state"] == "ACTIVE"
    )
    instances: list[dict] = []
    boot_volumes: list[dict] = []
    volumes: list[dict] = []
    load_balancers: list[dict] = []
    public_dns_zones: list[dict] = []
    reserved_public_ips: list[dict] = []
    for compartment in compartments:
        instances.extend(
            oci(
                profile,
                "compute",
                "instance",
                "list",
                "--compartment-id",
                compartment,
                "--all",
            )["data"]
        )
        boot_volumes.extend(
            oci(
                profile,
                "bv",
                "boot-volume",
                "list",
                "--compartment-id",
                compartment,
                "--all",
            )["data"]
        )
        volumes.extend(
            oci(
                profile,
                "bv",
                "volume",
                "list",
                "--compartment-id",
                compartment,
                "--all",
            )["data"]
        )
        load_balancers.extend(
            oci(
                profile,
                "lb",
                "load-balancer",
                "list",
                "--compartment-id",
                compartment,
                "--all",
            )["data"]
        )
        public_dns_zones.extend(
            oci(
                profile,
                "dns",
                "zone",
                "list",
                "--compartment-id",
                compartment,
                "--scope",
                "GLOBAL",
                "--all",
            ).get("data", [])
        )
        reserved_public_ips.extend(
            oci(
                profile,
                "network",
                "public-ip",
                "list",
                "--scope",
                "REGION",
                "--compartment-id",
                compartment,
                "--all",
            ).get("data", [])
        )
    return (
        instances,
        boot_volumes,
        volumes,
        load_balancers,
        public_dns_zones,
        reserved_public_ips,
    )


def validate_inventory(
    instances: list[dict],
    boot_volumes: list[dict],
    volumes: list[dict],
    load_balancers: list[dict],
    public_dns_zones: list[dict],
    reserved_public_ips: list[dict],
) -> tuple[dict[str, object], list[str]]:
    live_instances = [
        item for item in instances if item.get("lifecycle-state") not in TERMINAL_STATES
    ]
    live_boot = [
        item
        for item in boot_volumes
        if item.get("lifecycle-state") not in TERMINAL_STATES
    ]
    live_volumes = [
        item for item in volumes if item.get("lifecycle-state") not in TERMINAL_STATES
    ]
    live_load_balancers = [
        item
        for item in load_balancers
        if item.get("lifecycle-state") not in TERMINAL_STATES
    ]
    errors = []
    for item in live_instances:
        if item.get("shape") not in ALLOWED_SHAPES:
            errors.append(
                f"live instance {item.get('display-name')} uses non-Always-Free shape {item.get('shape')}"
            )
    a1 = [item for item in live_instances if item.get("shape") == A1_SHAPE]
    micros = [item for item in live_instances if item.get("shape") == MICRO_SHAPE]
    usage = {
        "a1_instances": float(len(a1)),
        "a1_ocpus": sum(
            float(item.get("shape-config", {}).get("ocpus") or 0) for item in a1
        ),
        "a1_ram_gb": sum(
            float(item.get("shape-config", {}).get("memory-in-gbs") or 0) for item in a1
        ),
        "micro_instances": float(len(micros)),
        "storage_gb": sum(
            float(item.get("size-in-gbs") or 0) for item in live_boot + live_volumes
        ),
        "load_balancers": float(len(live_load_balancers)),
        "reserved_public_ips": float(
            len(
                [
                    item
                    for item in reserved_public_ips
                    if item.get("lifecycle-state") not in TERMINAL_STATES
                    and item.get("lifetime") == "RESERVED"
                ]
            )
        ),
        "paid_resources": [
            {"type": "oci_dns_zone", "id": item.get("id"), "name": item.get("name")}
            for item in public_dns_zones
            if item.get("lifecycle-state") not in TERMINAL_STATES
        ],
    }
    limits = {
        "a1_instances": MAX_A1_INSTANCES,
        "a1_ocpus": MAX_A1_OCPUS,
        "a1_ram_gb": MAX_A1_RAM_GB,
        "micro_instances": MAX_MICRO_INSTANCES,
        "storage_gb": MAX_STORAGE_GB,
        "load_balancers": MAX_LOAD_BALANCERS,
    }
    for key, limit in limits.items():
        if usage[key] > limit:
            errors.append(
                f"live {key}={usage[key]:g} exceeds Always Free limit={limit}"
            )
    return usage, errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", default="DEFAULT")
    parser.add_argument("--tenancy-ocid", required=True)
    parser.add_argument("--output", type=argparse.FileType("w"))
    args = parser.parse_args()
    usage, errors = validate_inventory(*inventory(args.profile, args.tenancy_ocid))
    if args.output:
        json.dump(usage, args.output)
        args.output.write("\n")
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        print(
            "Resolve the live overage before planning. Paid resources require "
            "explicit user approval and a separate reviewed change."
        )
        return 1
    print(
        "Live Always Free usage accepted: "
        f"A1={usage['a1_instances']:g} instances/{usage['a1_ocpus']:g} OCPU/{usage['a1_ram_gb']:g} GB, "
        f"Micro={usage['micro_instances']:g}, storage={usage['storage_gb']:g} GB, "
        f"reserved public IPs={usage['reserved_public_ips']:g}"
    )
    if usage["paid_resources"]:
        print("Live paid resources were found; the reviewed plan must remove them.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
