"""Install the exact reviewed Synthetiq Anime 0.1.4 fixture contract; never change the engine or policy.

0.1.4 only adds card genres/year/status. The public-media policy list is extended with this exact
reviewed digest (no check removed), the reviewed 0.1.3 graph fixtures are re-versioned, and card-metadata
regressions are added. The digest is fixed, so a changed candidate cannot rewrite its own contract.
"""
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
digest = "a8f250f5fde24744d451ca8d93e1bcf920b8756935e48212e61bf545db50c6eb"
candidate = (root / "connectors/synthetiq-anime-testing.json").read_bytes()
manifest = json.loads(candidate)
if (hashlib.sha256(candidate).hexdigest() != digest or manifest.get("id") != "synthetiq-anime-testing"
        or manifest.get("version") != "0.1.4" or manifest.get("minimumAppVersion") != "2.1.36"
        or "typed-graph-context-v1" not in manifest.get("requiredEngineFeatures", [])):
    raise SystemExit("Manifest differs from the reviewed Synthetiq Anime 0.1.4 release")
tests = root / "VireoCore/Tests/VireoCoreTests"
fixtures = Path(__file__).parent / "fixtures"
path = tests / "DynamicMediaPolicyTests.swift"
source = path.read_text()
anchor = '"ad1fc55f034fdaccff68fd64021165736ff760b14fc1f8e4aa64b9418f5077d1"'
if source.count(anchor) != 1 or digest in source:
    raise SystemExit("Pinned public-media policy fixture drifted; review required")
# Append this exact reviewed artifact only. Do not remove any policy checks.
path.write_text(source.replace(anchor, anchor + ',\n                "' + digest + '"'))
for name, target in (("SynthetiqAnimeCandidateGraphTests-0.1.4.swift", "SynthetiqAnimeCandidateGraphTests.swift"),
                     ("NicheCardMetadataTests-synthetiq-anime-0.1.4.swift", "SynthetiqAnimeNicheCardTests.swift")):
    if (tests / target).exists():
        raise SystemExit("Unexpected existing release fixture; review required")
    (tests / target).write_bytes((fixtures / name).read_bytes())
print("Aligned exact reviewed Synthetiq Anime 0.1.4 fixture contract; engine unchanged")
