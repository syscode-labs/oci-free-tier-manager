#!/usr/bin/env python3
"""Fail-closed validation for controller-originated OCI Talos release requests."""

from __future__ import annotations

import json
import os
import re
import sys
from collections.abc import Mapping, Sequence

CONTROLLER_REPOSITORY = "syscode-labs/talos-release-controller"
RELEASE_SOURCE_REPOSITORY = "syscode-labs/syscode-homelab-gitops-apps"
OCI_INSTALLER_REPOSITORY = "ghcr.io/syscode-labs/talos-images/installer"
ALLOWED_TALOS_TARGETS = frozenset(
    {
        "oci_core_instance.ampere_instance[0]",
        "oci_core_instance.ampere_instance[1]",
    }
)
RELEASE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
OCI_IMAGE_OCID_RE = re.compile(r"^ocid1\.image\.[A-Za-z0-9._-]+$")
VERSION_RE = re.compile(r"^v?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")


class DispatchError(ValueError):
    """Raised when a release request cannot safely enter the OCI executor."""


def _string(value: object, name: str) -> str:
    if not isinstance(value, str) or not value:
        raise DispatchError(f"{name} is required")
    return value


def _exact_keys(value: Mapping[str, object], expected: set[str], name: str) -> None:
    if set(value) != expected:
        raise DispatchError(f"{name} has unexpected or missing fields")


def _string_list(value: object, name: str) -> list[str]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        raise DispatchError(f"{name} must be a list")
    items = list(value)
    if not all(isinstance(item, str) and item for item in items):
        raise DispatchError(f"{name} must contain non-empty strings")
    if len(set(items)) != len(items):
        raise DispatchError(f"{name} must not contain duplicates")
    return items  # type: ignore[return-value]


def validate_payload(payload: object) -> dict[str, object]:
    """Validate and normalize the exact controller contract for one OCI delivery."""
    if not isinstance(payload, Mapping):
        raise DispatchError("release payload must be an object")
    required = {
        "release_id",
        "source_repo",
        "source_sha",
        "sender_repo",
        "idempotency_key",
        "build_run_id",
        "talos_version",
        "kubernetes_version",
        "artifacts",
        "oci_scope",
    }
    missing = required - set(payload)
    if missing:
        raise DispatchError(
            f"release payload is missing required fields: {', '.join(sorted(missing))}"
        )
    _exact_keys(payload, required, "release payload")

    release_id = _string(payload.get("release_id"), "release_id")
    if not RELEASE_ID_RE.fullmatch(release_id):
        raise DispatchError("invalid release_id")
    if payload.get("idempotency_key") != release_id:
        raise DispatchError("idempotency_key must equal release_id")
    if payload.get("sender_repo") != CONTROLLER_REPOSITORY:
        raise DispatchError("request did not originate from the release controller")
    if payload.get("source_repo") != RELEASE_SOURCE_REPOSITORY:
        raise DispatchError("unexpected approved release source")
    source_sha = _string(payload.get("source_sha"), "source_sha")
    if not SHA_RE.fullmatch(source_sha):
        raise DispatchError("source_sha must be a lowercase 40-character SHA")
    build_run_id = payload.get("build_run_id")
    if (
        not isinstance(build_run_id, int)
        or isinstance(build_run_id, bool)
        or build_run_id <= 0
    ):
        raise DispatchError("build_run_id must be a positive integer")
    talos_version = _string(payload.get("talos_version"), "talos_version")
    if not VERSION_RE.fullmatch(talos_version):
        raise DispatchError("invalid talos_version")
    kubernetes_version = _string(
        payload.get("kubernetes_version"), "kubernetes_version"
    )
    if not VERSION_RE.fullmatch(kubernetes_version):
        raise DispatchError("invalid kubernetes_version")

    artifacts = payload.get("artifacts")
    if not isinstance(artifacts, Mapping):
        raise DispatchError("artifacts must be an object")
    _exact_keys(artifacts, {"unraid", "oci"}, "artifacts")
    oci = artifacts.get("oci")
    unraid = artifacts.get("unraid")
    if not isinstance(oci, Mapping) or not isinstance(unraid, Mapping):
        raise DispatchError("artifacts must contain OCI and Unraid artifact objects")
    _exact_keys(oci, {"ref", "digest", "image_ocid"}, "OCI artifact")
    _exact_keys(unraid, {"ref", "digest"}, "Unraid artifact")
    expected_oci_ref = f"{OCI_INSTALLER_REPOSITORY}:{talos_version}"
    expected_unraid_ref = f"{OCI_INSTALLER_REPOSITORY}:{talos_version}-libvirt"
    if oci.get("ref") != expected_oci_ref or unraid.get("ref") != expected_unraid_ref:
        raise DispatchError("artifact refs do not match the approved Talos version")
    for artifact, name in ((oci, "OCI"), (unraid, "Unraid")):
        digest = artifact.get("digest")
        if not isinstance(digest, str) or not DIGEST_RE.fullmatch(digest):
            raise DispatchError(f"invalid {name} artifact digest")
    image_ocid = oci.get("image_ocid")
    if not isinstance(image_ocid, str) or not OCI_IMAGE_OCID_RE.fullmatch(image_ocid):
        raise DispatchError("invalid OCI custom-image OCID")

    scope = payload.get("oci_scope")
    if not isinstance(scope, Mapping):
        raise DispatchError("oci_scope is required")
    _exact_keys(scope, {"targets", "replace"}, "oci_scope")
    targets = _string_list(scope.get("targets"), "oci_scope.targets")
    replacements = _string_list(scope.get("replace"), "oci_scope.replace")
    if not targets:
        raise DispatchError("oci_scope.targets must not be empty")
    if not set(targets).issubset(ALLOWED_TALOS_TARGETS):
        raise DispatchError(
            "oci_scope.targets contains a non-Talos or unapproved address"
        )
    if not set(replacements).issubset(set(targets)):
        raise DispatchError("oci_scope.replace must be a subset of oci_scope.targets")

    return {
        "release_id": release_id,
        "source_repo": RELEASE_SOURCE_REPOSITORY,
        "source_sha": source_sha,
        "sender_repo": CONTROLLER_REPOSITORY,
        "idempotency_key": release_id,
        "build_run_id": build_run_id,
        "talos_version": talos_version,
        "kubernetes_version": payload["kubernetes_version"],
        "artifacts": {"unraid": dict(unraid), "oci": dict(oci)},
        "oci_scope": {"targets": targets, "replace": replacements},
    }


def main() -> int:
    """Read PAYLOAD, validate it, and write a normalized private artifact."""
    try:
        payload = json.loads(os.environ.get("PAYLOAD", ""))
        normalized = validate_payload(payload)
        output_path = os.environ.get("RELEASE_REQUEST_PATH", "release-request.json")
        with open(output_path, "w", encoding="utf-8") as handle:
            json.dump(normalized, handle, sort_keys=True)
            handle.write("\n")
    except (DispatchError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
