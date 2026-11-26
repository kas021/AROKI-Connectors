"""Admit only the exact reviewed 26 Nov 2026 owner-kept republishes and pin each with a native test.

These modules were first published on 22 Nov 2026 with an untrue authorization
note. The owner reviewed them on 26 Nov 2026 and asked to keep them with the
note corrected. A metadata-only entry must equal its published release outside
version, releaseNotes and authorization.note.
"""
import hashlib
import json
import sys
from pathlib import Path

NOTE = ("First published on 22 Nov 2026 without the owner's authorization; reviewed and kept at "
        "the owner's request on 26 Nov 2026 after testing. Not a rights determination.")
OLD_NOTE = "Owner-requested conversion of a Synthetiq Player source for testing; not a rights determination."

REVIEWED = {
    "kickassanime": {
        "sha256": "c5204dc83cf8f7a9cd4a56969400bf1475537b0415b562aa6ff2341958ed6ae3",
        "version": "0.1.2",
        "published_sha256": "450ae9145c424a7f2a5318e8668e2216dfaeb65cc41e177dad290e96371f626d",
        "published_version": "0.1.1",
        "test_class": "KickAssAnimeKept012Tests",
    },
    "animeworld-it": {
        "sha256": "25c06687530e8181c62ae3e3cc8ddc523ae3b59f0180a10ea5698e02491e2871",
        "version": "0.1.1",
        "published_sha256": "c4835a61ecb9653013aa932ed20c24ba7f5c2a4a64636bdbaf21ad48a9fe9b15",
        "published_version": "0.1.0",
        "test_class": "AnimeWorldITKept011Tests",
    },
    "animeunity-it": {
        "sha256": "6e186e2ac5a2767a44ce9794e330d0911c19f2a8be5a10520202e4905ebf5cd9",
        "version": "0.1.1",
        "published_sha256": "b3357da92a9e36964e0c2a0490ec933c9250e2f3919f35dee6a5e9d82acb5072",
        "published_version": "0.1.0",
        "test_class": "AnimeUnityITKept011Tests",
    },
}

root = Path(sys.argv[1])
connector_id = sys.argv[2]
if connector_id not in REVIEWED:
    raise SystemExit("No reviewed 26 Nov 2026 republish for " + connector_id)
entry = REVIEWED[connector_id]

raw = (root / "connectors" / (connector_id + ".json")).read_bytes()
if hashlib.sha256(raw).hexdigest() != entry["sha256"]:
    raise SystemExit("Unreviewed " + connector_id + " republish bytes")
manifest = json.loads(raw)
assert manifest["id"] == connector_id and manifest["familyID"] == connector_id
assert manifest["status"] == "active"
assert manifest["version"] == entry["version"]
assert manifest["minimumAppVersion"] == "2.1.36"
assert manifest["authorization"] == {"basis": "personal", "note": NOTE}

public_root = Path(__file__).resolve().parent.parent
published_raw = (public_root / "connectors" / connector_id / "releases" / entry["published_sha256"] / "connector.json").read_bytes()
if hashlib.sha256(published_raw).hexdigest() != entry["published_sha256"]:
    raise SystemExit("Published " + connector_id + " release bytes changed")
published = json.loads(published_raw)
assert published["version"] == entry["published_version"] and published["status"] == "active"
assert published["authorization"] == {"basis": "personal", "note": OLD_NOTE}


def resolver(value):
    copy = json.loads(json.dumps(value))
    for key in ("version", "releaseNotes"):
        copy.pop(key)
    copy["authorization"].pop("note")
    return copy


if resolver(manifest) != resolver(published):
    raise SystemExit(connector_id + " republish is not metadata-only")

test = root / "VireoCore/Tests/VireoCoreTests" / (entry["test_class"] + ".swift")
if test.exists():
    raise SystemExit("Unexpected existing " + connector_id + " republish test")
test.write_text('''import XCTest
@testable import VireoCore

final class %(cls)s: XCTestCase {
    func testReviewedKeptManifestValidatesWithCorrectedNote() throws {
        let root = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("connectors/%(id)s.json"))
        XCTAssertEqual(Checksum.sha256Hex(of: data), "%(sha)s")
        let manifest = try ConnectorValidator.validate(manifestData: data)
        XCTAssertEqual(manifest.id, "%(id)s")
        XCTAssertEqual(manifest.familyID, "%(id)s")
        XCTAssertEqual(manifest.version.description, "%(version)s")
        XCTAssertEqual(manifest.minimumAppVersion.description, "2.1.36")
        XCTAssertEqual(manifest.status, .active)
        XCTAssertEqual(manifest.authorization.note, "%(note)s")
    }
}
''' % {"cls": entry["test_class"], "id": connector_id, "sha": entry["sha256"],
       "version": entry["version"], "note": NOTE})
print("Verified exact reviewed " + connector_id + " " + entry["version"]
      + "; identical to published " + entry["published_version"] + " outside version, releaseNotes and authorization.note")
