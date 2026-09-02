#!/usr/bin/env python3
"""Build an unsigned Aroki index from explicitly named connector manifests.

For personal/test feeds only. This never changes the signed official index.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import time
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a keyless Aroki index.json for an approved unsigned feed.")
    parser.add_argument("connector_ids", nargs="+", help="Connector IDs to include, e.g. anikage animekai")
    parser.add_argument("--repository-id", required=True, help="Stable lowercase repository ID")
    parser.add_argument("--name", required=True, help="Display name")
    parser.add_argument("--output", default="index.json", help="Output path relative to repository root")
    parser.add_argument("--generated-at", type=int, default=int(time.time()), help="UTC epoch for this index")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    entries = []
    for connector_id in args.connector_ids:
        manifest_path = root / "connectors" / connector_id / "connector.json"
        raw = manifest_path.read_bytes()
        manifest = json.loads(raw)
        if manifest.get("id") != connector_id:
            raise SystemExit(f"ERROR: {manifest_path} id does not match {connector_id}")
        required = ("familyID", "name", "version", "contentType", "language", "contentRating", "releaseTrack", "status", "minimumAppVersion")
        missing = [key for key in required if key not in manifest]
        if missing:
            raise SystemExit(f"ERROR: {connector_id} missing index fields: {', '.join(missing)}")
        entry = {key: manifest[key] for key in required}
        entry["id"] = connector_id
        entry["releaseNotes"] = manifest.get("releaseNotes", "")
        entry["manifest"] = {
            "path": f"connectors/{connector_id}/connector.json",
            "sha256": hashlib.sha256(raw).hexdigest(),
        }
        entries.append(entry)

    index = {
        "schemaVersion": 1,
        "repositoryID": args.repository_id,
        "name": args.name,
        "enabled": True,
        "generatedAt": args.generated_at,
        "connectors": entries,
    }
    output = (root / args.output).resolve()
    if root not in output.parents:
        raise SystemExit("ERROR: output must remain inside the repository")
    output.write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"WROTE: {output.relative_to(root)} with {len(entries)} connector(s).")


if __name__ == "__main__":
    main()
