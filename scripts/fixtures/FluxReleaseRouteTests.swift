import Foundation
import XCTest
import VireoCore

final class FluxReleaseRouteTests: XCTestCase {
    private func manifest() throws -> ConnectorManifest {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return try ConnectorValidator.validate(manifestData: Data(contentsOf: root.appendingPathComponent("connectors/synthetiq-anime-direct.json")))
    }
    private func transport(identity: String = #"{"data":{"Media":{"id":207329}}}"#,
                           selection: String = #"{"settlarSelection":"fixture-selection"}"#) -> FluxReleaseFixtureTransport {
        FluxReleaseFixtureTransport([identity, selection,
            #"{"embedUrl":"https://embed.settlar.io/?t=fixture-token"}"#,
            #"{"source":"https://media.settlar.io/fixture.m3u8","kind":"hls","expiresAt":2208988800,"subtitles":[{"url":"https://media.settlar.io/fr.vtt","label":"French","srclang":"fr"}]}"#])
    }
    func testPreservesExistingModuleAndCatalogueIdentities() throws {
        let m = try manifest()
        XCTAssertEqual(m.id, "synthetiq-anime-direct")
        XCTAssertEqual(m.familyID, "synthetiq-anime-direct")
        XCTAssertEqual(m.minimumAppVersion.description, "2.0.38")
    }
    func testCanonicalAniListRouteKeepsRequestedEpisodeAndSub() async throws {
        let t = transport()
        let e = ConnectorEngine(manifest: try manifest(), transport: t)
        let streams = try await e.streams(titleID: "63431", episodeID: "6", variant: .sub)
        let requests = await t.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[1].path, "/api/anime/playback-bootstrap/anilist/207329")
        let query = URLComponents(url: requests[1], resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "ep" }?.value, "6")
        XCTAssertEqual(query.first { $0.name == "lang" }?.value, "sub")
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(streams[0].subtitles.count, 1)
        XCTAssertEqual(streams[0].expiresAt, Date(timeIntervalSince1970: 2208988800))
    }
    func testDubIsNotSilentlyRewrittenToSub() async throws {
        let t = transport()
        let e = ConnectorEngine(manifest: try manifest(), transport: t)
        _ = try await e.streams(titleID: "63431", episodeID: "1", variant: .dub)
        let requests = await t.requests
        for index in [1, 2] {
            let query = URLComponents(url: requests[index], resolvingAgainstBaseURL: false)!.queryItems!
            let name = index == 1 ? "lang" : "channel"
            XCTAssertEqual(query.first { $0.name == name }?.value, "dub")
        }
    }
    func testMissingCanonicalIdentityStopsBeforeProviderRequest() async throws {
        let t = transport(identity: #"{"data":{"Media":null}}"#)
        let e = ConnectorEngine(manifest: try manifest(), transport: t)
        do { _ = try await e.streams(titleID: "63431", episodeID: "1", variant: .sub); XCTFail("Missing identity accepted") }
        catch { XCTAssertTrue(error is EngineError) }
        let count = await t.count()
        XCTAssertEqual(count, 1)
    }
    func testUnavailableAudioStopsWithoutTryingAnotherAudio() async throws {
        let t = transport(selection: #"{"available":false}"#)
        let e = ConnectorEngine(manifest: try manifest(), transport: t)
        do { _ = try await e.streams(titleID: "63431", episodeID: "1", variant: .dub); XCTFail("Unavailable audio accepted") }
        catch { XCTAssertTrue(error is EngineError) }
        let count = await t.count()
        XCTAssertEqual(count, 2)
    }
    func testProviderBootstrapFallbackDoesNotOverrideRequestedChannel() async throws {
        // Live 4 CUT HERO reports effectiveLanguage=sub for a Dub request,
        // but Settlar's explicitly requested Dub channel correctly returns 424.
        let t = FluxReleaseFixtureTransport([
            #"{"data":{"Media":{"id":156096}}}"#,
            #"{"effectiveLanguage":"sub","settlarSelection":"fixture-selection"}"#,
            #"{"embedUrl":"https://embed.settlar.io/?t=fixture-token"}"#,
            #"{"error":"audio unavailable"}"#
        ], statuses: [200, 200, 200, 424])
        let e = ConnectorEngine(manifest: try manifest(), transport: t)
        do { _ = try await e.streams(titleID: "55578", episodeID: "1", variant: .dub); XCTFail("Wrong-language stream accepted") }
        catch { XCTAssertEqual(error as? EngineError, .badStatus(424)) }
        let count = await t.count()
        XCTAssertEqual(count, 4)
        let requests = await t.requests
        let query = URLComponents(url: requests[2], resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "channel" }?.value, "dub")
    }
}

actor FluxReleaseFixtureTransport: HTTPTransport {
    var data: [Data]
    var requests: [URL] = []
    var statuses: [Int]
    init(_ payloads: [String], statuses: [Int] = []) {
        data = payloads.map { Data($0.utf8) }
        self.statuses = statuses
    }
    func execute(_ request: URLRequest, redirectPolicy: RedirectPolicy, maxResponseBytes: Int) async throws -> TransportResponse {
        let url = request.url!
        requests.append(url)
        guard !data.isEmpty else { throw EngineError.parse("unexpected extra request") }
        let bytes = data.removeFirst()
        let status = statuses.isEmpty ? 200 : statuses.removeFirst()
        return TransportResponse(data: bytes, statusCode: status, finalURL: url, headers: [:])
    }
    func yearQueries() -> [String: String] {
        guard let url = requests.first(where: { $0.path.hasSuffix("/browse") }),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
    }
    func count() -> Int { requests.count }
}
