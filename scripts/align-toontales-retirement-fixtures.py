"""Admit only the exact reviewed ToonTales retirement and pin it with a native test."""
import hashlib
import json
import sys
from pathlib import Path

REVIEWED_SHA256 = "ee95132cb0c1f1c67e50f20a0a8dcdb56c79065cf184867877ca10f819e4eb01"
PUBLISHED_SHA256 = "7c8c0121abfbe5104aa4845cf677b2c365a7c58617e42a394aac3c8563a9eea3"

root = Path(sys.argv[1])
raw = (root / "connectors/toontales.json").read_bytes()
if hashlib.sha256(raw).hexdigest() != REVIEWED_SHA256:
    raise SystemExit("Unreviewed ToonTales retirement bytes")
manifest = json.loads(raw)
assert manifest["id"] == "toontales" and manifest["familyID"] == "toontales"
assert manifest["status"] == "retired"
assert manifest["version"] == "0.1.1"
assert manifest["minimumAppVersion"] == "2.1.36"

# Metadata-only: everything except these fields must equal the published 0.1.0 release.
public_root = Path(__file__).resolve().parent.parent
published_raw = (public_root / "connectors/toontales/releases" / PUBLISHED_SHA256 / "connector.json").read_bytes()
if hashlib.sha256(published_raw).hexdigest() != PUBLISHED_SHA256:
    raise SystemExit("Published ToonTales 0.1.0 release bytes changed")
published = json.loads(published_raw)
assert published["version"] == "0.1.0" and published["status"] == "active"


def resolver(value):
    copy = json.loads(json.dumps(value))
    for key in ("version", "status", "releaseNotes"):
        copy.pop(key)
    copy["authorization"].pop("note")
    return copy


if resolver(manifest) != resolver(published):
    raise SystemExit("ToonTales retirement is not metadata-only")

test = root / "VireoCore/Tests/VireoCoreTests/ToonTalesRetirementTests.swift"
if test.exists():
    raise SystemExit("Unexpected existing ToonTales retirement test")
test.write_text('''import XCTest
@testable import VireoCore

final class ToonTalesRetirementTests: XCTestCase {
    func testReviewedRetirementManifestValidatesAsRetired() throws {
        let root = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("connectors/toontales.json"))
        XCTAssertEqual(Checksum.sha256Hex(of: data), "%s")
        let manifest = try ConnectorValidator.validate(manifestData: data)
        XCTAssertEqual(manifest.id, "toontales")
        XCTAssertEqual(manifest.familyID, "toontales")
        XCTAssertEqual(manifest.version.description, "0.1.1")
        XCTAssertEqual(manifest.minimumAppVersion.description, "2.1.36")
        XCTAssertEqual(manifest.status, .retired)
    }
}
''' % REVIEWED_SHA256)
print("Verified exact reviewed ToonTales retirement; resolver identical to published 0.1.0")
