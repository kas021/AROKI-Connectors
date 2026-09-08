"""Align pinned validator fixtures to the reviewed AniKoto 0.3.8 release.

Only the expected version and two synthetic request URLs change. All catalogue,
SUB/DUB, subtitle and policy assertions remain intact. Never edit engine code.
This intentionally fails closed if the release bytes or pinned tests drift.
"""
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
candidate = (root / "connectors/anikoto.json").read_bytes()
manifest = json.loads(candidate)
if manifest.get("version") != "0.3.8":
    raise SystemExit("AniKoto fixtures require review for this release version")
if hashlib.sha256(candidate).hexdigest() != "c58e0ab74c384c3d52c43d1380be8dfc956b7522d88a417d7bcc89f2600bd51d":
    raise SystemExit("AniKoto candidate differs from reviewed release")
path = root / "VireoCore/Tests/VireoCoreTests/AniKotoConnectorTests.swift"
source = path.read_text()
replacements = {
    'SemanticVersion("0.3.6")': 'SemanticVersion("0.3.8")',
    '/stream/getSources?id=98765&type=sub': '/stream/getSourcesNew?id=98765&type=sub',
    '/stream/getSources?id=54321&type=dub': '/stream/getSourcesNew?id=54321&type=dub',
}
for old, new in replacements.items():
    if source.count(old) != 1:
        raise SystemExit("Pinned AniKoto fixture changed; manual review required")
    source = source.replace(old, new)
path.write_text(source)
print("Aligned three AniKoto fixture literals; all test assertions retained")
