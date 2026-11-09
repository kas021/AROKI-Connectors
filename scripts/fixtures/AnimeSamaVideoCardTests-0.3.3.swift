import XCTest
@testable import VireoCore

final class AnimeSamaVideoCardTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath:#filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func manifest() throws -> ConnectorManifest {
        try ConnectorValidator.validate(manifestData:Data(contentsOf:root.appendingPathComponent("connectors/anime-sama-expansion.json")))
    }
    private func card(_ id: String, _ badges: [String], genre: String = "") -> String {
        let spans = badges.map { "<span class=\"as-badge \($0)\">Type</span>" }.joined()
        return "<div class=\"as-carte-oeuvre\"><a class=\"as-carte-lien\" href=\"https://anime-sama.to/catalogue/\(id)/\"><h3 class=\"as-carte-titre\">\(id)</h3></a><div class=\"as-carte-badges\">\(spans)<span class=\"genre\">\(genre)</span></div></div>"
    }
    private var html: Data {
        Data(("<html><body>" + card("anime",["as-badge-anime"])
            + card("scan-only",["as-badge-scan"])
            + card("film",["as-badge-film"])
            + card("anime-and-scan",["as-badge-anime","as-badge-scan"])
            + card("anime-with-manhwa-genre",["as-badge-anime"],genre:"Manhwa")
            + card("movie-with-current-anime-badge",["as-badge-anime"])
            + "</body></html>").utf8)
    }
    private let expected = ["anime","film","anime-and-scan","anime-with-manhwa-genre","movie-with-current-anime-badge"]
    func testDiscoveryKeepsVideoAndMixedMediaWithoutGenreGuessing() async throws {
        let transport = StubTransport()
        transport.route("https://anime-sama.to/catalogue/?page=1",.success(status:200,data:html))
        let result = try await ConnectorEngine(manifest:manifest(),transport:transport)
            .loadDiscoverySection(id:"catalogue",page:1)
        XCTAssertEqual(result.items.map(\.sourceID),expected)
    }
    func testSearchUsesTheSamePositiveVideoGuard() async throws {
        let transport = StubTransport()
        transport.route("https://anime-sama.to/catalogue/?search=fixture&page=1",.success(status:200,data:html))
        let result = try await ConnectorEngine(manifest:manifest(),transport:transport).search(query:"fixture")
        XCTAssertEqual(result.map(\.sourceID),expected)
    }
    func testReleasedReaderFeatureAndExistingRouteSafetyAreRetained() throws {
        let value = try manifest()
        XCTAssertEqual(value.id,"anime-sama-expansion");XCTAssertEqual(value.familyID,"anime-sama-expansion")
        XCTAssertEqual(value.version.description,"0.3.3")
        XCTAssertEqual(value.minimumAppVersion.description,"2.1.36")
        XCTAssertTrue(value.requiredEngineFeatures.contains { $0.rawValue=="legacy-script-comments-v1" })
        XCTAssertTrue(value.requiredEngineFeatures.contains(.boundedMirrorsV1))
        XCTAssertEqual(value.operations.streams?.mirrors.count,2)
        XCTAssertTrue(value.operations.streams?.mirrors.allSatisfy { $0.finalMediaURLPolicy == .publicHTTPS } == true)
    }
}
