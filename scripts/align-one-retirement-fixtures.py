"""Keep the pinned native fixtures testing the exact reviewed retirement."""
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
raw = (root / "connectors/synthetiq-one.json").read_bytes()
manifest = json.loads(raw)
if hashlib.sha256(raw).hexdigest() != "1541c90971a4923959d6fa052fa17d68e6f9dcbcc0ef7a0f4b5606ef5d251a5f":
    raise SystemExit("Unreviewed One retirement bytes")
assert manifest["status"] == "retired"
assert manifest["version"] == "1.2.12"
path = root / "VireoCore/Tests/VireoCoreTests/SynthetiqOneConnectorTests.swift"
source = path.read_text()
old = 'XCTAssertEqual(manifest.version.description, "1.2.11")'
assert source.count(old) == 1
path.write_text(source.replace(old, 'XCTAssertEqual(manifest.version.description, "1.2.12")\n        XCTAssertEqual(manifest.status, .retired)'))
