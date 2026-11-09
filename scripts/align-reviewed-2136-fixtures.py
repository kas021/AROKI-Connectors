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
    "anikoto": ("0.3.12", "dbfe00dcbd9c1841e26ebf76e120c99ee02306402b8f327d01855214f9aac25e"),
    "synthetiq-anime-testing": ("0.1.3", "67d5232e210d90873fb3dc04fdab4b576dfa2958fd4693e5476b0ac7821dd021"),
}
if connector_id not in reviewed:
    raise SystemExit("No reviewed 2.1.36 fixture contract for this connector")
version, digest = reviewed[connector_id]
candidate = (root / f"connectors/{connector_id}.json").read_bytes()
manifest = json.loads(candidate)
if (hashlib.sha256(candidate).hexdigest() != digest or manifest.get("id") != connector_id
    or manifest.get("version") != version or manifest.get("minimumAppVersion") != "2.1.36"
    or "typed-graph-context-v1" not in manifest.get("requiredEngineFeatures", [])):
    raise SystemExit("Manifest differs from the reviewed compatibility release")
tests = root / "VireoCore/Tests/VireoCoreTests"
fixtures = Path(__file__).parent / "fixtures"
if connector_id == "anikoto":
    (tests / "AniKotoConnectorTests.swift").write_bytes((fixtures / "AniKotoReleaseRouteTests-0.3.12.swift").read_bytes())
    (tests / "RolloutAniKotoCandidateTests.swift").write_bytes((fixtures / "AniKotoCandidateGraphTests-0.3.12.swift").read_bytes())
else:
    path = tests / "DynamicMediaPolicyTests.swift"
    source = path.read_text()
    anchor = '"ad1fc55f034fdaccff68fd64021165736ff760b14fc1f8e4aa64b9418f5077d1"'
    if source.count(anchor) != 1 or digest in source:
        raise SystemExit("Pinned public-media policy fixture drifted; review required")
    # Append this exact reviewed artifact only. Do not remove any policy checks.
    path.write_text(source.replace(anchor, anchor + ',\n                "' + digest + '"'))
    (tests / "SynthetiqAnimeCandidateGraphTests.swift").write_bytes((fixtures / "SynthetiqAnimeCandidateGraphTests-0.1.3.swift").read_bytes())
print(f"Aligned exact reviewed {connector_id} {version} fixture contract; engine unchanged")
