#!/usr/bin/env python3
"""Tests for the hard Always Free plan gate."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "check_free_tier_plan.py"
SPEC = importlib.util.spec_from_file_location("check_free_tier_plan", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Failed to load module from {MODULE_PATH}")
check_free_tier_plan = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_free_tier_plan)


def instance(
    address: str, shape: str, *, ocpus: int = 0, memory: int = 0, storage: int = 50
) -> dict:
    """Build a minimal planned compute resource for a test."""
    return {
        "address": address,
        "type": "oci_core_instance",
        "values": {
            "shape": shape,
            "shape_config": [{"ocpus": ocpus, "memory_in_gbs": memory}],
            "source_details": [{"boot_volume_size_in_gbs": storage}],
        },
    }


def plan(
    resources: list[dict],
    changes: list[dict] | None = None,
    checks: list[dict] | None = None,
) -> dict:
    """Build a minimal OpenTofu plan JSON object for a test."""
    return {
        "planned_values": {"root_module": {"resources": resources}},
        "resource_changes": changes or [],
        "checks": checks or [],
    }


class FreeTierPlanTests(unittest.TestCase):
    def test_accepts_full_always_free_allocation(self) -> None:
        """Accept a plan that exactly consumes the free allocation."""
        candidate = plan(
            [
                instance("a1[0]", "VM.Standard.A1.Flex", ocpus=1, memory=6),
                instance("a1[1]", "VM.Standard.A1.Flex", ocpus=1, memory=6),
                instance("micro[0]", "VM.Standard.E2.1.Micro"),
                instance("micro[1]", "VM.Standard.E2.1.Micro"),
            ]
        )
        self.assertEqual(check_free_tier_plan.validate(candidate), [])

    def test_rejects_non_free_compute_shape(self) -> None:
        """Reject a compute shape outside the free allowlist."""
        errors = check_free_tier_plan.validate(
            plan([instance("vm", "VM.Standard.E4.Flex")])
        )
        self.assertTrue(
            any("non-Always-Free compute shape" in error for error in errors)
        )

    def test_rejects_storage_above_200_gb(self) -> None:
        """Reject final storage above the free limit."""
        candidate = plan(
            [
                instance("a1[0]", "VM.Standard.A1.Flex", ocpus=1, memory=6, storage=50),
                instance("a1[1]", "VM.Standard.A1.Flex", ocpus=1, memory=6, storage=50),
                instance("micro[0]", "VM.Standard.E2.1.Micro", storage=50),
                instance("micro[1]", "VM.Standard.E2.1.Micro", storage=51),
            ]
        )
        errors = check_free_tier_plan.validate(candidate)
        self.assertIn("planned storage_gb=201 exceeds Always Free limit=200", errors)

    def test_rejects_failed_tofu_check(self) -> None:
        """Reject a plan containing a failed OpenTofu check."""
        candidate = plan(
            [],
            checks=[
                {"address": {"to_display": "check.storage_budget"}, "status": "fail"}
            ],
        )
        self.assertIn(
            "OpenTofu check failed: check.storage_budget",
            check_free_tier_plan.validate(candidate),
        )

    def test_rejects_create_before_destroy_compute(self) -> None:
        """Reject overlapping compute replacement."""
        candidate = plan(
            [],
            changes=[
                {
                    "address": "oci_core_instance.ampere_instance[0]",
                    "type": "oci_core_instance",
                    "change": {"actions": ["create", "delete"]},
                }
            ],
        )
        errors = check_free_tier_plan.validate(candidate)
        self.assertTrue(any("create-before-destroy" in error for error in errors))

    def test_rejects_create_when_live_storage_has_no_headroom(self) -> None:
        """Reject new storage when live usage is already full."""
        new_micro = instance("micro[1]", "VM.Standard.E2.1.Micro")
        candidate = plan(
            [new_micro],
            changes=[
                {
                    "address": "micro[1]",
                    "type": "oci_core_instance",
                    "change": {
                        "actions": ["create"],
                        "before": None,
                        "after": new_micro["values"],
                    },
                }
            ],
        )
        current = check_free_tier_plan.empty_usage()
        current["storage_gb"] = 200
        errors = check_free_tier_plan.validate(candidate, current)
        self.assertIn(
            "projected live storage_gb=250 exceeds Always Free limit=200", errors
        )

    def test_accepts_destroy_before_create_with_no_net_increase(self) -> None:
        """Accept destroy-before-create replacement without a peak increase."""
        old_micro = instance("micro[0]", "VM.Standard.E2.1.Micro")
        candidate = plan(
            [old_micro],
            changes=[
                {
                    "address": "micro[0]",
                    "type": "oci_core_instance",
                    "change": {
                        "actions": ["delete", "create"],
                        "before": old_micro["values"],
                        "after": old_micro["values"],
                    },
                }
            ],
        )
        current = check_free_tier_plan.empty_usage()
        current.update(micro_instances=2, storage_gb=200)
        self.assertEqual(check_free_tier_plan.validate(candidate, current), [])

    def test_rejects_storage_replacement_overlap(self) -> None:
        """Reject storage replacement whose overlap exceeds the free limit."""
        current = check_free_tier_plan.empty_usage()
        current["storage_gb"] = 200
        candidate = plan(
            [],
            changes=[
                {
                    "address": "oci_core_volume.data",
                    "type": "oci_core_volume",
                    "change": {
                        "actions": ["create", "delete"],
                        "before": {"size_in_gbs": 50},
                        "after": {"size_in_gbs": 50},
                    },
                }
            ],
        )
        errors = check_free_tier_plan.validate(candidate, current)
        self.assertIn(
            "maximum transient storage_gb=250 exceeds Always Free limit=200",
            errors,
        )

    def test_rejects_load_balancer_above_free_bandwidth(self) -> None:
        """Reject a load balancer above the free bandwidth allowance."""
        candidate = plan(
            [
                {
                    "address": "oci_load_balancer_load_balancer.free_tier_lb[0]",
                    "type": "oci_load_balancer_load_balancer",
                    "values": {
                        "shape": "flexible",
                        "shape_details": [{"maximum_bandwidth_in_mbps": 20}],
                    },
                }
            ]
        )
        errors = check_free_tier_plan.validate(candidate)
        self.assertTrue(
            any("exceeds the free 10 Mbps shape" in error for error in errors)
        )

    def test_rejects_unreviewed_reserved_public_ip_creation(self) -> None:
        """Reject unreviewed reserved public IP creation."""
        candidate = plan(
            [],
            changes=[
                {
                    "address": "oci_core_public_ip.extra",
                    "type": "oci_core_public_ip",
                    "change": {
                        "actions": ["create"],
                        "before": None,
                        "after": {"lifetime": "RESERVED"},
                    },
                }
            ],
        )
        errors = check_free_tier_plan.validate(candidate)
        self.assertTrue(
            any("not approved for Always Free" in error for error in errors)
        )

    def test_rejects_oci_public_dns_creation(self) -> None:
        """Reject creation of paid OCI public DNS."""
        candidate = plan(
            [],
            changes=[
                {
                    "address": "oci_dns_zone.paid",
                    "type": "oci_dns_zone",
                    "change": {"actions": ["create"], "before": None, "after": {}},
                }
            ],
        )
        errors = check_free_tier_plan.validate(candidate)
        self.assertTrue(
            any("not approved for Always Free" in error for error in errors)
        )

    def test_live_paid_dns_must_be_removed(self) -> None:
        """Require exact removal of a live paid DNS zone."""
        current = check_free_tier_plan.empty_usage()
        current["paid_resources"] = [
            {"type": "oci_dns_zone", "id": "zone-id", "name": "example.test"}
        ]
        errors = check_free_tier_plan.validate(plan([]), current)
        self.assertIn(
            "live paid resource oci_dns_zone example.test is not removed by this plan",
            errors,
        )

    def test_accepts_removal_of_live_paid_dns(self) -> None:
        """Accept exact removal of a reported paid DNS zone."""
        current = check_free_tier_plan.empty_usage()
        current["paid_resources"] = [
            {"type": "oci_dns_zone", "id": "zone-id", "name": "example.test"}
        ]
        candidate = plan(
            [],
            changes=[
                {
                    "address": "oci_dns_zone.paid",
                    "type": "oci_dns_zone",
                    "change": {
                        "actions": ["delete"],
                        "before": {"id": "zone-id"},
                        "after": None,
                    },
                }
            ],
        )
        self.assertEqual(check_free_tier_plan.validate(candidate, current), [])


if __name__ == "__main__":
    unittest.main()
