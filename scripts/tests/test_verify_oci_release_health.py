"""Focused fail-closed tests for OCI post-apply release evidence."""

from __future__ import annotations

import copy
import unittest

from scripts.verify_oci_release_health import HealthError, verify

TALOS = "v1.9.3"
KUBERNETES = "v1.31.2"


def healthy_evidence() -> dict[str, object]:
    machines = [
        {
            "id": "machine-a",
            "cluster": "oci-lab",
            "connected": True,
            "phase": "RUNNING",
            "ready": True,
        },
        {
            "id": "machine-b",
            "cluster": "oci-lab",
            "connected": True,
            "phase": "RUNNING",
            "ready": True,
        },
    ]
    return {
        "cluster": {
            "name": "oci-lab",
            "phase": "RUNNING",
            "ready": True,
            "talos_version": TALOS,
            "kubernetes_version": KUBERNETES,
        },
        "machines": machines,
        "talos": [
            {"node": entry["id"], "version": TALOS, "healthy": True}
            for entry in machines
        ],
        "kubernetes": {
            "api_ready": True,
            "server_version": KUBERNETES,
            "nodes": [
                {"name": "node-a", "ready": True},
                {"name": "node-b", "ready": True},
            ],
        },
    }


class OCIReleaseHealthTests(unittest.TestCase):
    def test_accepts_complete_exact_health_proof(self) -> None:
        verify(healthy_evidence(), TALOS, KUBERNETES)

    def test_rejects_old_healthy_talos_nodes(self) -> None:
        evidence = copy.deepcopy(healthy_evidence())
        evidence["talos"][0]["version"] = "v1.9.2"  # type: ignore[index]
        with self.assertRaisesRegex(HealthError, "does not equal requested"):
            verify(evidence, TALOS, KUBERNETES)

    def test_rejects_missing_expected_node(self) -> None:
        evidence = copy.deepcopy(healthy_evidence())
        evidence["machines"].pop()  # type: ignore[union-attr]
        with self.assertRaisesRegex(HealthError, "exactly 2 connected OCI machines"):
            verify(evidence, TALOS, KUBERNETES)

    def test_rejects_timeout_or_missing_kubernetes_api_proof(self) -> None:
        evidence = copy.deepcopy(healthy_evidence())
        evidence["kubernetes"]["api_ready"] = False  # type: ignore[index]
        with self.assertRaisesRegex(HealthError, "Kubernetes API readiness"):
            verify(evidence, TALOS, KUBERNETES)


if __name__ == "__main__":
    unittest.main()
