"""Align the exact reviewed Flux 0.1.4 artifact with the pinned validator.

The new route narrows final media from public HTTPS to its explicit allowlist.
Retain all legacy hash pins and security assertions; add six route fixtures.
No production engine or validator source is changed.
"""
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
candidate = (root / "connectors/synthetiq-anime-direct.json").read_bytes()
digest = "b7d2db21993d60d4ebe491f467b88247e377e536310d16c8dfd6299240311bf3"
manifest = json.loads(candidate)
if hashlib.sha256(candidate).hexdigest() != digest or manifest["version"] != "0.1.4":
    raise SystemExit("Flux release bytes require a new fixture review")
if manifest["operations"]["streams"].get("finalMediaPolicy", "allowlisted") != "allowlisted":
    raise SystemExit("Reviewed Flux route must retain strict final-media policy")
path = root / "VireoCore/Tests/VireoCoreTests/DynamicMediaPolicyTests.swift"
source = path.read_text()
old = '            if manifest.id == "anikoto" {'
new = '''            if manifest.id == "synthetiq-anime-direct",
               Checksum.sha256Hex(of: try Data(contentsOf: url)) == "''' + digest + '''" {
                XCTAssertEqual(policy, .allowlisted, "reviewed Flux must stay strict")
                XCTAssertEqual(manifest.minimumAppVersion.description, "2.0.38")
            } else if manifest.id == "anikoto" {'''
if source.count(old) != 1:
    raise SystemExit("Pinned policy fixture changed; review required")
source = source.replace(old, new)
path.write_text(source)
fixture = Path(__file__).parent / "fixtures/FluxReleaseRouteTests.swift"
target = root / "VireoCore/Tests/VireoCoreTests/FluxReleaseRouteTests.swift"
if target.exists():
    raise SystemExit("Unexpected existing release fixture; review required")
target.write_bytes(fixture.read_bytes())
print("Aligned exact strict-policy Flux artifact; legacy hash gates retained; six route tests added")
