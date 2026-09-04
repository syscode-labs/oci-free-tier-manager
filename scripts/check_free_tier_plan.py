#!/usr/bin/env python3
"""Fail a deployment plan that can exceed OCI Always Free compute or storage."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Iterator

A1_SHAPE = "VM.Standard.A1.Flex"
MICRO_SHAPE = "VM.Standard.E2.1.Micro"
ALLOWED_SHAPES = {A1_SHAPE, MICRO_SHAPE}
MAX_A1_INSTANCES = 2
MAX_A1_OCPUS = 2
MAX_A1_RAM_GB = 12
MAX_MICRO_INSTANCES = 2
MAX_STORAGE_GB = 200
MAX_LOAD_BALANCERS = 1

# OCI resource types that have an explicit gate here or do not carry a
# standing service charge. Any other OCI create/replacement fails closed.
ALLOWED_OCI_CREATE_TYPES = {
    "oci_budget_alert_rule",
    "oci_budget_budget",
    "oci_core_boot_volume",
    "oci_core_dhcp_options",
    "oci_core_instance",
    "oci_core_internet_gateway",
    "oci_core_route_table",
    "oci_core_security_list",
    "oci_core_subnet",
    "oci_core_vcn",
    "oci_core_volume",
    "oci_identity_compartment",
    "oci_identity_dynamic_group",
    "oci_identity_group",
    "oci_identity_policy",
    "oci_identity_user",
    "oci_identity_user_group_membership",
    "oci_load_balancer_load_balancer",
}


def resources(module: dict[str, Any] | None) -> Iterator[dict[str, Any]]:
    if not module:
        return
    yield from module.get("resources", [])
    for child in module.get("child_modules", []):
        yield from resources(child)


def first_block(values: dict[str, Any], name: str) -> dict[str, Any]:
    blocks = values.get(name) or []
    return blocks[0] if blocks else {}


def instance_usage(values: dict[str, Any]) -> tuple[str, float, float, float]:
    shape = values.get("shape")
    source = first_block(values, "source_details")
    storage = float(source.get("boot_volume_size_in_gbs") or 0)
    if shape == A1_SHAPE:
        config = first_block(values, "shape_config")
        return (
            shape,
            float(config.get("ocpus") or 0),
            float(config.get("memory_in_gbs") or 0),
            storage,
        )
    return str(shape), 0, 0, storage


def empty_usage() -> dict[str, float]:
    return {
        "a1_instances": 0.0,
        "a1_ocpus": 0.0,
        "a1_ram_gb": 0.0,
        "micro_instances": 0.0,
        "storage_gb": 0.0,
        "load_balancers": 0.0,
        "reserved_public_ips": 0.0,
    }


def resource_usage(
    resource_type: str, values: dict[str, Any] | None
) -> dict[str, float]:
    usage = empty_usage()
    if not values:
        return usage
    if resource_type == "oci_core_instance":
        shape, ocpus, memory, storage = instance_usage(values)
        if shape not in ALLOWED_SHAPES:
            raise ValueError(f"non-Always-Free compute shape {shape!r}")
        if shape == A1_SHAPE:
            usage.update(a1_instances=1, a1_ocpus=ocpus, a1_ram_gb=memory)
        else:
            usage["micro_instances"] = 1
        usage["storage_gb"] = storage
    elif resource_type in {"oci_core_volume", "oci_core_boot_volume"}:
        usage["storage_gb"] = float(values.get("size_in_gbs") or 0)
    elif resource_type == "oci_load_balancer_load_balancer":
        details = first_block(values, "shape_details")
        if (
            values.get("shape") != "flexible"
            or float(details.get("maximum_bandwidth_in_mbps") or 0) > 10
        ):
            raise ValueError("load balancer exceeds the free 10 Mbps shape")
        usage["load_balancers"] = 1
    elif resource_type == "oci_core_public_ip":
        if values.get("lifetime") != "RESERVED":
            raise ValueError(
                "managed public IP must use the reviewed RESERVED allowance"
            )
        usage["reserved_public_ips"] = 1
    return usage


def planned_usage(plan: dict[str, Any]) -> dict[str, float]:
    usage = empty_usage()
    for resource in resources(plan.get("planned_values", {}).get("root_module")):
        resource_type = resource.get("type")
        values = resource.get("values") or {}
        try:
            item_usage = resource_usage(str(resource_type), values)
        except ValueError as error:
            raise ValueError(f"{resource.get('address')}: {error}") from error
        for key, value in item_usage.items():
            usage[key] += value

    return usage


def projected_usage(plan: dict[str, Any], current: dict[str, Any]) -> dict[str, float]:
    projected = {key: float(current.get(key, 0)) for key in empty_usage()}
    for change in plan.get("resource_changes", []):
        resource_type = str(change.get("type"))
        before = resource_usage(resource_type, change.get("change", {}).get("before"))
        after = resource_usage(resource_type, change.get("change", {}).get("after"))
        for key in projected:
            projected[key] += after[key] - before[key]
    return projected


def maximum_transient_usage(
    plan: dict[str, Any], current: dict[str, Any]
) -> dict[str, float]:
    maximum = {key: float(current.get(key, 0)) for key in empty_usage()}
    final = projected_usage(plan, current)
    for change in plan.get("resource_changes", []):
        actions = change.get("change", {}).get("actions", [])
        if not actions or actions[0] not in {"create", "update"}:
            continue
        before = resource_usage(
            str(change.get("type")), change.get("change", {}).get("before")
        )
        after = resource_usage(
            str(change.get("type")), change.get("change", {}).get("after")
        )
        for key in maximum:
            if actions[0] == "create":
                maximum[key] += after[key]
            else:
                maximum[key] += max(0, after[key] - before[key])
    for key in maximum:
        maximum[key] = max(maximum[key], final[key])
    return maximum


def validate(plan: dict[str, Any], current: dict[str, Any] | None = None) -> list[str]:
    errors: list[str] = []
    for check in plan.get("checks", []):
        failed = check.get("status") == "fail" or any(
            instance.get("status") == "fail" for instance in check.get("instances", [])
        )
        if failed:
            address = check.get("address", {}).get("to_display", "unknown check")
            errors.append(f"OpenTofu check failed: {address}")

    for change in plan.get("resource_changes", []):
        resource_type = str(change.get("type"))
        actions = change.get("change", {}).get("actions", [])
        if resource_type == "oci_core_instance" and actions == ["create", "delete"]:
            errors.append(
                f"{change.get('address')}: create-before-destroy can temporarily exceed the free compute allowance"
            )
        if (
            "create" in actions
            and resource_type.startswith("oci_")
            and resource_type not in ALLOWED_OCI_CREATE_TYPES
        ):
            errors.append(
                f"{change.get('address')}: {resource_type} is not approved for Always Free creation or replacement"
            )

    try:
        usage = planned_usage(plan)
    except ValueError as error:
        errors.append(str(error))
        return errors

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
                f"planned {key}={usage[key]:g} exceeds Always Free limit={limit}"
            )
    if current is not None:
        for paid in current.get("paid_resources", []):
            removed = any(
                change.get("type") == paid.get("type")
                and (change.get("change", {}).get("before") or {}).get("id")
                == paid.get("id")
                and "delete" in change.get("change", {}).get("actions", [])
                for change in plan.get("resource_changes", [])
            )
            if not removed:
                errors.append(
                    f"live paid resource {paid.get('type')} {paid.get('name')} is not removed by this plan"
                )
        try:
            projected = projected_usage(plan, current)
            maximum = maximum_transient_usage(plan, current)
        except ValueError as error:
            errors.append(str(error))
            return errors
        for key, limit in limits.items():
            if projected[key] > limit:
                errors.append(
                    f"projected live {key}={projected[key]:g} exceeds Always Free limit={limit}"
                )
            if maximum[key] > limit:
                errors.append(
                    f"maximum transient {key}={maximum[key]:g} exceeds Always Free limit={limit}"
                )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("plan_json", type=Path)
    parser.add_argument("--current-usage", type=Path)
    args = parser.parse_args()
    plan = json.loads(args.plan_json.read_text(encoding="utf-8"))
    current = (
        json.loads(args.current_usage.read_text(encoding="utf-8"))
        if args.current_usage
        else None
    )
    errors = validate(plan, current)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        print(
            "Paid resources require a separate, explicitly user-approved change. There is no bypass flag."
        )
        return 1
    usage = planned_usage(plan)
    print(
        "Always Free plan accepted: "
        f"A1={usage['a1_instances']:g} instances/{usage['a1_ocpus']:g} OCPU/{usage['a1_ram_gb']:g} GB, "
        f"Micro={usage['micro_instances']:g}, storage={usage['storage_gb']:g} GB"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
