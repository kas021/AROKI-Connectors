import XCTest
@testable import VireoCore

/// Candidate-specific, deterministic stream-graph tests. This file is kept in
/// the Koto lane so it cannot silently replace the shared engine test file.
final class RolloutAniKotoCandidateTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func manifest() throws -> ConnectorManifest {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent("connectors/anikoto.json"))
        return try ConnectorValidator.validate(manifestData: data)
    }

    private func r2Manifest() throws -> ConnectorManifest {
        try manifest()
    }

    private func r3Manifest() throws -> ConnectorManifest {
        try manifest()
    }

    private let watchURL = "https://anikototv.to/watch/naruto-123"
    private let browseURL = "https://anikage.cc/api/media/anime/browse?q=Naruto&format=TV&yearMin=2002&yearMax=2002&page=1"
    private let sourcePrefix = "https://anikage.cc/api/media/anime/naruto-20/episodes/1/sources?provider=koto&lang="

    private func watchHTML(linked: Bool = true, aired: String = "Oct 3, 2002 to Mar 27, 2007",
                           yearLink: Bool = false, visibleTitle: String = "Naruto",
                           dataJPTitle: String = "Naruto", catalogueID: Int = 20) -> String {
        let style = linked
            ? " style=\"background-image:url(https://s4.anilist.co/file/anilistcdn/media/anime/banner/\(catalogueID)-naruto.jpg)\""
            : ""
        let premiered = yearLink ? "<div>Premiered: <a href=\"/filter?season=Fall&year=2002\">Fall 2002</a></div>" : ""
        return """
        <html><body>
          <div id="watch-main" data-id="shared-456">
            <h1 class="title d-title" data-jp="\(dataJPTitle)">\(visibleTitle)</h1>
            <div id="w-info"><div class="bmeta"><div class="meta">
              <div>Type: <span>TV</span></div>\(premiered)<div>Aired: <span>\(aired)</span></div>
            </div></div></div>
            <div id="player"\(style)></div>
          </div>
        </body></html>
        """
    }

    private func streamTransport(rows: [[String: Any]], linked: Bool = true,
                                 dubAvailable: Bool = true,
                                 aired: String = "Oct 3, 2002 to Mar 27, 2007",
                                 yearLink: Bool = false,
                                 videoURL: String = "fixture-sub-token",
                                 captionURL: String = "fixture-en-caption-token",
                                 visibleTitle: String = "Naruto", dataJPTitle: String = "Naruto",
                                 year: Int = 2002, format: String = "TV", catalogueID: Int = 20) throws -> StubTransport {
        let transport = StubTransport()
        transport.route(watchURL, .success(status: 200, data: Data(watchHTML(linked: linked, aired: aired, yearLink: yearLink,
                            visibleTitle: visibleTitle, dataJPTitle: dataJPTitle, catalogueID: catalogueID).utf8)))
        transport.route("https://anikototv.to/ajax/server/list?servers=enc-payload-1",
                        .success(status: 200, data: Data(#"{"result":"<div class=\"servers\"><div class=\"tip\">You are watching <b>Episode 1</b></div></div>"}"#.utf8)))
        transport.route(browseURLFor(title: visibleTitle.isEmpty ? dataJPTitle : visibleTitle, year: year, format: format), .success(status: 200,
                        data: try JSONSerialization.data(withJSONObject: ["data": rows])))
        for row in rows {
            guard let slug = row["slug"] as? String else { continue }
            for variant in ["sub", "dub"] {
                let source = variant == "sub" ? videoURL : "fixture-dub-token"
                let sources = variant == "dub" && !dubAvailable ? [] : [["url": source, "quality": "1080p"]]
                let captions: [[String: Any]] = variant == "sub"
                    ? [["file": captionURL, "label": "English", "srclang": "en"]]
                    : []
                transport.route(sourcePrefix(for: slug) + variant + "&refresh=1",
                                .success(status: 200, data: try JSONSerialization.data(withJSONObject: [
                                    "sources": sources, "subtitles": captions
                                ])))
            }
        }
        return transport
    }

    private func browseURLFor(title: String = "Naruto", year: Int, format: String = "TV") -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        return "https://anikage.cc/api/media/anime/browse?q=\(encodedTitle)&format=\(format)&yearMin=\(year)&yearMax=\(year)&page=1"
    }

    private func sourcePrefix(for slug: String) -> String {
        "https://anikage.cc/api/media/anime/\(slug)/episodes/1/sources?provider=koto&lang="
    }

    private var exactRow: [String: Any] {
        ["slug": "naruto-20", "anilistId": 20,
         "title": ["english": "Naruto", "romaji": "Naruto"],
         "year": 2002, "format": "TV"]
    }

    func testCandidateVersionFeatureGateAndExistingRoutes() throws {
        let parsed = try manifest()
        XCTAssertEqual(parsed.id, "anikoto")
        XCTAssertEqual(parsed.version, try XCTUnwrap(SemanticVersion("0.3.12")))
        XCTAssertEqual(parsed.minimumAppVersion, try XCTUnwrap(SemanticVersion("2.1.36")))
        XCTAssertTrue(parsed.requiredEngineFeatures.contains { $0.rawValue == "typed-graph-context-v1" })
        XCTAssertEqual(parsed.operations.streams?.variants, [.sub, .dub])
        XCTAssertEqual(parsed.operations.streams?.finalMediaURLPolicy, .publicHTTPS)
        XCTAssertTrue(parsed.allowedHosts.contains { $0.matches(host: "anikage.cc") })
        XCTAssertTrue(parsed.allowedHosts.contains { $0.matches(host: "og.bakayaro.live") })
    }

    func testUniqueAniListMatchKeepsEpisodeAudioCaptionAndPlaybackPolicy() async throws {
        let decoy: [String: Any] = ["slug": "naruto-remake", "anilistId": 999,
            "title": ["english": "Naruto"], "year": 2002, "format": "TV"]
        let transport = try streamTransport(rows: [decoy, exactRow])
        let engine = ConnectorEngine(manifest: try manifest(), transport: transport, retryDelays: [0])

        let sub = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1", variant: .sub)
        XCTAssertEqual(sub.count, 1)
        XCTAssertEqual(sub[0].url.absoluteString, "https://og.bakayaro.live/fixture-sub-token")
        XCTAssertEqual(sub[0].mediaType, .hls)
        XCTAssertEqual(sub[0].subtitles.count, 1)
        XCTAssertEqual(sub[0].subtitles[0].url.absoluteString, "https://og.bakayaro.live/fixture-en-caption-token")
        XCTAssertEqual(sub[0].subtitles[0].languageCode, "en")
        XCTAssertEqual(sub[0].headers["referer"] ?? sub[0].headers["Referer"], "https://anikage.cc/")
        XCTAssertEqual(Array(transport.requestedURLs.prefix(3)), [
            watchURL,
            "https://anikototv.to/ajax/server/list?servers=enc-payload-1",
            browseURL,
        ])
        XCTAssertTrue(transport.requestedURLs.contains(sourcePrefix + "sub&refresh=1"))
        XCTAssertFalse(transport.requestedURLs.contains(sourcePrefix + "dub&refresh=1"))

        let dubTransport = try streamTransport(rows: [exactRow])
        let dubEngine = ConnectorEngine(manifest: try manifest(), transport: dubTransport, retryDelays: [0])
        let dub = try await dubEngine.streams(titleID: "naruto-123", episodeID: "enc-payload-1", variant: .dub)
        XCTAssertEqual(dub.first?.url.absoluteString, "https://og.bakayaro.live/fixture-dub-token")
        XCTAssertFalse(dubTransport.requestedURLs.contains(sourcePrefix + "sub&refresh=1"))

        let noDubTransport = try streamTransport(rows: [exactRow], dubAvailable: false)
        let noDubEngine = ConnectorEngine(manifest: try manifest(), transport: noDubTransport, retryDelays: [0])
        do {
            _ = try await noDubEngine.streams(titleID: "naruto-123", episodeID: "enc-payload-1", variant: .dub)
            XCTFail("empty Dub response must not substitute Sub")
        } catch { }
        XCTAssertFalse(noDubTransport.requestedURLs.contains(sourcePrefix + "sub&refresh=1"))
    }

    func testMissingBannerIDUsesUniqueTitleYearFormatFallback() async throws {
        let transport = try streamTransport(rows: [exactRow], linked: false)
        let engine = ConnectorEngine(manifest: try manifest(), transport: transport, retryDelays: [0])
        let candidates = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1")
        XCTAssertEqual(candidates.first?.url.absoluteString, "https://og.bakayaro.live/fixture-sub-token")
    }

    func testAmbiguousWrongYearWrongFormatAndConflictingIDStopBeforeSources() async throws {
        let duplicate = exactRow
        var wrongYear = exactRow; wrongYear["year"] = 2003
        var wrongFormat = exactRow; wrongFormat["format"] = "MOVIE"
        var conflictingID = exactRow; conflictingID["anilistId"] = 999

        for rows in [[exactRow, duplicate], [wrongYear], [wrongFormat], [conflictingID]] {
            let transport = try streamTransport(rows: rows)
            let engine = ConnectorEngine(manifest: try manifest(), transport: transport, retryDelays: [0])
            do {
                _ = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1")
                XCTFail("unverified or ambiguous catalogue identity must fail closed")
            } catch { }
            XCTAssertFalse(transport.requestedURLs.contains { $0.contains("/sources?") })
        }
    }

    func testR2ExtractsStartYearFromDateBareYearAndPremiereLink() async throws {
        let cases: [(String, Bool)] = [
            ("Oct 3, 2002 to Mar 27, 2007", false),
            ("2002", false),
            ("not available", true),
        ]
        for (aired, yearLink) in cases {
            let transport = try streamTransport(rows: [exactRow], aired: aired, yearLink: yearLink)
            let engine = ConnectorEngine(manifest: try r2Manifest(), transport: transport, retryDelays: [0])
            let streams = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1")
            XCTAssertEqual(streams.first?.url.absoluteString, "https://og.bakayaro.live/fixture-sub-token")
            XCTAssertTrue(transport.requestedURLs.contains(browseURLFor(year: 2002)))
        }
    }

    func testR2PreservesOpaqueAndAbsoluteProxyURLsForVideoAndCaptions() async throws {
        let absoluteVideo = "https://og.bakayaro.live/media/fixture/master.m3u8"
        let absoluteCaption = "https://og.bakayaro.live/captions/fixture-en.vtt"
        let transport = try streamTransport(rows: [exactRow], videoURL: absoluteVideo, captionURL: absoluteCaption)
        let engine = ConnectorEngine(manifest: try r2Manifest(), transport: transport, retryDelays: [0])
        let streams = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1")
        XCTAssertEqual(streams.first?.url.absoluteString, absoluteVideo)
        XCTAssertEqual(streams.first?.subtitles.first?.url.absoluteString, absoluteCaption)

        let opaque = try streamTransport(rows: [exactRow])
        let opaqueEngine = ConnectorEngine(manifest: try r2Manifest(), transport: opaque, retryDelays: [0])
        let opaqueStreams = try await opaqueEngine.streams(titleID: "naruto-123", episodeID: "enc-payload-1")
        XCTAssertEqual(opaqueStreams.first?.url.absoluteString, "https://og.bakayaro.live/fixture-sub-token")
        XCTAssertEqual(opaqueStreams.first?.subtitles.first?.url.absoluteString,
                       "https://og.bakayaro.live/fixture-en-caption-token")
    }

    func testR2RejectsWrongYearAndConflictingCatalogueId() async throws {
        var wrongYear = exactRow; wrongYear["year"] = 2003
        var wrongID = exactRow; wrongID["anilistId"] = 999
        for row in [wrongYear, wrongID] {
            let transport = try streamTransport(rows: [row])
            let engine = ConnectorEngine(manifest: try r2Manifest(), transport: transport, retryDelays: [0])
            do {
                _ = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1")
                XCTFail("R2 must not relax year or known AniList identity")
            } catch { }
            XCTAssertFalse(transport.requestedURLs.contains { $0.contains("/sources?") })
        }
    }

    func testR3VisibleEnglishHeadingMatchesWhenDataJpIsForeignTitle() async throws {
        let visible = "Komi Can't Communicate"
        let row: [String: Any] = [
            "slug": "komi-5617", "anilistId": 999,
            "title": ["english": "Komi Can’t Communicate"],
            "year": 2021, "format": "TV",
        ]
        let transport = try streamTransport(rows: [row], linked: false,
            aired: "Jan 7, 2021 to Jun 24, 2021", visibleTitle: visible,
            dataJPTitle: "Komi-san wa, Comyushou desu.", year: 2021)
        let engine = ConnectorEngine(manifest: try r3Manifest(), transport: transport, retryDelays: [0])
        // The fixture watch/server routes use these opaque source-owned IDs;
        // identity must come from the returned metadata, not the ID's spelling.
        let streams = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1")
        XCTAssertEqual(streams.first?.url.absoluteString, "https://og.bakayaro.live/fixture-sub-token")
        XCTAssertTrue(transport.requestedURLs.contains(
            browseURLFor(title: visible, year: 2021)))
        XCTAssertTrue(transport.requestedURLs.contains(sourcePrefix(for: "komi-5617") + "sub&refresh=1"))
    }

    func testR3DataJpIsUsedOnlyWhenVisibleHeadingIsMissing() async throws {
        let transport = try streamTransport(rows: [exactRow], visibleTitle: "", dataJPTitle: "Naruto")
        let engine = ConnectorEngine(manifest: try r3Manifest(), transport: transport, retryDelays: [0])
        let streams = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1")
        XCTAssertEqual(streams.first?.url.absoluteString, "https://og.bakayaro.live/fixture-sub-token")
        XCTAssertTrue(transport.requestedURLs.contains(browseURL))
    }

    func testR3VisibleTitleDoesNotOverrideConflictingBannerId() async throws {
        var matchingMetadataWrongID = exactRow
        matchingMetadataWrongID["anilistId"] = 999
        let transport = try streamTransport(rows: [matchingMetadataWrongID], visibleTitle: "Naruto",
            dataJPTitle: "Alternative title", catalogueID: 20)
        let engine = ConnectorEngine(manifest: try r3Manifest(), transport: transport, retryDelays: [0])
        do {
            _ = try await engine.streams(titleID: "naruto-123", episodeID: "enc-payload-1")
            XCTFail("visible-title equality must not override a conflicting AniList banner ID")
        } catch { }
        XCTAssertFalse(transport.requestedURLs.contains { $0.contains("/sources?") })
    }
}
