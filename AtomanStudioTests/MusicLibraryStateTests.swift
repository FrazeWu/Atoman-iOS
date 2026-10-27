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

    func testLoadMorePaginatesLibraryCollections() async throws {
        URLProtocolStub.requestHandler = { request in
            let path = request.url!.path
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let page = query.first(where: { $0.name == "page" })?.value ?? "1"
            switch path {
            case "/api/v1/music/playlists":
                if page == "2" {
                    return Self.response(request, body: """
                    {"data":[{"id":"playlist-2","name":"Second","is_public":false,"is_favorite":false,"song_count":0}],"meta":{"has_more":false}}
                    """)
                }
                return Self.response(request, body: """
                {"data":[{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":0}],"meta":{"has_more":true}}
                """)
            case "/api/v1/music/playlists/favorite-1":
                return Self.response(request, body: "{\"data\":{\"id\":\"favorite-1\",\"name\":\"最爱\",\"is_public\":false,\"is_favorite\":true,\"song_count\":0}}")
            case "/api/v1/music/playlists/favorite-1/songs":
                return Self.response(request, body: "{\"data\":[]}")
            case "/api/v1/music/bookmarks/albums":
                let index = page == "1" ? "1" : "2"
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-\(index)","album_id":"album-\(index)","album":{"id":"album-\(index)","title":"Album \(index)"}}],"meta":{"has_more":\(page == "1" ? "true" : "false")}}
                """)
            case "/api/v1/music/bookmarks/artists", "/api/v1/music/history":
                return Self.response(request, body: "{\"data\":[],\"meta\":{\"has_more\":false}}")
            default: throw URLError(.unsupportedURL)
            }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        let api = MusicAPI(
            client: APIClient(baseURL: URL(string: "https://example.com/api/v1")!, session: URLSession(configuration: config)),
            authSession: AuthSessionStore(token: "token-1")
        )
        let state = MusicLibraryState()
        await state.load(api: api)
        XCTAssertTrue(state.moreSections.contains(.albums))
        XCTAssertTrue(state.moreSections.contains(.playlists))
        await state.loadMore(.albums, api: api)
        await state.loadMore(.playlists, api: api)
        XCTAssertEqual(state.favoriteAlbums.map(\.id), ["bookmark-1", "bookmark-2"])
        XCTAssertEqual(state.playlists.map(\.id), ["favorite-1", "playlist-2"])
        XCTAssertFalse(state.moreSections.contains(.albums))
        XCTAssertFalse(state.moreSections.contains(.playlists))
        XCTAssertTrue(state.failedSections.isEmpty)
    }

    private static func response(
        _ request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }
}
