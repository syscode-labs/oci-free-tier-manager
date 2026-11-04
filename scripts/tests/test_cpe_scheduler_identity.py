"""Regression checks for the schedule's separate invocation identity."""

import pathlib
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[2] / "tofu/oci/cpe-auto-recreate.tf"


class SchedulerIdentityTests(unittest.TestCase):
    """The target and invocation principal must both be narrowly scoped."""

    def test_schedule_principal_matches_exact_schedule(self):
        """Do not confuse Function identity with its caller."""
        text = SOURCE.read_text()
        start = text.index(
            'resource "oci_identity_dynamic_group" "cpe_recreate_schedule"'
        )
        end = text.index(
            'resource "oci_identity_policy" "cpe_recreate_schedule"', start
        )
        block = text[start:end]
        self.assertIn("resource.type = 'resourceschedule'", block)
        self.assertIn(
            "resource.id = '${oci_resource_scheduler_schedule.cpe_recreate[0].id}'",
            block,
        )
        self.assertIn(
            'contains(["function", "verify-local"], var.cpe_remediator_mode)', block
        )

    def test_schedule_invocation_is_target_scoped(self):
        """Grant invocation without network-management permissions."""
        text = SOURCE.read_text()
        start = text.index('resource "oci_identity_policy" "cpe_recreate_schedule"')
        block = text[start : text.index("# OCIR push auth.", start)]
        self.assertIn("oci_identity_dynamic_group.cpe_recreate_schedule[0].name", block)
        self.assertIn(
            "to use functions-family in compartment id ${local.compartment_id}", block
        )
        self.assertIn(
            "target.function.id = '${oci_functions_function.cpe_recreate[0].id}'", block
        )
        self.assertNotIn("to manage", block)


if __name__ == "__main__":
    unittest.main()
