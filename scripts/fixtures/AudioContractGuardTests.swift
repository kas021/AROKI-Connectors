import Foundation
import XCTest
@testable import VireoCore

/// Portable VireoCoreTests-target tests for the two lane candidates. Copy this
/// file into the released core test target when integrating; it deliberately
/// uses only StubTransport and the shipped declarative graph runtime.
final class AudioContractGuardTests: XCTestCase {
    private enum Module: CaseIterable {
        case aniPM
        case flux

        var id: String {
            switch self {
            case .aniPM: return "anipm"
            case .flux: return "synthetiq-anime-direct"
            }
        }

        var candidate: String {
            switch self {
            case .aniPM: return "anipm-0.1.3.json"
            case .flux: return "synthetiq-anime-direct-0.1.5.json"
            }
        }

        var baseline: String {
            switch self {
            case .aniPM: return "anipm.baseline.json"
            case .flux: return "synthetiq-anime-direct.baseline.json"
            }
        }

        static func resolve(_ raw: String?) throws -> [Module] {
            guard let raw, !raw.isEmpty else { return Array(Self.allCases) }
            guard let module = Self.allCases.first(where: { $0.id == raw }) else {
                throw NSError(domain: "AudioContractGuardTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "unknown AROKI_AUDIO_GUARD_MODULE value"])
            }
            return [module]
        }

        var bootstrapURL: String {
            switch self {
            case .aniPM:
                return "https://ani.pm/api/anime/playback-bootstrap/anipm/title?ep=episode-1&lang={variant}&backup=0"
            case .flux:
                return "https://ani.pm/api/anime/playback-bootstrap/anilist/42?ep=episode-1&lang={variant}&backup=0"
            }
        }
    }

    private var runRoot: URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let laneMarker = current.appendingPathComponent("lanes/provider/audio-guards/candidates/anipm-0.1.3.json")
            let ciMarker = current.appendingPathComponent("connectors/audio-guard-baselines/anipm.json")
            if FileManager.default.fileExists(atPath: laneMarker.path)
                || FileManager.default.fileExists(atPath: ciMarker.path) { return current }
            current = current.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }

    private func candidateData(_ module: Module) throws -> Data {
        let lane = runRoot.appendingPathComponent("lanes/provider/audio-guards/candidates/\(module.candidate)")
        let ci = runRoot.appendingPathComponent("connectors/\(module.id).json")
        let url = FileManager.default.fileExists(atPath: lane.path) ? lane : ci
        return try Data(contentsOf: url)
    }

    private func baselineData(_ module: Module) throws -> Data {
        let local = runRoot.appendingPathComponent("candidates/\(module.baseline)")
        let ci = runRoot.appendingPathComponent("connectors/audio-guard-baselines/\(module.id).json")
        let url = FileManager.default.fileExists(atPath: local.path) ? local : ci
        return try Data(contentsOf: url)
    }

