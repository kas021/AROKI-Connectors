"""Align pinned validator fixtures to exact reviewed AniKoto releases.

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
reviewed = {
    "0.3.8": ("c58e0ab74c384c3d52c43d1380be8dfc956b7522d88a417d7bcc89f2600bd51d", "active"),
    "0.3.9": ("90756caaa5f97f990453fba6aa010d2ded009b87641a3f638eedbfc12169e0dc", "retired"),
    "0.3.10": ("49e8a0f2baa49abf2534ad9522d86eafc0cca054c76ead2cff62e15823221413", "active"),
}
# Releases whose fixtures are committed in the pinned validator itself.
prealigned = {"0.3.10"}
version = manifest.get("version")
if version not in reviewed:
    raise SystemExit("AniKoto fixtures require review for this release version")
digest, status = reviewed[version]
if version in prealigned:
    if hashlib.sha256(candidate).hexdigest() != digest or manifest.get("status") != status:
        raise SystemExit("AniKoto candidate differs from reviewed release")
    print("Pinned validator already carries reviewed AniKage-route fixtures; no alignment needed")
    raise SystemExit(0)
if hashlib.sha256(candidate).hexdigest() != digest or manifest.get("status") != status:
    raise SystemExit("AniKoto candidate differs from reviewed release")
path = root / "VireoCore/Tests/VireoCoreTests/AniKotoConnectorTests.swift"
source = path.read_text()
replacements = {
    'SemanticVersion("0.3.6")': (f'SemanticVersion("{version}")', 1),
    '/stream/getSources?id=98765&type=sub': ('/stream/getSourcesNew?id=98765&type=sub', 2),
    '/stream/getSources?id=54321&type=dub': ('/stream/getSourcesNew?id=54321&type=dub', 2),
}
if status == "retired":
    replacements['XCTAssertEqual(manifest.status, .active)'] = ('XCTAssertEqual(manifest.status, .retired)', 1)
for old, (new, expected_count) in replacements.items():
    if source.count(old) == 0 and source.count(new) == expected_count:
        continue  # Reviewed expectation already exists in the newer validator.
    if source.count(old) != expected_count:
        raise SystemExit("Pinned AniKoto fixture changed; manual review required")
    source = source.replace(old, new)
path.write_text(source)
print("Aligned exact reviewed version/status and fixture routes; all assertions retained")
