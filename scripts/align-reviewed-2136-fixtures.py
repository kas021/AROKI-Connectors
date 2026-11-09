"""Install exact reviewed module fixtures; never change the engine or policy.

Existing catalogue/audio/caption assertions are retained. Candidate digests are
fixed, so arbitrary candidate changes cannot rewrite their own test contract.
"""
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
connector_id = sys.argv[2]
reviewed = {
    "anikoto": ("0.3.12", "dbfe00dcbd9c1841e26ebf76e120c99ee02306402b8f327d01855214f9aac25e", "typed-graph-context-v1"),
    "synthetiq-anime-testing": ("0.1.3", "67d5232e210d90873fb3dc04fdab4b576dfa2958fd4693e5476b0ac7821dd021", "typed-graph-context-v1"),
    "anime-sama-expansion": ("0.3.3", "3f4fd2b5b53454716f14438e60f47773189917bf048b5b66ea176032d6bd164b", "legacy-script-comments-v1"),
    "anipm": ("0.1.3", "49ee962133d6963439c75a896a49c28b6acad1a4c4aaa0ecec332b8a5c88245d", "typed-graph-context-v1"),
    "synthetiq-anime-direct": ("0.1.5", "2a3a8ab6dedb955e3b348c8c03558f00591c341d653305fff6b99865eb84800b", "typed-graph-context-v1"),
}
if connector_id not in reviewed:
    raise SystemExit("No reviewed 2.1.36 fixture contract for this connector")
version, digest, feature = reviewed[connector_id]
candidate = (root / f"connectors/{connector_id}.json").read_bytes()
manifest = json.loads(candidate)
if (hashlib.sha256(candidate).hexdigest() != digest or manifest.get("id") != connector_id
    or manifest.get("version") != version or manifest.get("minimumAppVersion") != "2.1.36"
    or feature not in manifest.get("requiredEngineFeatures", [])):
    raise SystemExit("Manifest differs from the reviewed compatibility release")
tests = root / "VireoCore/Tests/VireoCoreTests"
fixtures = Path(__file__).parent / "fixtures"
if connector_id == "anikoto":
    (tests / "AniKotoConnectorTests.swift").write_bytes((fixtures / "AniKotoReleaseRouteTests-0.3.12.swift").read_bytes())
    (tests / "RolloutAniKotoCandidateTests.swift").write_bytes((fixtures / "AniKotoCandidateGraphTests-0.3.12.swift").read_bytes())
elif connector_id in ("anipm", "synthetiq-anime-direct"):
    baseline_dir = root / "connectors/audio-guard-baselines"
    baseline_dir.mkdir(exist_ok=True)
    baseline_hashes = {
        "anipm": "85a888677f8f601978699f12f4ab64966f12a75ef13b646ecc5f1b12966f7e44",
        "synthetiq-anime-direct": "b7d2db21993d60d4ebe491f467b88247e377e536310d16c8dfd6299240311bf3",
    }
    for module, expected in baseline_hashes.items():
        baseline = (fixtures / f"{module}-audio-guard-baseline.json").read_bytes()
        if hashlib.sha256(baseline).hexdigest() != expected:
            raise SystemExit("Audio guard baseline fixture drifted; review required")
        (baseline_dir / f"{module}.json").write_bytes(baseline)
    (tests / "AudioContractGuardTests.swift").write_bytes((fixtures / "AudioContractGuardTests.swift").read_bytes())
    if connector_id == "synthetiq-anime-direct":
        if manifest["operations"]["streams"].get("finalMediaPolicy", "allowlisted") != "allowlisted":
            raise SystemExit("Reviewed Flux audio guard must retain strict final-media policy")
        path = tests / "DynamicMediaPolicyTests.swift"
        source = path.read_text()
        anchor = '            if manifest.id == "anikoto" {'
        replacement = ('            if manifest.id == "synthetiq-anime-direct",\n'
                       '               Checksum.sha256Hex(of: try Data(contentsOf: url)) == "' + digest + '" {\n'
                       '                XCTAssertEqual(policy, .allowlisted, "reviewed Flux must stay strict")\n'
                       '                XCTAssertEqual(manifest.minimumAppVersion.description, "2.1.36")\n'
                       '            } else if manifest.id == "anikoto" {')
        if source.count(anchor) != 1:
            raise SystemExit("Pinned Flux policy fixture drifted; review required")
        path.write_text(source.replace(anchor, replacement))
        (tests / "FluxReleaseRouteTests.swift").write_bytes((fixtures / "FluxReleaseRouteTests-0.1.5.swift").read_bytes())
else:
    path = tests / "DynamicMediaPolicyTests.swift"
    source = path.read_text()
    anchor = ('"ad1fc55f034fdaccff68fd64021165736ff760b14fc1f8e4aa64b9418f5077d1"'
              if connector_id == "synthetiq-anime-testing" else
              '"671258b736a3f857911c3aed0a0fb1ec5d3fd21d365fd023cfc01bd3279d692c"')
    if source.count(anchor) != 1 or digest in source:
        raise SystemExit("Pinned public-media policy fixture drifted; review required")
    # Append this exact reviewed artifact only. Do not remove any policy checks.
    path.write_text(source.replace(anchor, anchor + ',\n                "' + digest + '"'))
    if connector_id == "synthetiq-anime-testing":
        (tests / "SynthetiqAnimeCandidateGraphTests.swift").write_bytes((fixtures / "SynthetiqAnimeCandidateGraphTests-0.1.3.swift").read_bytes())
    else:
        (tests / "AnimeSamaVideoCardTests.swift").write_bytes((fixtures / "AnimeSamaVideoCardTests-0.3.3.swift").read_bytes())
print(f"Aligned exact reviewed {connector_id} {version} fixture contract; engine unchanged")
