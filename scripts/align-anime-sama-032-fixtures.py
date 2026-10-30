"""Align the reviewed Anime-Sama 0.3.2 artifact with the pinned policy fixture.

Only adds the exact reviewed artifact hash to the existing allowlist. The pinned
public-https policy and bounded-mirrors feature assertions are retained.
Fails closed if the bytes or the pinned fixture drift.
"""
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
candidate = (root / "connectors/anime-sama-expansion.json").read_bytes()
manifest = json.loads(candidate)
reviewed_sha = "ecfa3ce07a0bd165149ce81ca3e62c17b932592b77404d1b5f7140fb289a3929"
reviewed_version = "0.3.2"

if manifest.get("id") != "anime-sama-expansion" or manifest.get("version") != reviewed_version:
    raise SystemExit("Anime-Sama candidate is not the reviewed 0.3.2 release")
if hashlib.sha256(candidate).hexdigest() != reviewed_sha:
    raise SystemExit("Anime-Sama candidate differs from the reviewed release")
mirrors = manifest.get("operations", {}).get("streams", {}).get("mirrors") or []
if not mirrors or any(m.get("finalMediaPolicy") != "public-https" for m in mirrors):
    raise SystemExit("Reviewed Anime-Sama release must retain public-https on every mirror")
if "bounded-mirrors-v1" not in (manifest.get("requiredEngineFeatures") or []):
    raise SystemExit("Reviewed Anime-Sama release must retain bounded mirrors")

path = root / "VireoCore/Tests/VireoCoreTests/DynamicMediaPolicyTests.swift"
source = path.read_text()
old = '''            "anime-sama-expansion": [
                "671258b736a3f857911c3aed0a0fb1ec5d3fd21d365fd023cfc01bd3279d692c"
            ]'''
new = '''            "anime-sama-expansion": [
                "671258b736a3f857911c3aed0a0fb1ec5d3fd21d365fd023cfc01bd3279d692c",
                "ecfa3ce07a0bd165149ce81ca3e62c17b932592b77404d1b5f7140fb289a3929"
            ]'''
if source.count(old) != 1:
    raise SystemExit("Pinned Anime-Sama policy fixture changed; manual review required")
path.write_text(source.replace(old, new))
print("Added reviewed Anime-Sama 0.3.2 artifact hash; policy and feature assertions retained")
