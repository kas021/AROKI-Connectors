import Foundation
import XCTest
import VireoCore

final class FluxReleaseRoute015Tests: XCTestCase {
    private func skipUnlessFluxSelected() throws {
        guard let selected = ProcessInfo.processInfo.environment["AROKI_AUDIO_GUARD_MODULE"], !selected.isEmpty else { return }
        guard selected == "anipm" || selected == "synthetiq-anime-direct" else {
            throw NSError(domain: "FluxReleaseRoute015Tests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "unknown AROKI_AUDIO_GUARD_MODULE value"])
        }
        if selected == "anipm" { throw XCTSkip("Flux route fixtures are not selected for this publication run") }
    }

    private func manifest() throws -> ConnectorManifest {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let laneCandidate = root.appendingPathComponent("lanes/provider/audio-guards/candidates/synthetiq-anime-direct-0.1.5.json")
            let ciCandidate = root.appendingPathComponent("connectors/synthetiq-anime-direct.json")
            if FileManager.default.fileExists(atPath: laneCandidate.path) {
                return try ConnectorValidator.validate(manifestData: Data(contentsOf: laneCandidate))
            }
            if FileManager.default.fileExists(atPath: ciCandidate.path) {
                return try ConnectorValidator.validate(manifestData: Data(contentsOf: ciCandidate))
            }
            root = root.deletingLastPathComponent()
        }
        throw NSError(domain: "FluxReleaseRoute015Tests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "candidate manifest not found"])
    }
    private func transport(identity: String = #"{"data":{"Media":{"id":207329}}}"#,
                           selection: String = #"{"settlarSelection":"fixture-selection","availability":{"sub":true,"dub":true},"effectiveLanguage":"sub"}"#) -> FluxReleaseFixtureTransport015 {
        FluxReleaseFixtureTransport015([identity, selection,
            #"{"embedUrl":"https://embed.settlar.io/?t=fixture-token"}"#,
            #"{"source":"https://media.settlar.io/fixture.m3u8","kind":"hls","expiresAt":2208988800,"subtitles":[{"url":"https://media.settlar.io/fr.vtt","label":"French","srclang":"fr"}]}"#])
    }
    func testPreservesExistingModuleAndCatalogueIdentities() throws {
        try skipUnlessFluxSelected()
        let m = try manifest()
        XCTAssertEqual(m.id, "synthetiq-anime-direct")
        XCTAssertEqual(m.familyID, "synthetiq-anime-direct")
        XCTAssertEqual(m.version, try XCTUnwrap(SemanticVersion("0.1.5")))
        XCTAssertEqual(m.minimumAppVersion.description, "2.1.36")
    }
    func testCanonicalAniListRouteKeepsRequestedEpisodeAndSub() async throws {
        try skipUnlessFluxSelected()
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
        try skipUnlessFluxSelected()
        let t = transport(selection: #"{"settlarSelection":"fixture-selection","availability":{"sub":true,"dub":true},"effectiveLanguage":"dub"}"#)
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
        try skipUnlessFluxSelected()
        let t = transport(identity: #"{"data":{"Media":null}}"#)
        let e = ConnectorEngine(manifest: try manifest(), transport: t)
        do { _ = try await e.streams(titleID: "63431", episodeID: "1", variant: .sub); XCTFail("Missing identity accepted") }
        catch { XCTAssertTrue(error is EngineError) }
        let count = await t.count()
        XCTAssertEqual(count, 1)
    }
    func testUnavailableAudioStopsWithoutTryingAnotherAudio() async throws {
        try skipUnlessFluxSelected()
        let t = transport(selection: #"{"availability":{"sub":true,"dub":false},"effectiveLanguage":"dub","settlarSelection":"fixture-selection"}"#)
        let e = ConnectorEngine(manifest: try manifest(), transport: t)
        do { _ = try await e.streams(titleID: "63431", episodeID: "1", variant: .dub); XCTFail("Unavailable audio accepted") }
        catch { XCTAssertTrue(error is EngineError) }
        let count = await t.count()
        XCTAssertEqual(count, 2)
    }
    func testProviderBootstrapAudioMismatchStopsBeforeSession() async throws {
        try skipUnlessFluxSelected()
        // A bootstrap that advertises Sub for an explicit Dub request is
        // rejected before session creation; the graph must not downgrade.
        let t = FluxReleaseFixtureTransport015([
            #"{"data":{"Media":{"id":156096}}}"#,
            #"{"availability":{"sub":true,"dub":true},"effectiveLanguage":"sub","settlarSelection":"fixture-selection"}"#
        ])
        let e = ConnectorEngine(manifest: try manifest(), transport: t)
        do { _ = try await e.streams(titleID: "55578", episodeID: "1", variant: .dub); XCTFail("Wrong-language stream accepted") }
        catch { XCTAssertTrue(error is EngineError) }
        let count = await t.count()
        XCTAssertEqual(count, 2)
        let requests = await t.requests
        let query = URLComponents(url: requests[1], resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "lang" }?.value, "dub")
        XCTAssertFalse(requests.contains { $0.path == "/api/anime/settlar/session" })
    }
}

actor FluxReleaseFixtureTransport015: HTTPTransport {
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
