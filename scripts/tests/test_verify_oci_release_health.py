"""Focused fail-closed tests for OCI post-apply release evidence."""

from __future__ import annotations

import unittest

from scripts.verify_oci_release_health import HealthError, verify

TALOS = "v1.9.3"
KUBERNETES = "v1.31.2"
MACHINE_IDS = {"machine-a", "machine-b"}


def healthy_talos() -> list[object]:
    return [
        {"node": "machine-a", "spec": {"version": TALOS}},
        {"node": "machine-b", "spec": {"version": TALOS}},
    ]


def healthy_nodes() -> dict[str, object]:
    return {
        "items": [
            {"status": {"conditions": [{"type": "Ready", "status": "True"}]}},
            {"status": {"conditions": [{"type": "Ready", "status": "True"}]}},
        ]
    }


class OCIReleaseHealthTests(unittest.TestCase):
    def test_accepts_exact_selected_machine_health_proof(self) -> None:
        verify(
            MACHINE_IDS,
            healthy_talos(),
            healthy_nodes(),
            {"serverVersion": {"gitVersion": KUBERNETES}},
            TALOS,
            KUBERNETES,
        )

    def test_rejects_old_healthy_talos_nodes(self) -> None:
        talos = healthy_talos()
        talos[0]["spec"] = {"version": "v1.9.2"}  # type: ignore[index]
        with self.assertRaisesRegex(HealthError, "exact requested version"):
            verify(
                MACHINE_IDS,
                talos,
                healthy_nodes(),
                {"serverVersion": {"gitVersion": KUBERNETES}},
                TALOS,
                KUBERNETES,
            )

    def test_rejects_talos_results_for_unselected_node(self) -> None:
        talos = healthy_talos()
        talos[1]["node"] = "machine-c"  # type: ignore[index]
        with self.assertRaisesRegex(HealthError, "selected OCI machine UUIDs"):
            verify(
                MACHINE_IDS,
                talos,
                healthy_nodes(),
                {"serverVersion": {"gitVersion": KUBERNETES}},
                TALOS,
                KUBERNETES,
            )

    def test_rejects_missing_kubernetes_ready_proof(self) -> None:
        nodes = healthy_nodes()
        nodes["items"][1]["status"]["conditions"][0]["status"] = "False"  # type: ignore[index]
        with self.assertRaisesRegex(HealthError, "not Ready"):
            verify(
                MACHINE_IDS,
                healthy_talos(),
                nodes,
                {"serverVersion": {"gitVersion": KUBERNETES}},
                TALOS,
                KUBERNETES,
            )


if __name__ == "__main__":
    unittest.main()
