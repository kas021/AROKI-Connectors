import Foundation
import VireoCore

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let indexBytes = try Data(contentsOf: root.appendingPathComponent("index.json"))
let index = try RepositoryIndexVerifier.verify(indexData: indexBytes)
var object = try JSONSerialization.jsonObject(with: indexBytes) as! [String: Any]
var entries = object["connectors"] as! [[String: Any]]
var count = 0
for i in entries.indices {
    let id = entries[i]["id"] as! String
    guard id != "update-flow-test" else { continue }
    let path = "logos/\(id).png"
    let bytes = try Data(contentsOf: root.appendingPathComponent(path))
    let digest = Checksum.sha256Hex(of: bytes)
    try RepositoryIconValidator.validate(data: bytes, expectedSHA256: digest)
    entries[i]["icon"] = ["path": path, "sha256": digest]
    count += 1
}
object["connectors"] = entries
object.removeValue(forKey: "signature")
let unsigned = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
guard let key = ProcessInfo.processInfo.environment["AROKI_CONNECTOR_PRIVATE_KEY"], !key.isEmpty else {
    throw ValidationError("artwork", "Signing key is required; production data remains unchanged")
}
let canonical = try CanonicalJSON.canonicalData(fromJSONData: unsigned, removingTopLevelKeys: ["signature"])
object["signature"] = try PackageSignature.sign(payload: canonical, privateKeyBase64: key)
let signed = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
let catalogue = try RepositoryArtworkCatalogue.verify(data: signed, for: index)
guard catalogue.count == count, count == 10 else { throw ValidationError("artwork", "Unexpected logo coverage") }
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: temporary) }
let store = try ConnectorStore(rootDirectory: temporary, appVersion: SemanticVersion("2.1.36")!)
for entry in index.connectors {
    let manifest = try Data(contentsOf: root.appendingPathComponent(entry.manifest.path))
    _ = try RepositoryIndexVerifier.verifyAndCrossCheck(manifestData: manifest, entry: entry, indexPublicKey: index.publicKey)
    if entry.status == .retired {
        var rejectedAsRetired = false
        do {
            _ = try store.install(manifestData: manifest, iconData: nil, entry: entry, index: index)
        } catch {
            rejectedAsRetired = String(describing: error).contains("is retired and cannot be installed")
        }
        guard rejectedAsRetired, store.loadInstalled(familyID: entry.familyID) == nil else {
            throw ValidationError("artwork", "Retired connector installation was not safely rejected")
        }
        print("\(entry.id): signed retired manifest verified; new installation correctly blocked")
        continue
    }
    // Simulate existing no-logo installation, then upgrade artwork at the same identity/version.
    _ = try store.install(manifestData: manifest, iconData: nil, entry: entry, index: index)
    let image = try catalogue[RepositoryArtworkCatalogue.key(for: entry)].map { try Data(contentsOf: root.appendingPathComponent($0.path)) }
    if let image, let descriptor = catalogue[RepositoryArtworkCatalogue.key(for: entry)] {
        try store.applyArtwork(image, descriptor: descriptor, entry: entry, index: index)
    }
    guard let loaded = store.loadInstalled(familyID: entry.familyID), loaded.version == entry.version else {
        throw ValidationError("artwork", "Install/reload failed")
    }
    if let image {
        guard try Data(contentsOf: loaded.directory.appendingPathComponent("icon.png")) == image else {
            throw ValidationError("artwork", "Cached image differs")
        }
    }
    print("\(entry.id): existing identity preserved; manifest verified; install/reload passed")
}
guard try Data(contentsOf: root.appendingPathComponent("index.json")) == indexBytes else {
    throw ValidationError("artwork", "Primary index changed")
}
try signed.write(to: root.appendingPathComponent("artwork.json"), options: .atomic)
print("PASS: \(count) signed logos; primary index and manifests unchanged")
