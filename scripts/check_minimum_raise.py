#!/usr/bin/env python3
"""Read-only gate for an explicitly approved Aroki minimum-version raise.

This lane proposal does not sign, edit, publish, or verify repository
signatures. The eventual workflow must first run the pinned vireo-tool
`verify-repository` against the current signed index and a frozen legacy branch.
The approval registry intentionally starts empty: all minimum raises fail
closed until an owner-reviewed candidate is added.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


COMPATIBILITY_FLOOR = "2.1.36"
PINNED_PUBLISHER_SHA256 = "4beeee75737bb3f22e190e2fa2a5205cd86b3569d0b640555302c84303dbf056"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
VERSION_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")

REGISTRY_KEYS = {
    "connectorID",
    "familyID",
    "candidateCommit",
    "candidateSHA256",
    "baselineVersion",
    "baselineMinimumAppVersion",
    "baselineIndexSHA256",
    "baseMainCommit",
    "legacyBranchCommit",
    "legacyIndexSHA256",
    "minimumAppVersion",
    "publisherScriptSHA256",
}


class GateError(ValueError):
    """A migration prerequisite was not met."""


def _semver(value: Any, field: str) -> tuple[int, int, int]:
    if not isinstance(value, str) or VERSION_RE.fullmatch(value) is None:
        raise GateError(f"{field} must be numeric major.minor.patch")
    return tuple(int(part) for part in value.split("."))


def _digest(value: Any, field: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise GateError(f"{field} must be a lowercase SHA-256 digest")
    return value


def _commit(value: Any, field: str) -> str:
    if not isinstance(value, str) or COMMIT_RE.fullmatch(value) is None:
        raise GateError(f"{field} must be a full 40-character commit SHA")
    return value


def _index_entry(index: dict[str, Any], connector_id: str) -> dict[str, Any]:
    entries = index.get("connectors")
    if not isinstance(entries, list):
        raise GateError("signed index must contain a connectors array")
    matches = [entry for entry in entries if isinstance(entry, dict) and entry.get("id") == connector_id]
    if len(matches) != 1:
        raise GateError("signed index must contain exactly one entry for connector ID")
    return matches[0]


def _registry_entry(registry: dict[str, Any], connector_id: str) -> dict[str, Any] | None:
    if not isinstance(registry, dict):
        raise GateError("approval registry must be an object")
    if registry.get("schemaVersion") != 1:
        raise GateError("approval registry schema is invalid")
    approvals = registry.get("approvedRaises")
    if not isinstance(approvals, list):
        raise GateError("approval registry must contain an approvedRaises array")
    matches: list[dict[str, Any]] = []
    for entry in approvals:
        if not isinstance(entry, dict) or set(entry) != REGISTRY_KEYS:
            raise GateError("approval registry entry has unexpected or missing fields")
        if entry.get("connectorID") == connector_id:
            matches.append(entry)
    if len(matches) > 1:
        raise GateError("approval registry has duplicate connector approvals")
    return matches[0] if matches else None


def authorize_raise(
    *,
    connector_id: str,
    manifest_bytes: bytes,
    index_bytes: bytes,
    registry: dict[str, Any],
    compatibility_floor: str,
    expected_candidate_commit: str,
    observed_candidate_commit: str,
    expected_manifest_sha256: str,
    base_main_commit: str,
    legacy_branch_commit: str,
    legacy_index_sha256: str,
    publisher_script_sha256: str,
) -> dict[str, str]:
    """Return a non-secret decision, or raise GateError without writing files."""
    if not re.fullmatch(r"[a-z0-9-]+", connector_id):
        raise GateError("connector ID is invalid")
    expected_commit = _commit(expected_candidate_commit, "expected candidate commit")
    observed_commit = _commit(observed_candidate_commit, "observed candidate commit")
    if expected_commit != observed_commit:
        raise GateError("observed candidate commit does not match approved commit")
    base_commit = _commit(base_main_commit, "base main commit")
    legacy_commit = _commit(legacy_branch_commit, "legacy branch commit")
    expected_hash = _digest(expected_manifest_sha256, "expected manifest SHA-256")
    legacy_hash = _digest(legacy_index_sha256, "legacy index SHA-256")
    publisher_hash = _digest(publisher_script_sha256, "publisher script SHA-256")

    actual_hash = hashlib.sha256(manifest_bytes).hexdigest()
    if actual_hash != expected_hash:
        raise GateError("candidate manifest bytes do not match expected SHA-256")

    try:
        manifest = json.loads(manifest_bytes)
        index = json.loads(index_bytes)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise GateError("candidate manifest or signed index is not valid JSON") from exc
    if not isinstance(manifest, dict) or not isinstance(index, dict):
        raise GateError("candidate manifest and signed index must be objects")
    if manifest.get("id") != connector_id:
        raise GateError("candidate ID does not match requested connector ID")

    old = _index_entry(index, connector_id)
    family_id = manifest.get("familyID")
    if not isinstance(family_id, str) or not family_id or old.get("familyID") != family_id:
        raise GateError("candidate familyID does not match the published entry")

    candidate_version = _semver(manifest.get("version"), "candidate version")
    baseline_version = _semver(old.get("version"), "published version")
    if candidate_version <= baseline_version:
        raise GateError("candidate version must be a strict upgrade")
    candidate_minimum = _semver(manifest.get("minimumAppVersion"), "candidate minimumAppVersion")
    baseline_minimum = _semver(old.get("minimumAppVersion"), "published minimumAppVersion")
    if candidate_minimum <= baseline_minimum:
        return {"decision": "no-minimum-raise", "connectorID": connector_id, "candidateSHA256": actual_hash}

    if compatibility_floor != COMPATIBILITY_FLOOR:
        raise GateError("minimum raise requires exact compatibility floor 2.1.36")
    if candidate_minimum != _semver(COMPATIBILITY_FLOOR, "compatibility floor"):
        raise GateError("raised candidate minimum must equal compatibility floor 2.1.36")
    if publisher_hash != PINNED_PUBLISHER_SHA256:
        raise GateError("pinned publisher script has drifted")

    approval = _registry_entry(registry, connector_id)
    if approval is None:
        raise GateError("no owner-reviewed candidate approval exists; registry is fail-closed")
    baseline_index_hash = hashlib.sha256(index_bytes).hexdigest()
    expected_fields = {
        "connectorID": connector_id,
        "familyID": family_id,
        "candidateCommit": expected_commit,
        "candidateSHA256": actual_hash,
        "baselineVersion": old.get("version"),
        "baselineMinimumAppVersion": old.get("minimumAppVersion"),
        "baselineIndexSHA256": baseline_index_hash,
        "baseMainCommit": base_commit,
        "legacyBranchCommit": legacy_commit,
        "legacyIndexSHA256": legacy_hash,
        "minimumAppVersion": COMPATIBILITY_FLOOR,
        "publisherScriptSHA256": PINNED_PUBLISHER_SHA256,
    }
    for key, expected in expected_fields.items():
        if approval.get(key) != expected:
            raise GateError(f"approval registry mismatch: {key}")
    return {"decision": "approved-exact-floor-raise", "connectorID": connector_id, "candidateSHA256": actual_hash}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--connector-id", required=True)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--index", required=True, type=Path, help="must be verified by vireo-tool first")
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--compatibility-floor", required=True)
    parser.add_argument("--expected-candidate-commit", required=True)
    parser.add_argument("--observed-candidate-commit", required=True)
    parser.add_argument("--expected-manifest-sha256", required=True)
    parser.add_argument("--base-main-commit", required=True)
    parser.add_argument("--legacy-branch-commit", required=True)
    parser.add_argument("--legacy-index-sha256", required=True)
    parser.add_argument("--publisher-script", required=True, type=Path)
    args = parser.parse_args(argv)

    try:
        manifest_bytes = args.candidate.read_bytes()
        index_bytes = args.index.read_bytes()
        registry = json.loads(args.registry.read_bytes())
        publisher_hash = hashlib.sha256(args.publisher_script.read_bytes()).hexdigest()
        decision = authorize_raise(
            connector_id=args.connector_id,
            manifest_bytes=manifest_bytes,
            index_bytes=index_bytes,
            registry=registry,
            compatibility_floor=args.compatibility_floor,
            expected_candidate_commit=args.expected_candidate_commit,
            observed_candidate_commit=args.observed_candidate_commit,
            expected_manifest_sha256=args.expected_manifest_sha256,
            base_main_commit=args.base_main_commit,
            legacy_branch_commit=args.legacy_branch_commit,
            legacy_index_sha256=args.legacy_index_sha256,
            publisher_script_sha256=publisher_hash,
        )
    except (OSError, json.JSONDecodeError, GateError) as exc:
        print(f"minimum-raise gate: BLOCKED: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(decision, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
