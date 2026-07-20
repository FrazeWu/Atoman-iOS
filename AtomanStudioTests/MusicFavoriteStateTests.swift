import AtomanCore
import Foundation
import XCTest
@testable import AtomanMusic

@MainActor
final class MusicFavoriteStateTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testRefreshFavoritesCachesLibraryIDs() async {
        let environment = makeEnvironment()

        await environment.refreshFavorites()

        XCTAssertEqual(environment.favoriteSongIDs, ["song-1"])
        XCTAssertEqual(environment.favoriteAlbumIDs, ["album-1"])
        XCTAssertEqual(environment.favoriteArtistIDs, ["artist-1"])
    }

    func testRefreshFavoritesKeepsBookmarksWhenFavoritePlaylistIsMissing() async {
        let environment = makeEnvironment()
        URLProtocolStub.requestHandler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/music/playlists"):
                return Self.response(request, body: #"{"data":[]}"#)
            case ("GET", "/api/v1/music/bookmarks/albums"):
                return Self.response(request, body: #"{"data":[{"id":"bookmark-album","album_id":"album-1"}]}"#)
            case ("GET", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, body: #"{"data":[{"id":"bookmark-artist","artist_id":"artist-1"}]}"#)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        await environment.refreshFavorites()

        XCTAssertNil(environment.favoritePlaylistID)
        XCTAssertEqual(environment.favoriteAlbumIDs, ["album-1"])
        XCTAssertEqual(environment.favoriteArtistIDs, ["artist-1"])
    }

    func testFavoriteMutationsUpdateSharedStateAfterServerSuccess() async throws {
        let environment = makeEnvironment()
        await environment.refreshFavorites()

        try await environment.setFavoriteSong(id: "song-2", isFavorite: true)
        try await environment.setFavoriteAlbum(id: "album-1", isFavorite: false)
        try await environment.setFavoriteArtist(id: "artist-1", isFavorite: false)

        XCTAssertEqual(environment.favoriteSongIDs, ["song-1", "song-2"])
        XCTAssertTrue(environment.favoriteAlbumIDs.isEmpty)
        XCTAssertTrue(environment.favoriteArtistIDs.isEmpty)
    }

    func testRefreshFavoritesClearsSharedStateAfterLogout() async {
        let environment = makeEnvironment()
        await environment.refreshFavorites()
        environment.authSession.clear()
        URLProtocolStub.requestHandler = { _ in throw URLError(.userAuthenticationRequired) }

        await environment.refreshFavorites()

        XCTAssertNil(environment.favoritePlaylistID)
        XCTAssertTrue(environment.favoriteSongIDs.isEmpty)
        XCTAssertTrue(environment.favoriteAlbumIDs.isEmpty)
        XCTAssertTrue(environment.favoriteArtistIDs.isEmpty)
    }

    private func makeEnvironment() -> MusicAppEnvironment {
        URLProtocolStub.requestHandler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/music/playlists"):
                return Self.response(request, body: "{\"data\":[{\"id\":\"favorite-1\",\"name\":\"最爱\",\"is_public\":false,\"is_favorite\":true,\"song_count\":1}]}")
            case ("GET", "/api/v1/music/playlists/favorite-1"):
                return Self.response(request, body: "{\"data\":{\"id\":\"favorite-1\",\"name\":\"最爱\",\"is_public\":false,\"is_favorite\":true,\"song_count\":1}}")
            case ("GET", "/api/v1/music/playlists/favorite-1/songs"):
                return Self.response(request, body: "{\"data\":[{\"id\":\"entry-1\",\"position\":1,\"song\":{\"id\":\"song-1\",\"title\":\"Favorite Song\",\"audio_url\":\"https://cdn.example.com/song-1.mp3\"}}]}")
            case ("GET", "/api/v1/music/bookmarks/albums"):
                return Self.response(request, body: "{\"data\":[{\"id\":\"bookmark-album\",\"album_id\":\"album-1\"}]}")
            case ("GET", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, body: "{\"data\":[{\"id\":\"bookmark-artist\",\"artist_id\":\"artist-1\"}]}")
            case ("POST", "/api/v1/music/playlists/favorite-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"entry-2\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/albums/album-1"),
                 ("DELETE", "/api/v1/music/bookmarks/artists/artist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let client = APIClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            session: URLSession(configuration: configuration)
        )
        let authSession = AuthSessionStore(token: "token-1")
        return MusicAppEnvironment(
            api: MusicAPI(client: client, authSession: authSession),
            authSession: authSession,
            player: MusicPlayer(engine: FavoritePlaybackEngine())
        )
    }

    private static func response(
        _ request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }
}

@MainActor
private final class FavoritePlaybackEngine: MusicPlaybackEngine {
    var onTimeUpdate: ((TimeInterval, TimeInterval) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onBufferingChanged: ((Bool) -> Void)?
    var onPlaybackFailed: ((String) -> Void)?
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?
    var onOutputDisconnected: (() -> Void)?

    func load(url: URL) {}
    func play() {}
    func pause() {}
    func seek(to time: TimeInterval) {}
}
