"""Install regression tests for the exact reviewed URL-only AniKage repair."""
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
candidate = (root / "connectors/anikage.json").read_bytes()
manifest = json.loads(candidate)
if (hashlib.sha256(candidate).hexdigest() != "11efcc77ff1e85383b55d776f9aaf9580554ba3c7b96d8fbd3c7eea4fe6406cd"
    or manifest.get("id") != "anikage" or manifest.get("familyID") != "anikage"
    or manifest.get("version") != "0.3.6" or manifest.get("minimumAppVersion") != "0.1.0"):
    raise SystemExit("AniKage candidate is not the exact reviewed legacy-compatible release")
fixture = Path(__file__).parent / "fixtures/AniKageSourceURLTests-0.3.6.swift"
(root / "VireoCore/Tests/VireoCoreTests/AniKageSourceURLTests.swift").write_bytes(fixture.read_bytes())
print("Added exact reviewed AniKage URL-shape tests; host policy and engine unchanged")
