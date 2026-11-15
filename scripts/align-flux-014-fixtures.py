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
# Reviewed 0.1.6 (card genres/year/status for Find a niche; routes unchanged, strict final-media policy).
digest_016 = "71db638ec3b050502c2c7728d33fc17c98319e530a728ff41c2f77c3e4bb1981"
if hashlib.sha256(candidate).hexdigest() == digest_016:
    if (manifest["version"] != "0.1.6" or manifest["minimumAppVersion"] != "2.1.36"
        or manifest["operations"]["streams"].get("finalMediaPolicy", "allowlisted") != "allowlisted"):
        raise SystemExit("Reviewed Flux 0.1.6 must keep minimum 2.1.36 and strict final-media policy")
    tests = root / "VireoCore/Tests/VireoCoreTests"
    path = tests / "DynamicMediaPolicyTests.swift"
    source = path.read_text()
    anchor = '            if manifest.id == "anikoto" {'
    replacement = ('            if manifest.id == "synthetiq-anime-direct",\n'
                   '               Checksum.sha256Hex(of: try Data(contentsOf: url)) == "' + digest_016 + '" {\n'
                   '                XCTAssertEqual(policy, .allowlisted, "reviewed Flux must stay strict")\n'
                   '                XCTAssertEqual(manifest.minimumAppVersion.description, "2.1.36")\n'
                   '            } else if manifest.id == "anikoto" {')
    if source.count(anchor) != 1:
        raise SystemExit("Pinned Flux policy fixture drifted; review required")
    path.write_text(source.replace(anchor, replacement))
    fixtures = Path(__file__).parent / "fixtures"
    for name, target in (("FluxReleaseRouteTests-0.1.6.swift", "FluxReleaseRouteTests.swift"),
                         ("NicheCardMetadataTests-flux-0.1.6.swift", "FluxNicheCardTests.swift")):
        if (tests / target).exists():
            raise SystemExit("Unexpected existing release fixture; review required")
        (tests / target).write_bytes((fixtures / name).read_bytes())
    print("Aligned exact reviewed Flux 0.1.6: strict policy retained, route and card-metadata fixtures added")
    raise SystemExit(0)
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
