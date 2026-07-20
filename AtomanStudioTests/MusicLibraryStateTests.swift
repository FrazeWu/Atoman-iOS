import AtomanCore
import Foundation
import XCTest
@testable import AtomanMusic

@MainActor
final class MusicLibraryStateTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testLoadKeepsSuccessfulSectionsWhenHistoryFails() async {
        URLProtocolStub.requestHandler = { request in
            switch request.url?.path {
            case "/api/v1/music/playlists":
                return Self.response(request, body: "{\"data\":[{\"id\":\"favorite-1\",\"name\":\"最爱\",\"is_public\":false,\"is_favorite\":true,\"song_count\":0}]}")
            case "/api/v1/music/playlists/favorite-1":
                return Self.response(request, body: "{\"data\":{\"id\":\"favorite-1\",\"name\":\"最爱\",\"is_public\":false,\"is_favorite\":true,\"song_count\":0}}")
            case "/api/v1/music/playlists/favorite-1/songs":
                return Self.response(request, body: "{\"data\":[]}")
            case "/api/v1/music/bookmarks/albums":
                return Self.response(request, body: "{\"data\":[{\"id\":\"album-bookmark-1\",\"album_id\":\"album-1\",\"album\":{\"id\":\"album-1\",\"title\":\"Album One\"}}]}")
            case "/api/v1/music/bookmarks/artists":
                return Self.response(request, body: "{\"data\":[{\"id\":\"artist-bookmark-1\",\"artist_id\":\"artist-1\",\"artist\":{\"id\":\"artist-1\",\"name\":\"Artist One\"}}]}")
            case "/api/v1/music/history":
                return Self.response(request, statusCode: 500, body: "{\"error\":\"failed\"}")
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let authSession = AuthSessionStore(token: "token-1")
        let api = MusicAPI(
            client: APIClient(
                baseURL: URL(string: "https://example.com/api/v1")!,
                session: URLSession(configuration: configuration)
            ),
            authSession: authSession
        )
        let state = MusicLibraryState()

        await state.load(api: api)

        XCTAssertEqual(state.playlists.first?.name, "最爱")
        XCTAssertEqual(state.favoriteAlbums.first?.album?.title, "Album One")
        XCTAssertEqual(state.favoriteArtists.first?.artist?.name, "Artist One")
        XCTAssertTrue(state.history.isEmpty)
        XCTAssertEqual(state.failedSections, [.history])
    }

    private static func response(
        _ request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }
}
