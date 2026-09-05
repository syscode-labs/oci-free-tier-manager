#!/usr/bin/env python3
"""Fail-closed checks over evidence collected by the OCI release workflow."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

EXPECTED_NODE_COUNT = 2


class HealthError(RuntimeError):
    """Evidence is absent, malformed, stale, or does not prove this release."""


def json_stream(path: Path) -> list[Any]:
    """Read omnictl or talosctl JSON, including multiple adjacent values."""
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
    """Raise a stable failure suitable for workflow logs."""
    if not condition:
        raise HealthError(message)


def machine_ids(path: Path) -> set[str]:
    """Load exactly the Omni UUIDs selected by the workflow."""
    ids = {
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    require(
        len(ids) == EXPECTED_NODE_COUNT,
        "expected exactly two selected OCI machine UUIDs",
    )
    return ids


def verify(
    selected_machine_ids: set[str],
    talos: list[Any],
    kubernetes_nodes: dict[str, Any],
    kubernetes_version: dict[str, Any],
    talos_version: str,
    expected_kubernetes_version: str,
) -> None:
    """Verify exact selected Talos UUIDs, versions, and Kubernetes readiness."""
    require(
        len(talos) == EXPECTED_NODE_COUNT,
        "Talos proof must contain exactly the two selected OCI nodes",
    )
    observed_ids: set[str] = set()
    for entry in talos:
        require(isinstance(entry, dict), "invalid Talos version evidence")
        metadata = entry.get("metadata", {})
        node = entry.get("node")
        if node is None and isinstance(metadata, dict):
            node = metadata.get("node")
        require(bool(isinstance(node, str) and node), "Talos evidence has no node UUID")
        assert isinstance(node, str)
        observed_ids.add(node)
        spec = entry.get("spec", {})
        observed_version = spec.get("version") if isinstance(spec, dict) else None
        require(
            observed_version == talos_version,
            "Talos nodes do not all run the exact requested version",
        )
    require(
        observed_ids == selected_machine_ids,
        "Talos proof does not match the selected OCI machine UUIDs",
    )

    nodes = kubernetes_nodes.get("items")
    require(
        isinstance(nodes, list) and len(nodes) == EXPECTED_NODE_COUNT,
        "Kubernetes proof must contain exactly the two expected OCI nodes",
    )
    for node in nodes:
        require(isinstance(node, dict), "invalid Kubernetes node evidence")
        conditions = {
            condition.get("type"): condition.get("status")
            for condition in node.get("status", {}).get("conditions", [])
            if isinstance(condition, dict)
        }
        require(conditions.get("Ready") == "True", "a Kubernetes node is not Ready")

    observed_kubernetes = kubernetes_version.get("serverVersion", {}).get("gitVersion")
    require(
        observed_kubernetes == expected_kubernetes_version,
        "Kubernetes API version does not equal the requested release version",
    )


def main() -> int:
    """Parse workflow artifacts and return a non-zero status for any gap."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--machine-ids", type=Path, required=True)
    parser.add_argument("--talos-version-output", type=Path, required=True)
    parser.add_argument("--kubernetes-nodes", type=Path, required=True)
    parser.add_argument("--kubernetes-version", type=Path, required=True)
    parser.add_argument("--talos-version", required=True)
    parser.add_argument("--expected-kubernetes-version", required=True)
    args = parser.parse_args()
    try:
        verify(
            machine_ids(args.machine_ids),
            json_stream(args.talos_version_output),
            json.loads(args.kubernetes_nodes.read_text(encoding="utf-8")),
            json.loads(args.kubernetes_version.read_text(encoding="utf-8")),
            args.talos_version,
            args.expected_kubernetes_version,
        )
    except (OSError, ValueError, HealthError) as error:
        print(f"ERROR: release health verification failed: {error}", file=sys.stderr)
        return 1
    print(
        "OCI release health verified: exact selected Talos UUIDs and Kubernetes readiness"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
