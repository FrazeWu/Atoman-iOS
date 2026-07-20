import AtomanCore
import Foundation
import XCTest
@testable import AtomanMusic

@MainActor
final class MusicAuthenticationCoordinatorTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testGuestFavoritePresentsLoginWithoutSendingRequest() async {
        var requestCount = 0
        let environment = makeEnvironment(token: nil) { request in
            requestCount += 1
            throw URLError(.unsupportedURL)
        }

        await environment.requestFavoriteSong(id: "song-1", isFavorite: true)

        XCTAssertEqual(requestCount, 0)
        XCTAssertTrue(environment.authentication.isPresented)
        XCTAssertEqual(environment.authentication.pendingAction, .favoriteSong(id: "song-1", isFavorite: true))
    }

    func testCompletedLoginReplaysPendingFavoriteOnlyOnce() async throws {
        var favoritePostCount = 0
        let environment = makeEnvironment(token: nil) { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/music/playlists"):
                return Self.response(request, body: """
                {"data":[{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":0}]}
                """)
            case ("GET", "/api/v1/music/playlists/favorite-1"):
                return Self.response(request, body: """
                {"data":{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":0}}
                """)
            case ("GET", "/api/v1/music/playlists/favorite-1/songs"):
                return Self.response(request, body: "{" + #""data":[]"# + "}")
            case ("GET", "/api/v1/music/bookmarks/albums"),
                 ("GET", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, body: "{" + #""data":[]"# + "}")
            case ("POST", "/api/v1/music/playlists/favorite-1/songs"):
                favoritePostCount += 1
                return Self.response(request, statusCode: 201, body: #"{"data":{"id":"entry-1"}}"#)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        await environment.requestFavoriteSong(id: "song-1", isFavorite: true)
        try environment.authSession.authenticate(AuthSessionPayload(token: "token-1", user: Self.user))

        await environment.completeAuthentication()
        await environment.completeAuthentication()

        XCTAssertEqual(favoritePostCount, 1)
        XCTAssertTrue(environment.favoriteSongIDs.contains("song-1"))
        XCTAssertFalse(environment.authentication.isPresented)
        XCTAssertNil(environment.authentication.pendingAction)
    }

    func testCompletedLoginReplaysPendingAlbumFavorite() async throws {
        var favoritePostCount = 0
        let environment = makeEnvironment(token: nil) { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/music/playlists"):
                return Self.response(request, body: #"{"data":[]}"#)
            case ("GET", "/api/v1/music/bookmarks/albums"),
                 ("GET", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, body: #"{"data":[]}"#)
            case ("POST", "/api/v1/music/bookmarks/albums"):
                favoritePostCount += 1
                return Self.response(request, statusCode: 201, body: #"{"data":{"id":"bookmark-1"}}"#)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        await environment.requestFavoriteAlbum(id: "album-1", isFavorite: true)
        try environment.authSession.authenticate(AuthSessionPayload(token: "token-1", user: Self.user))

        await environment.completeAuthentication()

        XCTAssertEqual(favoritePostCount, 1)
        XCTAssertTrue(environment.favoriteAlbumIDs.contains("album-1"))
    }

    func testCompletedLoginReplaysPendingArtistFavorite() async throws {
        var favoritePostCount = 0
        let environment = makeEnvironment(token: nil) { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/music/playlists"):
                return Self.response(request, body: #"{"data":[]}"#)
            case ("GET", "/api/v1/music/bookmarks/albums"),
                 ("GET", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, body: #"{"data":[]}"#)
            case ("POST", "/api/v1/music/bookmarks/artists"):
                favoritePostCount += 1
                return Self.response(request, statusCode: 201, body: #"{"data":{"id":"bookmark-1"}}"#)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        await environment.requestFavoriteArtist(id: "artist-1", isFavorite: true)
        try environment.authSession.authenticate(AuthSessionPayload(token: "token-1", user: Self.user))

        await environment.completeAuthentication()

        XCTAssertEqual(favoritePostCount, 1)
        XCTAssertTrue(environment.favoriteArtistIDs.contains("artist-1"))
    }

    func testLogoutKeepsCurrentPlaybackQueue() throws {
        let environment = makeEnvironment(token: "token-1") { _ in
            throw URLError(.unsupportedURL)
        }
        let songs = [try Self.song(id: "song-1"), try Self.song(id: "song-2")]
        environment.player.play(songs: songs, startingAt: "song-2")

        environment.logout()

        XCTAssertFalse(environment.authSession.isAuthenticated)
        XCTAssertEqual(environment.player.currentSong?.id, "song-2")
        XCTAssertEqual(environment.player.songs.map(\.id), ["song-1", "song-2"])
    }

    func testAuthenticationUsesPlayerPresentationContextWhilePlayerIsOpen() {
        let environment = makeEnvironment(token: nil) { _ in
            throw URLError(.unsupportedURL)
        }
        environment.authentication.present()

        XCTAssertTrue(environment.presentsAuthenticationInRoot)
        XCTAssertFalse(environment.presentsAuthenticationInPlayer)

        environment.player.isShowingPlayer = true

        XCTAssertFalse(environment.presentsAuthenticationInRoot)
        XCTAssertTrue(environment.presentsAuthenticationInPlayer)
    }

    private func makeEnvironment(
        token: String?,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> MusicAppEnvironment {
        URLProtocolStub.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let authSession = AuthSessionStore(token: token)
        let api = MusicAPI(
            client: APIClient(
                baseURL: URL(string: "https://example.com/api/v1")!,
                session: URLSession(configuration: configuration)
            ),
            authSession: authSession
        )
        return MusicAppEnvironment(
            api: api,
            authSession: authSession,
            player: MusicPlayer(engine: AuthenticationPlaybackEngineSpy())
        )
    }

    private static let user = AuthUser(
        id: 7,
        uuid: "user-1",
        username: "alice",
        email: "alice@example.com",
        role: "user"
    )

    private static func response(
        _ request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!,
            Data(body.utf8)
        )
    }

    private static func song(id: String) throws -> MusicSong {
        try JSONDecoder().decode(
            MusicSong.self,
            from: Data(#"{"id":"\#(id)","title":"Song \#(id)","audio_url":"https://cdn.example.com/\#(id).mp3"}"#.utf8)
        )
    }
}

@MainActor
private final class AuthenticationPlaybackEngineSpy: MusicPlaybackEngine {
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
