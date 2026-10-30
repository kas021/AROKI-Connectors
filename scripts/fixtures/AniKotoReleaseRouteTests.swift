import XCTest
@testable import VireoCore

final class AniKotoConnectorTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadManifest() throws -> ConnectorManifest {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent("connectors/anikoto.json"))
        return try ConnectorValidator.validate(manifestData: data)
    }

    func testAniKotoConnectorValidates() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest.id, "anikoto")
        XCTAssertEqual(manifest.version, try XCTUnwrap(SemanticVersion("0.3.11")))
        XCTAssertEqual(manifest.releaseTrack, .beta)
        XCTAssertEqual(manifest.status, .active)
        XCTAssertEqual(manifest.operations.streams?.variants, [.sub, .dub])
        XCTAssertEqual(manifest.operations.streams?.finalMediaURLPolicy, .publicHTTPS)
        XCTAssertTrue(manifest.allowedHosts.contains { $0.matches(host: "anikage.cc") })
        XCTAssertTrue(manifest.allowedHosts.contains { $0.matches(host: "og.bakayaro.live") })
    }

    func testAniKotoSearchMapsResultsWithoutMetadata() async throws {
        let manifest = try loadManifest()
        let transport = StubTransport()
        transport.route("https://anikototv.to/filter?keyword=naruto&page=1",
                         .success(status: 200, data: Data("""
        <html><body><div id="list-items"><div class="item"><div class="poster"><img src="https://cdn.anipixcdn.co/thumbnail/abc.jpg" /></div><a class="name d-title" href="https://anikototv.to/watch/naruto-123/ep-1">Naruto</a></div></div></body></html>
        """.utf8)))

        let engine = ConnectorEngine(manifest: manifest, transport: transport, retryDelays: [0])
        let results = try await engine.search(query: "naruto", page: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].sourceID, "naruto-123")
        XCTAssertEqual(results[0].title, "Naruto")
        XCTAssertEqual(results[0].posterURL?.absoluteString, "https://cdn.anipixcdn.co/thumbnail/abc.jpg")
        XCTAssertTrue(results[0].metadata.genres.isEmpty,
                      "standalone listing cards carry no genre info")
        XCTAssertNil(results[0].metadata.status,
                     "no ongoing/completed badge on listing cards")
        XCTAssertNil(results[0].metadata.year,
                     "no year on listing cards")
    }


    private let watchHTML = """
    <html><body><div id="watch-main" data-id="shared-456"><h1 class="title d-title" data-jp="Naruto">Naruto</h1>
    <div id="w-info"><div class="bmeta"><div class="meta"><div>Type: <span>TV</span></div><div>Premiered: <a href="/filter?season=Fall&year=2002">Fall 2002</a></div><div>Aired: <span>Oct 3, 2002 to Mar 27, 2007</span></div></div></div></div></div></body></html>
    """
    private let browseURL = "https://anikage.cc/api/media/anime/browse?q=Naruto&format=TV&yearMin=2002&yearMax=2002&page=1"
    private func sourcesURL(_ v: String) -> String {
        "https://anikage.cc/api/media/anime/naruto-20/episodes/1/sources?provider=koto&lang=\(v)&refresh=1"
    }

    /// Routes the AniKage-backed graph: watch page -> server list (episode
    /// number) -> AniKage browse (identity-filtered) -> koto sources.
    private func streamTransport(dubAvailable: Bool = true) -> StubTransport {
        let t = StubTransport()
        t.route("https://anikototv.to/watch/naruto-123", .success(status: 200, data: Data(watchHTML.utf8)))
        t.route("https://anikototv.to/ajax/server/list?servers=enc-payload-1", .success(status: 200, data: Data("""
        { "result": "<div class=\\"servers\\"><div class=\\"tip\\">You are watching <b>Episode 1</b></div></div>" }
        """.utf8)))
        t.route(browseURL, .success(status: 200, data: Data(#"{"data":[{"slug":"naruto-20"}]}"#.utf8)))
        t.route(sourcesURL("sub"), .success(status: 200, data: Data(#"{"sources":[{"url":"hls/sub/master.m3u8","quality":"1080p"}],"subtitles":[{"file":"subs/en.vtt","label":"English","srclang":"en"}]}"#.utf8)))
        t.route(sourcesURL("dub"), dubAvailable
            ? .success(status: 200, data: Data(#"{"sources":[{"url":"hls/dub/master.m3u8","quality":"1080p"}],"subtitles":[]}"#.utf8))
            : .success(status: 200, data: Data(#"{"sources":[],"subtitles":[]}"#.utf8)))
        return t
    }

    func testAniKotoCaptionCDNLoadsThroughConnectorPolicy() async throws {
        let manifest = try loadManifest()
        let transport = StubTransport()
        let url = "https://og.bakayaro.live/subs/en.vtt"
        transport.route(url, .success(status: 200, data: Data("WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nCaption restored\n".utf8)))
        let engine = ConnectorEngine(manifest: manifest, transport: transport, retryDelays: [0])
        let track = SubtitleTrack(url: try XCTUnwrap(URL(string: url)), languageCode: "en", label: "English", format: .vtt)
        let cues = try await engine.loadSubtitleTrack(track)
        XCTAssertEqual(cues.map(\.text), ["Caption restored"])
    }

    func testAniKotoCatalogueFlow() async throws {
        // Find the project root relative to this file
        let fileURL = URL(fileURLWithPath: #file)
        let projectRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        
        let connectorURL = projectRoot.appendingPathComponent("connectors/anikoto.json")
        let manifestData = try Data(contentsOf: connectorURL)
        let manifest = try ConnectorValidator.validate(manifestData: manifestData)
        
        let transport = StubTransport()
        
        // Mock Discovery (all eight bounded M19 shelves at their start page).
        transport.route("https://anikototv.to/filter?sort=most_watched&page=1", .success(status: 200, data: Data("""
        <html><body><div id="list-items"><div class="item"><div class="poster"><img src="https://cdn.anipixcdn.co/thumbnail/abc.jpg" /></div><a class="name d-title" href="https://anikototv.to/watch/naruto-123/ep-1">Naruto</a></div></div></body></html>
        """.utf8)))
        
        let emptyCatalogue = Data("<html><body><div id=\"list-items\"></div></body></html>".utf8)
        transport.route("https://anikototv.to/filter?sort=score&page=1", .success(status: 200, data: emptyCatalogue))
        transport.route("https://anikototv.to/genre/action?page=1", .success(status: 200, data: emptyCatalogue))
        transport.route("https://anikototv.to/genre/adventure?page=1", .success(status: 200, data: emptyCatalogue))
        transport.route("https://anikototv.to/genre/comedy?page=1", .success(status: 200, data: emptyCatalogue))
        transport.route("https://anikototv.to/genre/fantasy?page=1", .success(status: 200, data: emptyCatalogue))
        transport.route("https://anikototv.to/genre/romance?page=1", .success(status: 200, data: emptyCatalogue))
        transport.route("https://anikototv.to/genre/sci-fi?page=1", .success(status: 200, data: emptyCatalogue))
        
        // Mock Details
        transport.route("https://anikototv.to/watch/naruto-123", .success(status: 200, data: Data("""
        <html><body>
            <div id="watch-main" data-id="shared-456">
                <h1 class="d-title">Naruto</h1>
                <div class="synopsis"><div class="shorting">Ninja story</div></div>
                <div class="poster"><img src="https://cdn.anipixcdn.co/thumbnail/abc.jpg" /></div>
                <div class="bmeta"><div class="meta"><a href="/genre/action">Action</a></div></div>
            </div>
        </body></html>
        """.utf8)))
        
        // Mock Episodes (JSON wrapped HTML) — episodeID is the encrypted
        // data-ids servers payload, per the proven M14 flow.
        transport.route("https://anikototv.to/ajax/episode/list/shared-456", .success(status: 200, data: Data("""
        {
            "result": "<div class=\\"episodes\\"><ul class=\\"ep-range\\"><li><a data-id=\\"110289\\" data-ids=\\"enc-payload-1\\" data-num=\\"1\\"><span class=\\"d-title\\">Ep 1</span></a></li></ul></div>"
        }
        """.utf8)))

        // Mock Streams step 1: server list (JSON-wrapped HTML). VidPlay-1
        // (data-sv-id 8e4) is selected; VidCloud-1 (a41) is never chosen.
        transport.route("https://anikototv.to/ajax/server/list?servers=enc-payload-1", .success(status: 200, data: Data("""
        {
            "result": "<div class=\\"servers\\"><div class=\\"type\\" data-type=\\"sub\\"><ul><li data-sv-id=\\"8e4\\" data-link-id=\\"link-vidplay\\">VidPlay-1</li><li data-sv-id=\\"323\\" data-link-id=\\"link-hd\\">HD-1</li><li data-sv-id=\\"a41\\" data-link-id=\\"link-vidcloud\\">VidCloud-1</li></ul></div><div class=\\"type\\" data-type=\\"dub\\"><ul><li data-sv-id=\\"8e4\\" data-link-id=\\"link-vidplay-dub\\">VidPlay-1</li><li data-sv-id=\\"323\\" data-link-id=\\"link-hd-dub\\">HD-1</li><li data-sv-id=\\"a41\\" data-link-id=\\"link-vidcloud-dub\\">VidCloud-1</li></ul></div></div>"
        }
        """.utf8)))

        // Mock Streams step 2: server -> embed/player URL (validated continuation URL).
        transport.route("https://anikototv.to/ajax/server?get=link-vidplay", .success(status: 200, data: Data("""
        { "result": { "url": "https://vidtube.site/stream/abc123" } }
        """.utf8)))

        // Mock Streams step 3: follow the validated player URL -> player ID.
        transport.route("https://vidtube.site/stream/abc123", .success(status: 200, data: Data("""
        <html><body><div id="player" data-id="98765"></div></body></html>
        """.utf8)))

        // Mock Streams step 4: derived origin + fixed getSources path -> direct HLS.
        // Real shape observed live: `sources` is a single object, `tracks` holds subtitles.
        transport.route("https://vidtube.site/stream/getSources?id=98765&type=sub", .success(status: 200, data: Data("""
        {
          "sources": { "file": "https://vidtub.norami.top/hls/abc123/master.m3u8" },
          "tracks": [
            { "file": "https://vidtub.norami.top/subs/abc123/English.vtt", "label": "English", "kind": "captions" },
            { "url": "https://vidtub.norami.top/subs/abc123/Spanish.vtt", "name": "Spanish", "srclang": "es", "kind": "captions" }
          ]
        }
        """.utf8)))
        
        let engine = ConnectorEngine(manifest: manifest, transport: transport, retryDelays: [0])
        
        // Test Discovery
        let sections = try await engine.loadDiscovery()
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Most Watched")
        XCTAssertEqual(sections[0].items.count, 1)
        XCTAssertEqual(sections[0].items[0].title, "Naruto")
        XCTAssertEqual(sections[0].items[0].sourceID, "naruto-123")
        XCTAssertEqual(sections[0].items[0].posterURL?.absoluteString, "https://cdn.anipixcdn.co/thumbnail/abc.jpg")
        XCTAssertTrue(sections[0].items[0].metadata.genres.isEmpty,
                      "listing cards carry no genre field — genres live on details page only")
        XCTAssertNil(sections[0].items[0].metadata.status,
                     "no status badge on listing cards")
        
        // Test Details
        let details = try await engine.details(titleID: "naruto-123")
        XCTAssertEqual(details.title, "Naruto")
        XCTAssertEqual(details.synopsis, "Ninja story")
        XCTAssertEqual(details.sharedID, "shared-456")
        XCTAssertEqual(details.genres, ["Action"])
        
        // Test Episodes
        let seasons = try await engine.seasons(titleID: "naruto-123", sharedID: "shared-456")
        XCTAssertEqual(seasons.count, 1)
        XCTAssertEqual(seasons[0].episodes.count, 1)
        XCTAssertEqual(seasons[0].episodes[0].id, "enc-payload-1")
        XCTAssertEqual(seasons[0].episodes[0].title, "Ep 1")
        XCTAssertEqual(seasons[0].episodes[0].episodeNumber, 1)
        

        // Test Streams: the AniKage-backed 4-step graph resolves a direct HLS candidate.
        let st = streamTransport()
        let streamEngine = ConnectorEngine(manifest: manifest, transport: st, retryDelays: [0])
        let candidates = try await streamEngine.streams(titleID: "naruto-123", episodeID: "enc-payload-1")
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].url.absoluteString, "https://og.bakayaro.live/hls/sub/master.m3u8")
        XCTAssertEqual(candidates[0].mediaType, .hls)
        XCTAssertEqual(candidates[0].headers["referer"] ?? candidates[0].headers["Referer"], "https://anikage.cc/")
        XCTAssertEqual(candidates[0].subtitles.count, 1)
        XCTAssertEqual(candidates[0].subtitles[0].url.absoluteString, "https://og.bakayaro.live/subs/en.vtt")
        XCTAssertEqual(candidates[0].subtitles[0].languageCode, "en")
        XCTAssertEqual(st.requestedURLs, [
            "https://anikototv.to/watch/naruto-123",
            "https://anikototv.to/ajax/server/list?servers=enc-payload-1",
            browseURL,
            sourcesURL("sub"),
        ], "strictly linear chain: watch -> server list -> identity browse -> sources")
    }

    func testAniKotoStreamsFailClosedWhenIdentityBrowseHasNoMatch() async throws {
        let t = streamTransport()
        t.route(browseURL, .success(status: 200, data: Data(#"{"data":[]}"#.utf8)))
        let engine = ConnectorEngine(manifest: try loadManifest(), transport: t, retryDelays: [0])
        do {
            _ = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1")
            XCTFail("expected failure when no identity match exists")
        } catch {}
        XCTAssertFalse(t.requestedURLs.contains { $0.contains("/sources?") }, "no sources request without an identity match")
    }

    func testAniKotoStreamsDubResolvesDistinctCandidate() async throws {
        let t = streamTransport()
        let engine = ConnectorEngine(manifest: try loadManifest(), transport: t, retryDelays: [0])
        let candidates = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1", variant: .dub)
        XCTAssertEqual(candidates.first?.url.absoluteString, "https://og.bakayaro.live/hls/dub/master.m3u8")
        XCTAssertFalse(t.requestedURLs.contains(sourcesURL("sub")), "no Sub request for Dub")
    }

    func testAniKotoStreamsDubUnavailableFailsWithoutFallback() async throws {
        let t = streamTransport(dubAvailable: false)
        let engine = ConnectorEngine(manifest: try loadManifest(), transport: t, retryDelays: [0])
        do {
            _ = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1", variant: .dub)
            XCTFail("expected failure when dub has no sources")
        } catch {}
        XCTAssertFalse(t.requestedURLs.contains(sourcesURL("sub")), "no silent sub fallback")
    }
}
