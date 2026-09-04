#!/usr/bin/env python3
"""Tests for the live Always Free usage gate."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location(
    "check_free_tier_usage", SCRIPTS / "check_free_tier_usage.py"
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Failed to load check_free_tier_usage")
check_free_tier_usage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_free_tier_usage)


def instance(name: str, shape: str, ocpus: int = 0, memory: int = 0) -> dict:
    return {
        "display-name": name,
        "shape": shape,
        "shape-config": {"ocpus": ocpus, "memory-in-gbs": memory},
        "lifecycle-state": "RUNNING",
    }


class FreeTierUsageTests(unittest.TestCase):
    def test_accepts_full_live_allocation(self) -> None:
        instances = [
            instance("a1-1", "VM.Standard.A1.Flex", 1, 6),
            instance("a1-2", "VM.Standard.A1.Flex", 1, 6),
            instance("micro-1", "VM.Standard.E2.1.Micro"),
            instance("micro-2", "VM.Standard.E2.1.Micro"),
        ]
        boot = [{"size-in-gbs": 50, "lifecycle-state": "AVAILABLE"} for _ in range(4)]
        usage, errors = check_free_tier_usage.validate_inventory(
            instances, boot, [], [], [], []
        )
        self.assertEqual(errors, [])
        self.assertEqual(usage["storage_gb"], 200)

    def test_rejects_unattached_storage_overage(self) -> None:
        boot = [{"size-in-gbs": 50, "lifecycle-state": "AVAILABLE"} for _ in range(5)]
        _, errors = check_free_tier_usage.validate_inventory([], boot, [], [], [], [])
        self.assertIn("live storage_gb=250 exceeds Always Free limit=200", errors)

    def test_rejects_non_free_shape(self) -> None:
        _, errors = check_free_tier_usage.validate_inventory(
            [instance("paid", "VM.Standard.E4.Flex", 1, 8)], [], [], [], [], []
        )
        self.assertTrue(any("non-Always-Free shape" in error for error in errors))

    def test_fails_closed_when_oci_query_fails(self) -> None:
        with mock.patch(
            "subprocess.run",
            side_effect=__import__("subprocess").CalledProcessError(1, ["oci"]),
        ):
            with self.assertRaises(__import__("subprocess").CalledProcessError):
                check_free_tier_usage.oci("DEFAULT", "compute", "instance", "list")

    def test_rejects_more_than_one_load_balancer(self) -> None:
        lbs = [{"lifecycle-state": "ACTIVE"}, {"lifecycle-state": "ACTIVE"}]
        _, errors = check_free_tier_usage.validate_inventory([], [], [], lbs, [], [])
        self.assertIn("live load_balancers=2 exceeds Always Free limit=1", errors)

    def test_reports_public_dns_as_paid_resource(self) -> None:
        zone = {"id": "zone-id", "name": "example.test", "lifecycle-state": "ACTIVE"}
        usage, errors = check_free_tier_usage.validate_inventory(
            [], [], [], [], [zone], []
        )
        self.assertEqual(errors, [])
        self.assertEqual(
            usage["paid_resources"],
            [{"type": "oci_dns_zone", "id": "zone-id", "name": "example.test"}],
        )

    def test_counts_only_reserved_public_ips(self) -> None:
        public_ips = [
            {"lifetime": "RESERVED", "lifecycle-state": "ASSIGNED"},
            {"lifetime": "EPHEMERAL", "lifecycle-state": "ASSIGNED"},
        ]
        usage, errors = check_free_tier_usage.validate_inventory(
            [], [], [], [], [], public_ips
        )
        self.assertEqual(errors, [])
        self.assertEqual(usage["reserved_public_ips"], 1)


if __name__ == "__main__":
    unittest.main()
