#!/usr/bin/env python3
"""Tests for adoption/import mapping logic."""

from __future__ import annotations

import unittest
import importlib.util
from pathlib import Path
from tempfile import NamedTemporaryFile

MODULE_PATH = Path(__file__).resolve().parents[1] / "adopt_existing_to_state.py"
SPEC = importlib.util.spec_from_file_location("adopt_existing_to_state", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Failed to load module from {MODULE_PATH}")
adopt_existing_to_state = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(adopt_existing_to_state)


class AdoptExistingToStateTests(unittest.TestCase):
    """Validate deterministic and safe import mapping behavior."""

    def test_sort_instances_orders_by_numeric_suffix(self) -> None:
        """Instances with numeric suffixes should sort naturally."""
        items = [
            {"display-name": "ampere-instance-10", "id": "id10"},
            {"display-name": "ampere-instance-2", "id": "id2"},
            {"display-name": "ampere-instance-1", "id": "id1"},
        ]

        sorted_items = adopt_existing_to_state.sort_instances_for_mapping(items)

        self.assertEqual([i["id"] for i in sorted_items], ["id1", "id2", "id10"])

    def test_map_instances_fails_when_discovery_exceeds_expected(self) -> None:
        """Importer must fail if wildcard discovery finds extra VMs."""
        discovered = [
            {"display-name": "ampere-instance-1", "id": "id1"},
            {"display-name": "ampere-instance-2", "id": "id2"},
            {"display-name": "ampere-instance-3", "id": "id3"},
        ]

        with self.assertRaises(adopt_existing_to_state.DiscoveryError):
            adopt_existing_to_state.map_instances_to_addresses(
                discovered=discovered,
                expected_count=2,
                address_prefix="oci_core_instance.ampere_instance",
                shape_name="VM.Standard.A1.Flex",
            )

    def test_map_instances_maps_existing_without_filling_gaps(self) -> None:
        """Importer should map discovered VMs and allow missing slots."""
        discovered = [
            {"display-name": "micro-instance-2", "id": "id2"},
        ]

        mapped = adopt_existing_to_state.map_instances_to_addresses(
            discovered=discovered,
            expected_count=2,
            address_prefix="oci_core_instance.micro_instance",
            shape_name="VM.Standard.E2.1.Micro",
        )

        self.assertEqual(
            mapped,
            [("oci_core_instance.micro_instance[0]", "id2")],
        )

    def test_read_adoption_toggle_from_tfvars(self) -> None:
        """Importer should parse adopt_existing_resources boolean from tfvars."""
        with NamedTemporaryFile("w+", encoding="utf-8") as tfvars_file:
            tfvars_file.write("adopt_existing_resources = true\n")
            tfvars_file.flush()
            enabled = adopt_existing_to_state.read_adoption_toggle(
                Path(tfvars_file.name)
            )
            self.assertTrue(enabled)

        with NamedTemporaryFile("w+", encoding="utf-8") as tfvars_file:
            tfvars_file.write("adopt_existing_resources = false\n")
            tfvars_file.flush()
            enabled = adopt_existing_to_state.read_adoption_toggle(
                Path(tfvars_file.name)
            )
            self.assertFalse(enabled)

    def test_parse_bucket_usage_bytes(self) -> None:
        """Bucket usage should sum object sizes."""
        response = {
            "data": [
                {"name": "terraform.tfstate", "size": 1024},
                {"name": "terraform.tfstate.backup", "size": 2048},
            ]
        }
        self.assertEqual(
            adopt_existing_to_state.parse_bucket_usage_bytes(response), 3072
        )

    def test_has_storage_quota_statement(self) -> None:
        """Quota statement detection should match object-storage storage-bytes rules."""
        statements = [
            "Set object-storage quota storage-bytes to 20000000000 in compartment homelab",
            "Set compute quota standard-a1-core-count to 4 in compartment homelab",
        ]
        self.assertTrue(adopt_existing_to_state.has_storage_quota_statement(statements))
        self.assertFalse(
            adopt_existing_to_state.has_storage_quota_statement(
                ["Allow group x to inspect compartments in tenancy"]
            )
        )


if __name__ == "__main__":
    unittest.main()
