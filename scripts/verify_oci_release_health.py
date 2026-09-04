#!/usr/bin/env python3
"""Fail-closed post-apply evidence checks for the OCI Talos release receiver.

The workflow deliberately collects every datum through the Omni service-account
path, then this module checks that the observed cluster—not merely a ready
control-plane summary—matches the release's versions and complete topology.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

EXPECTED_CLUSTER = "oci-lab"
EXPECTED_NODE_COUNT = 2


class HealthError(RuntimeError):
    """Evidence is absent, malformed, stale, or does not prove this release."""


def json_stream(path: Path) -> list[Any]:
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        raise HealthError(f"{path}: empty JSON evidence")
    decoder = json.JSONDecoder()
    values: list[Any] = []
    index = 0
    while index < len(text):
        while index < len(text) and text[index].isspace():
            index += 1
        if index >= len(text):
            break
        value, index = decoder.raw_decode(text, index)
        values.extend(value if isinstance(value, list) else [value])
    return values


def require(condition: bool, message: str) -> None:
    if not condition:
        raise HealthError(message)


def exact_version(value: object, expected: str, evidence: str) -> None:
    require(
        value == expected,
        f"{evidence} version {value!r} does not equal requested {expected!r}",
    )


def verify(
    evidence: dict[str, Any], talos_version: str, kubernetes_version: str
) -> None:
    """Validate normalized, complete release evidence with no best-effort paths."""
    cluster = evidence.get("cluster")
    require(isinstance(cluster, dict), "missing Omni cluster evidence")
    require(cluster.get("name") == EXPECTED_CLUSTER, "Omni evidence is not for oci-lab")
    require(
        cluster.get("phase") == "RUNNING" and cluster.get("ready") is True,
        "oci-lab is not RUNNING Ready",
    )
    exact_version(cluster.get("talos_version"), talos_version, "Omni Talos")
    exact_version(
        cluster.get("kubernetes_version"), kubernetes_version, "Omni Kubernetes"
    )

    machines = evidence.get("machines")
    require(
        isinstance(machines, list) and len(machines) == EXPECTED_NODE_COUNT,
        f"expected exactly {EXPECTED_NODE_COUNT} connected OCI machines",
    )
    machine_ids: set[str] = set()
    for machine in machines:
        require(isinstance(machine, dict), "invalid Omni machine evidence")
        machine_id = machine.get("id")
        require(
            isinstance(machine_id, str) and machine_id,
            "machine evidence has no identity",
        )
        require(machine_id not in machine_ids, "duplicate Omni machine identity")
        machine_ids.add(machine_id)
        require(
            machine.get("cluster") == EXPECTED_CLUSTER, "machine is outside oci-lab"
        )
        require(
            machine.get("connected") is True
            and machine.get("phase") == "RUNNING"
            and machine.get("ready") is True,
            f"OCI machine {machine_id} is not connected RUNNING Ready",
        )

    talos = evidence.get("talos")
    require(
        isinstance(talos, list) and len(talos) == EXPECTED_NODE_COUNT,
        "missing Talos proof for one or more expected OCI machines",
    )
    talos_ids = {entry.get("node") for entry in talos if isinstance(entry, dict)}
    require(
        talos_ids == machine_ids,
        "Talos proof does not match the exact connected OCI machines",
    )
    for entry in talos:
        require(
            isinstance(entry, dict) and entry.get("healthy") is True,
            "Talos API did not report a healthy expected machine",
        )
        exact_version(entry.get("version"), talos_version, "Talos node")

    kubernetes = evidence.get("kubernetes")
    require(
        isinstance(kubernetes, dict) and kubernetes.get("api_ready") is True,
        "Kubernetes API readiness is not proven",
    )
    exact_version(
        kubernetes.get("server_version"), kubernetes_version, "Kubernetes API"
    )
    nodes = kubernetes.get("nodes")
    require(
        isinstance(nodes, list) and len(nodes) == EXPECTED_NODE_COUNT,
        f"expected exactly {EXPECTED_NODE_COUNT} Kubernetes nodes",
    )
    names: set[str] = set()
    for node in nodes:
        require(isinstance(node, dict), "invalid Kubernetes node evidence")
        name = node.get("name")
        require(
            isinstance(name, str) and name and name not in names,
            "missing or duplicate Kubernetes node name",
        )
        names.add(name)
        require(node.get("ready") is True, f"Kubernetes node {name} is not Ready")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--talos-version", required=True)
    parser.add_argument("--kubernetes-version", required=True)
    args = parser.parse_args()
    try:
        evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
        require(isinstance(evidence, dict), "evidence must be a JSON object")
        verify(evidence, args.talos_version, args.kubernetes_version)
    except (OSError, ValueError, HealthError) as error:
        print(f"ERROR: release health verification failed: {error}", file=sys.stderr)
        return 1
    print(
        "OCI release health verified: exact Omni/Talos/Kubernetes versions and two-node topology"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
