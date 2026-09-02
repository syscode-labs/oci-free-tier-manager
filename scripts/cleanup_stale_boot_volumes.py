#!/usr/bin/env python3
"""Remove unattached OCI boot volumes before/after Terraform apply."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from typing import Any


def oci(profile: str, *args: str) -> Any:
    command = ["oci", "--profile", profile, *args]
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    if not result.stdout.strip():
        return {"data": []}
    return json.loads(result.stdout)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tenancy-ocid", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    compartments = [{"id": args.tenancy_ocid, "name": "<tenancy-root>"}]
    compartments.extend(
        {"id": item["id"], "name": item["name"]}
        for item in oci(
            args.profile,
            "iam",
            "compartment",
            "list",
            "--compartment-id",
            args.tenancy_ocid,
            "--compartment-id-in-subtree",
            "true",
            "--all",
        )["data"]
        if item["lifecycle-state"] == "ACTIVE"
    )

    stale: list[tuple[str, str, str]] = []
    for compartment in compartments:
        volumes = oci(
            args.profile,
            "bv",
            "boot-volume",
            "list",
            "--compartment-id",
            compartment["id"],
            "--all",
        )["data"]
        attached: set[str] = set()
        for volume in volumes:
            if volume["lifecycle-state"] != "AVAILABLE":
                continue
            attachments = oci(
                args.profile,
                "compute",
                "boot-volume-attachment",
                "list",
                "--compartment-id",
                compartment["id"],
                "--availability-domain",
                volume["availability-domain"],
                "--all",
            )["data"]
            if any(
                item["boot-volume-id"] == volume["id"]
                and item["lifecycle-state"] == "ATTACHED"
                for item in attachments
            ):
                attached.add(volume["id"])
        stale.extend(
            (compartment["name"], volume["display-name"], volume["id"])
            for volume in volumes
            if volume["lifecycle-state"] == "AVAILABLE" and volume["id"] not in attached
        )

    for compartment, display_name, volume_id in stale:
        print(f"stale boot volume: {compartment}/{display_name} {volume_id}")
        if not args.dry_run:
            subprocess.run(
                [
                    "oci",
                    "--profile",
                    args.profile,
                    "bv",
                    "boot-volume",
                    "delete",
                    "--boot-volume-id",
                    volume_id,
                    "--force",
                ],
                check=True,
                env=os.environ,
            )
    print(f"stale boot volumes {'found' if args.dry_run else 'removed'}: {len(stale)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
