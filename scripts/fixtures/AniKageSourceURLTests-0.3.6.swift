import XCTest
@testable import VireoCore

final class AniKageSourceURLTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath:#filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func manifest() throws -> ConnectorManifest {
        try ConnectorValidator.validate(manifestData:Data(contentsOf:root.appendingPathComponent("connectors/anikage.json")))
    }
    private func streams(video: String, caption: String, variant: AudioVariant = .sub) async throws -> [StreamCandidate] {
        let transport = StubTransport()
        let response: [String:Any] = ["sources":[["url":video,"quality":"1080p"]],
            "subtitles":[["file":caption,"label":"English","srclang":"en"]]]
        transport.route("https://anikage.cc/api/media/anime/fixture-title/episodes/1/sources?provider=koto&lang=\(variant.rawValue)&refresh=1",
            .success(status:200,data:try JSONSerialization.data(withJSONObject:response)))
        return try await ConnectorEngine(manifest:manifest(),transport:transport,retryDelays:[])
            .streams(titleID:"fixture-title",episodeID:"1",variant:variant)
    }
    func testExistingHostPolicyAndMinimumAreNotWidened() throws {
        let value = try manifest()
        XCTAssertEqual(value.id,"anikage"); XCTAssertEqual(value.familyID,"anikage")
        XCTAssertEqual(value.version.description,"0.3.6")
        XCTAssertEqual(value.minimumAppVersion.description,"0.1.0")
        XCTAssertEqual(value.operations.streams?.finalMediaURLPolicy,.allowlisted)
        XCTAssertEqual(value.operations.streams?.variants,[.sub,.dub])
    }
    func testOpaqueTokensKeepOriginalProxyAndCaptionLanguage() async throws {
        let result = try await streams(video:"fixture-video-token",caption:"fixture-caption-token")
        XCTAssertEqual(result.first?.url.absoluteString,"https://og.bakayaro.live/fixture-video-token")
        XCTAssertEqual(result.first?.subtitles.first?.url.absoluteString,"https://og.bakayaro.live/fixture-caption-token")
        XCTAssertEqual(result.first?.subtitles.first?.languageCode,"en")
        XCTAssertEqual(result.first?.headers["origin"] ?? result.first?.headers["Origin"],"https://anikage.cc")
    }
    func testAbsoluteAllowedURLsAreNotDoublePrefixed() async throws {
        let video = "https://og.bakayaro.live/fixture/master.m3u8"
        let caption = "https://og.bakayaro.live/fixture/english.vtt"
        let result = try await streams(video:video,caption:caption,variant:.dub)
        XCTAssertEqual(result.first?.url.absoluteString,video)
        XCTAssertEqual(result.first?.subtitles.first?.url.absoluteString,caption)
    }
    func testUnlistedVideoAndCaptionHostsRemainRejected() async throws {
        do {
            _ = try await streams(video:"https://unlisted.invalid/master.m3u8",caption:"fixture-caption-token")
            XCTFail("The URL-shape fix must not widen the final-media host policy")
        } catch { }
        let result = try await streams(video:"fixture-video-token",caption:"https://unlisted.invalid/english.vtt")
        XCTAssertTrue(result.first?.subtitles.isEmpty == true)
    }
}
