#!/usr/bin/env python3
"""Portable preflight for an explicitly user-approved unsigned Aroki feed.

This does not sign, publish, or certify a connector. It catches the common
repository-shape mistakes on Windows before a user pushes a candidate branch.
The native Aroki app remains the authoritative schema and media validator.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


IDENTIFIER = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
HOST = re.compile(r"^(\*\.)?[a-z0-9][a-z0-9.-]{0,251}[a-z0-9]$")
FORBIDDEN_TEXT = ("javascript:", "<script", "webview", "eval(")


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def walk_strings(value: object):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from walk_strings(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from walk_strings(item)


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate an Aroki connector's portable repository shape.")
    parser.add_argument("connector_id", help="Connector directory and manifest id, e.g. anikage")
    args = parser.parse_args()

    connector_id = args.connector_id.strip().lower()
    if not IDENTIFIER.fullmatch(connector_id):
        fail("connector id must be lowercase letters, numbers, and hyphens")

    root = Path(__file__).resolve().parents[1]
    manifest_path = root / "connectors" / connector_id / "connector.json"
    if not manifest_path.is_file():
        fail(f"missing {manifest_path.relative_to(root)}")
    if manifest_path.stat().st_size > 512 * 1024:
        fail("connector manifest exceeds 512 KiB")

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"invalid JSON: {error}")
    if not isinstance(manifest, dict):
        fail("connector root must be an object")

    required = {"schemaVersion", "id", "familyID", "name", "version", "allowedHosts", "operations"}
    missing = sorted(required - set(manifest))
    if missing:
        fail("missing required fields: " + ", ".join(missing))
    if manifest["id"] != connector_id:
        fail("manifest id must match connector directory")
    if not isinstance(manifest["familyID"], str) or not IDENTIFIER.fullmatch(manifest["familyID"]):
        fail("familyID must be a lowercase identifier")
    if not isinstance(manifest["version"], str) or not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", manifest["version"]):
        fail("version must be semantic, e.g. 1.2.3")
    if not isinstance(manifest["operations"], dict) or not manifest["operations"]:
        fail("operations must be a non-empty object")

    hosts = manifest["allowedHosts"]
    if not isinstance(hosts, list) or not hosts or len(hosts) > 32:
        fail("allowedHosts must contain between 1 and 32 hosts")
    for host in hosts:
        if not isinstance(host, str) or not HOST.fullmatch(host) or "://" in host:
            fail(f"invalid allowed host: {host!r}")
        lowered = host.lower()
        if lowered in {"localhost", "127.0.0.1", "::1"} or re.fullmatch(r"\d+(\.\d+){3}", lowered):
            fail(f"local or IP host is not allowed: {host}")

    for text in walk_strings(manifest):
        lowered = text.lower()
        if any(token in lowered for token in FORBIDDEN_TEXT):
            fail("manifest contains executable or browser-only content")

    print(f"PASS: {connector_id} {manifest['version']} passed portable structural preflight.")
    print("Next: run the native macOS certification gate before calling playback verified.")


if __name__ == "__main__":
    main()