    private func makeTransport(
        _ module: Module,
        variant: AudioVariant,
        bootstrap: [String: Any],
        bootstrapStatus: Int = 200
    ) throws -> StubTransport {
        let transport = StubTransport()
        switch module {
        case .aniPM:
            transport.route("https://ani.pm/api/anime/series/title?phase=core",
                            .success(status: 200, data: Data(#"{"source":"anipm"}"#.utf8)))
        case .flux:
            transport.route("https://graphql.anilist.co",
                            .success(status: 200, data: Data(#"{"data":{"Media":{"id":42}}}"#.utf8)))
        }
        let bootstrapURL = module.bootstrapURL.replacingOccurrences(of: "{variant}", with: variant.rawValue)
        transport.route(bootstrapURL, .success(status: bootstrapStatus,
                                               data: try JSONSerialization.data(withJSONObject: bootstrap)))
        transport.route("https://ani.pm/api/anime/settlar/session?selection=fixture-selection&provider=anipm&ep=episode-1&channel=\(variant.rawValue)&telemetry=0",
                        .success(status: 200, data: Data(#"{"embedUrl":"https://embed.settlar.io/embed?t=fixture-token"}"#.utf8)))
        transport.route("https://embed.settlar.io/api/embed/session?t=fixture-token",
                        .success(status: 200, data: Data(#"{"source":"https://media.settlar.io/fixture.m3u8","kind":"hls","expiresAt":1799999999,"subtitles":[{"url":"https://media.settlar.io/captions.vtt","label":"English","srclang":"en"}]}"#.utf8)))
        return transport
    }

    private func validBootstrap(language: String, availability: [String: Any] = ["sub": true, "dub": true]) -> [String: Any] {
        ["settlarSelection": "fixture-selection", "availability": availability, "effectiveLanguage": language]
    }

    private func bootstrapURL(_ module: Module, variant: AudioVariant) -> String {
        module.bootstrapURL.replacingOccurrences(of: "{variant}", with: variant.rawValue)
    }

    private func sessionURL(_ variant: AudioVariant) -> String {
        "https://ani.pm/api/anime/settlar/session?selection=fixture-selection&provider=anipm&ep=episode-1&channel=\(variant.rawValue)&telemetry=0"
    }

    private func resolve(_ module: Module, variant: AudioVariant, bootstrap: [String: Any]) async throws -> (StubTransport, [StreamCandidate]) {
        let transport = try makeTransport(module, variant: variant, bootstrap: bootstrap)
        let manifest = try ConnectorValidator.validate(manifestData: candidateData(module))
        let streams = try await ConnectorEngine(manifest: manifest, transport: transport, retryDelays: [])
            .streams(titleID: "title", episodeID: "episode-1", variant: variant)
        return (transport, streams)
    }

    func testPositiveSubAndDubStayOnTheirDeclaredAudioRoute() async throws {
        for module in try Module.resolve(ProcessInfo.processInfo.environment["AROKI_AUDIO_GUARD_MODULE"]) {
            for variant in [AudioVariant.sub, .dub] {
                let (transport, streams) = try await resolve(module, variant: variant,
                                                             bootstrap: validBootstrap(language: " \(variant.rawValue.uppercased()) "))
                XCTAssertEqual(streams.count, 1, "\(module.id) \(variant.rawValue)")
                XCTAssertEqual(transport.requestedURLs[1], bootstrapURL(module, variant: variant))
                XCTAssertTrue(transport.requestedURLs.contains(sessionURL(variant)))
                XCTAssertEqual(transport.recorded.count, 4)
                XCTAssertEqual(streams.first?.subtitles.first?.languageCode, "en")
            }
        }
    }

    func testFalseMissingAndInvalidAvailabilityBlockBeforeSession() async throws {
        var missingObject = validBootstrap(language: "sub")
        missingObject.removeValue(forKey: "availability")
        let invalidCases: [[String: Any]] = [
            ["sub": false, "dub": true],
            ["dub": true],
            ["sub": "available", "dub": true],
            ["sub": 1, "dub": true],
        ]
        for module in try Module.resolve(ProcessInfo.processInfo.environment["AROKI_AUDIO_GUARD_MODULE"]) {
            let responses = invalidCases.map { validBootstrap(language: "sub", availability: $0) } + [missingObject]
            for bootstrap in responses {
                let transport = try makeTransport(module, variant: .sub, bootstrap: bootstrap)
                let manifest = try ConnectorValidator.validate(manifestData: candidateData(module))
                do {
                    _ = try await ConnectorEngine(manifest: manifest, transport: transport, retryDelays: [])
                        .streams(titleID: "title", episodeID: "episode-1", variant: .sub)
                    XCTFail("invalid Sub availability must fail closed")
                } catch {}
                XCTAssertFalse(transport.requestedURLs.contains(sessionURL(.sub)))
                XCTAssertEqual(transport.requestedURLs.count, 2)
            }
        }
    }

    func testOppositeUnknownAndMissingEffectiveLanguageBlock() async throws {
        let invalidLanguages: [String?] = ["dub", "sub", "multi", " ", nil]
        for module in try Module.resolve(ProcessInfo.processInfo.environment["AROKI_AUDIO_GUARD_MODULE"]) {
            for variant in [AudioVariant.sub, .dub] {
                for language in invalidLanguages {
                    if let language, language == variant.rawValue { continue }
                    var bootstrap = validBootstrap(language: language ?? "sub")
                    if language == nil { bootstrap.removeValue(forKey: "effectiveLanguage") }
                    let transport = try makeTransport(module, variant: variant, bootstrap: bootstrap)
                    let manifest = try ConnectorValidator.validate(manifestData: candidateData(module))
                    do {
                        _ = try await ConnectorEngine(manifest: manifest, transport: transport, retryDelays: [])
                            .streams(titleID: "title", episodeID: "episode-1", variant: variant)
                        XCTFail("missing or conflicting language declaration must fail closed")
                    } catch {}
                    XCTAssertFalse(transport.requestedURLs.contains(sessionURL(variant)))
                    XCTAssertEqual(transport.requestedURLs.count, 2)
                }
            }
        }
    }

    func testDubNeverFallsBackToSubWhenDubIsUnavailable() async throws {
        for module in try Module.resolve(ProcessInfo.processInfo.environment["AROKI_AUDIO_GUARD_MODULE"]) {
            let transport = try makeTransport(module, variant: .dub,
                                              bootstrap: validBootstrap(language: "sub", availability: ["sub": true, "dub": false]))
            let manifest = try ConnectorValidator.validate(manifestData: candidateData(module))
            do {
                _ = try await ConnectorEngine(manifest: manifest, transport: transport, retryDelays: [])
                    .streams(titleID: "title", episodeID: "episode-1", variant: .dub)
                XCTFail("unavailable Dub must not silently borrow Sub")
            } catch {}
            XCTAssertTrue(transport.requestedURLs[1].contains("lang=dub"))
            XCTAssertFalse(transport.requestedURLs.contains(sessionURL(.dub)))
            XCTAssertFalse(transport.requestedURLs.contains(sessionURL(.sub)))
        }
    }

    func testBootstrap429StopsBeforeSettlarSession() async throws {
        for module in try Module.resolve(ProcessInfo.processInfo.environment["AROKI_AUDIO_GUARD_MODULE"]) {
            let transport = try makeTransport(module, variant: .sub,
                                              bootstrap: validBootstrap(language: "sub"), bootstrapStatus: 429)
            let manifest = try ConnectorValidator.validate(manifestData: candidateData(module))
            do {
                _ = try await ConnectorEngine(manifest: manifest, transport: transport, retryDelays: [])
                    .streams(titleID: "title", episodeID: "episode-1", variant: .sub)
                XCTFail("429 must stop the graph")
            } catch let error as EngineError {
                XCTAssertEqual(error, .badStatus(429))
            }
            XCTAssertFalse(transport.requestedURLs.contains(sessionURL(.sub)))
            XCTAssertEqual(transport.requestedURLs.count, 2)
        }
    }

    func testOnlyVersionFloorFeatureAndReleaseNotesChangeOutsideAudioGuards() throws {
        for module in try Module.resolve(ProcessInfo.processInfo.environment["AROKI_AUDIO_GUARD_MODULE"]) {
            var baseline = try JSONSerialization.jsonObject(with: baselineData(module)) as! [String: Any]
            var candidate = try JSONSerialization.jsonObject(with: candidateData(module)) as! [String: Any]
            for root in ["version", "minimumAppVersion", "releaseNotes"] {
                baseline.removeValue(forKey: root)
                candidate.removeValue(forKey: root)
            }
            let oldFeatures = baseline["requiredEngineFeatures"] as? [String] ?? []
            let newFeatures = candidate["requiredEngineFeatures"] as? [String] ?? []
            XCTAssertEqual(newFeatures.filter { $0 != "typed-graph-context-v1" }, oldFeatures)
            if oldFeatures.isEmpty {
                candidate.removeValue(forKey: "requiredEngineFeatures")
            } else {
                candidate["requiredEngineFeatures"] = oldFeatures
            }
            func removeGuards(_ root: inout [String: Any]) {
                guard var operations = root["operations"] as? [String: Any],
                      var streams = operations["streams"] as? [String: Any],
                      var steps = streams["steps"] as? [[String: Any]], steps.count > 1,
                      var extract = steps[1]["extract"] as? [String: Any],
                      var context = extract["context"] as? [String: Any] else { return }
                context.removeValue(forKey: "audioAvailable")
                context.removeValue(forKey: "audioMatches")
                extract["context"] = context
                steps[1]["extract"] = extract
                streams["steps"] = steps
                operations["streams"] = streams
                root["operations"] = operations
            }
            removeGuards(&candidate)
            let left = try JSONSerialization.data(withJSONObject: baseline, options: [.sortedKeys])
            let right = try JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys])
            XCTAssertEqual(left, right, "only the named guard, version, compatibility floor, feature declaration, and release notes may change")
        }
    }
}
