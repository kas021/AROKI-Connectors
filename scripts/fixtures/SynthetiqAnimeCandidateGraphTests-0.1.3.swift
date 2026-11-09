import XCTest
@testable import VireoCore

/// Deterministic contract tests for the lane candidate, using the released
/// typed graph engine and synthetic AniList/AniKage responses only.
final class SynthetiqAnimeCandidateGraphTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func manifest() throws -> ConnectorManifest {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent("connectors/synthetiq-anime-testing.json"))
        return try ConnectorValidator.validate(manifestData: data)
    }

    private let graphqlURL = "https://graphql.anilist.co"
    private let browseURL = "https://anikage.cc/api/media/anime/browse?q=Fullmetal%20Alchemist%3A%20Brotherhood&format=TV&yearMin=2009&yearMax=2009&page=1"
    private let sourceURL = "https://anikage.cc/api/media/anime/brotherhood/episodes/episode-opaque/sources?provider=koto&lang="

    private func mediaResponse() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["data": ["Media": [
            "id": 5114, "idMal": 20, "title": ["romaji": "Fullmetal Alchemist: Brotherhood"],
            "format": "TV", "seasonYear": 2009,
        ]]])
    }

    private var exactRow: [String: Any] {
        ["slug": "brotherhood", "anilistId": 5114,
         "title": ["english": "Fullmetal Alchemist: Brotherhood",
                   "romaji": "Hagane no Renkinjutsushi: Fullmetal Alchemist"],
         "year": 2009, "format": "TV"]
    }

    private func transport(rows: [[String: Any]]) throws -> StubTransport {
        let result = StubTransport()
        result.route(graphqlURL, .success(status: 200, data: try mediaResponse()))
        result.route(browseURL, .success(status: 200,
                      data: try JSONSerialization.data(withJSONObject: ["data": rows])))
        for variant in ["sub", "dub"] {
            let subtitles: [[String: Any]] = variant == "sub"
                ? [["file": "caption-token-en", "label": "English", "srclang": "en"]]
                : []
            result.route(sourceURL + variant + "&refresh=1",
                          .success(status: 200, data: try JSONSerialization.data(withJSONObject: [
                            "sources": [["url": "episode-token-\(variant)", "quality": "1080p"]],
                            "subtitles": subtitles,
                          ])))
        }
        return result
    }

    func testCandidateFeatureGateAndPreservedIDsAndAudioVariants() throws {
        let parsed = try manifest()
        XCTAssertEqual(parsed.id, "synthetiq-anime-testing")
        XCTAssertEqual(parsed.version, try XCTUnwrap(SemanticVersion("0.1.3")))
        XCTAssertEqual(parsed.minimumAppVersion, try XCTUnwrap(SemanticVersion("2.1.36")))
        XCTAssertTrue(parsed.requiredEngineFeatures.contains { $0.rawValue == "typed-graph-context-v1" })
        XCTAssertEqual(parsed.operations.streams?.variants, [.sub, .dub])
        XCTAssertEqual(parsed.operations.episodes?.numberedRange?.identity.raw, "data.Media.idMal")
    }

    func testUniqueCanonicalRowResolvesRequestedVariantCaptionAndProxyPolicy() async throws {
        let decoy: [String: Any] = ["slug": "remake", "anilistId": 121,
            "title": ["english": "Fullmetal Alchemist"], "year": 2003, "format": "TV"]
        let transport = try transport(rows: [decoy, exactRow])
        let engine = ConnectorEngine(manifest: try manifest(), transport: transport, retryDelays: [0])

        let sub = try await engine.streams(titleID: "20", episodeID: "episode-opaque", variant: .sub)
        XCTAssertEqual(sub.count, 1)
        XCTAssertEqual(sub[0].url.absoluteString, "https://og.bakayaro.live/episode-token-sub")
        XCTAssertEqual(sub[0].mediaType, .hls)
        XCTAssertEqual(sub[0].headers["referer"] ?? sub[0].headers["Referer"], "https://anikage.cc/")
        XCTAssertEqual(sub[0].subtitles.count, 1)
        XCTAssertEqual(sub[0].subtitles[0].url.absoluteString, "https://og.bakayaro.live/caption-token-en")
        XCTAssertEqual(sub[0].subtitles[0].languageCode, "en")
        XCTAssertTrue(transport.requestedURLs.contains(sourceURL + "sub&refresh=1"))
        XCTAssertFalse(transport.requestedURLs.contains(sourceURL + "dub&refresh=1"))

        let dubTransport = try self.transport(rows: [exactRow])
        let dubEngine = ConnectorEngine(manifest: try manifest(), transport: dubTransport, retryDelays: [0])
        let dub = try await dubEngine.streams(titleID: "20", episodeID: "episode-opaque", variant: .dub)
        XCTAssertEqual(dub.first?.url.absoluteString, "https://og.bakayaro.live/episode-token-dub")
        XCTAssertFalse(dubTransport.requestedURLs.contains(sourceURL + "sub&refresh=1"))
    }

    func testWrongIDWrongYearWrongFormatAndAmbiguousIDFailBeforeSourceRequest() async throws {
        var wrongID = exactRow; wrongID["anilistId"] = 121
        var wrongYear = exactRow; wrongYear["year"] = 2010
        var wrongFormat = exactRow; wrongFormat["format"] = "MOVIE"
        let duplicate = exactRow

        for rows in [[wrongID], [wrongYear], [wrongFormat], [exactRow, duplicate]] {
            let transport = try transport(rows: rows)
            let engine = ConnectorEngine(manifest: try manifest(), transport: transport, retryDelays: [0])
            do {
                _ = try await engine.streams(titleID: "20", episodeID: "episode-opaque")
                XCTFail("identity conflict or duplicate must not select a row")
            } catch { }
            XCTAssertFalse(transport.requestedURLs.contains { $0.contains("/sources?") })
        }
    }

    func testStringAnilistIdFailsClosedWithReleasedIntegerComparator() async throws {
        var stringID = exactRow; stringID["anilistId"] = "5114"
        let transport = try transport(rows: [stringID])
        let engine = ConnectorEngine(manifest: try manifest(), transport: transport, retryDelays: [0])
        do {
            _ = try await engine.streams(titleID: "20", episodeID: "episode-opaque")
            XCTFail("string ID must not be coerced by integer comparison")
        } catch { }
        XCTAssertFalse(transport.requestedURLs.contains { $0.contains("/sources?") })
    }
}
