import Foundation
import XCTest
import VireoCore

/// Reviewed card-metadata contract (Find a niche): genres, year and status must reach title cards
/// from the AniList response, in search and in discovery, without changing the title identity.
final class SynthetiqAnimeNicheCardTests: XCTestCase {
    private struct Fixed: HTTPTransport {
        let body: String
        func execute(_ request: URLRequest, redirectPolicy: RedirectPolicy, maxResponseBytes: Int) async throws -> TransportResponse {
            TransportResponse(data: Data(body.utf8), statusCode: 200, finalURL: request.url!, headers: [:])
        }
    }
    private let body = #"{"data":{"Page":{"media":[{"id":1,"idMal":20,"title":{"english":"Naruto","romaji":"Naruto"},"coverImage":{"large":"https://s4.anilist.co/a.jpg"},"seasonYear":2002,"status":"FINISHED","genres":["Action","Adventure"]},{"id":2,"idMal":21,"title":{"english":null,"romaji":"One Piece"},"coverImage":{"large":"https://s4.anilist.co/b.jpg"},"seasonYear":1999,"status":"RELEASING","genres":["Adventure"]},{"id":3,"idMal":22,"title":{"english":"Soon","romaji":"Soon"},"coverImage":{"large":"https://s4.anilist.co/c.jpg"},"seasonYear":null,"status":"NOT_YET_RELEASED","genres":[]}]}}}"#

    private func manifest() throws -> ConnectorManifest {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let url = root.appendingPathComponent("connectors/synthetiq-anime-testing.json")
            if FileManager.default.fileExists(atPath: url.path) {
                return try ConnectorValidator.validate(manifestData: Data(contentsOf: url))
            }
            root = root.deletingLastPathComponent()
        }
        throw NSError(domain: "NicheCardTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "candidate manifest not found"])
    }

    func testSearchCardsCarryGenresYearAndStatusWithoutChangingIdentity() async throws {
        let engine = ConnectorEngine(manifest: try manifest(), transport: Fixed(body: body))
        let cards = try await engine.search(query: "naruto")
        XCTAssertEqual(cards.map(\.sourceID), ["20", "21", "22"])
        XCTAssertEqual(cards[0].metadata.genres, ["Action", "Adventure"])
        XCTAssertEqual(cards[0].metadata.year, 2002)
        XCTAssertEqual(cards[0].metadata.status, .completed)
        XCTAssertEqual(cards[1].metadata.status, .ongoing)
        XCTAssertEqual(cards[2].metadata.status, .upcoming)
        XCTAssertNil(cards[2].metadata.year)
        XCTAssertTrue(cards[2].metadata.genres.isEmpty)
    }

    func testDiscoveryCardsCarryGenresYearAndStatus() async throws {
        let engine = ConnectorEngine(manifest: try manifest(), transport: Fixed(body: body))
        let sections = try await engine.loadDiscovery()
        XCTAssertFalse(sections.isEmpty)
        for section in sections {
            XCTAssertEqual(section.items.first?.metadata.genres, ["Action", "Adventure"], section.id)
            XCTAssertEqual(section.items.first?.metadata.status, .completed, section.id)
        }
    }
}
