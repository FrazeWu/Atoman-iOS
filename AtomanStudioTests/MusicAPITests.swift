import AtomanCore
import Foundation
import XCTest
@testable import AtomanMusic

final class MusicAPITests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testSearchDecodesPlayableCatalog() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/music/search?page=1&page_size=20&q=echo")
            return Self.response(request, body: """
            {
              "data": {
                "songs": [{"id":"song-1","title":"Echo Song","audio_url":"https://cdn.example.com/echo.mp3","cover_url":"https://cdn.example.com/echo.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}]}],
                "albums": [{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}]}],
                "artists": [{"id":"artist-1","name":"Echo Artist","image_url":"https://cdn.example.com/artist.jpg"}],
                "playlists": [{"id":"playlist-1","name":"Echo Mix","is_public":true,"is_favorite":false,"song_count":1}]
              }
            }
            """)
        }

        let results = try await api.search(query: "echo")

        XCTAssertEqual(results.songs.first?.title, "Echo Song")
        XCTAssertEqual(results.songs.first?.artistText, "Echo Artist")
        XCTAssertEqual(results.albums.first?.title, "Echo Album")
        XCTAssertEqual(results.artists.first?.name, "Echo Artist")
        XCTAssertEqual(results.playlists.first?.name, "Echo Mix")
    }

    func testHomeFeedUsesLiveRecommendationAndPublicPlaylistContracts() async throws {
        let api = makeAPI { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let mode = components?.queryItems?.first(where: { $0.name == "mode" })?.value
            switch request.url?.path {
            case "/api/v1/music/recommend/albums":
                let id = mode == "hot" ? "album-1" : "album-2"
                return Self.response(request, body: """
                {"data":[{"id":"\(id)","title":"Echo \(id)","image_url":"https://cdn.example.com/\(id).jpg","target_path":"/music/album/\(id)"}],"meta":{"page":1,"page_size":8,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/recommend/artists":
                return Self.response(request, body: """
                {"data":[{"id":"artist-1","title":"Echo Artist","target_path":"/music/artist/artist-1"}],"meta":{"has_more":false}}
                """)
            case "/api/v1/music/playlists/public":
                // This is a public summary: it does NOT contain is_favorite.
                return Self.response(request, body: """
                {"data":[{"id":"playlist-1","name":"Echo Mix","is_public":true,"song_count":3}],"meta":{"has_more":false}}
                """)
            default: throw URLError(.unsupportedURL)
            }
        }

        let home = try await api.homeFeed()
        XCTAssertEqual(home.recommended.first?.type, .album)
        XCTAssertEqual(home.recommended.first?.title, "Echo album-1")
        XCTAssertEqual(home.latest.first?.id, "album-2")
        XCTAssertEqual(home.artists.first?.type, .artist)
        XCTAssertEqual(home.playlists.first?.displaySubtitle, "歌单 · 3 首")
    }

    func testHomeFeedPrefersPersonalizedAlbumsForAuthenticatedListeners() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            switch request.url?.path {
            case "/api/v1/music/home":
                return Self.response(request, body: """
                {"data":{"personalized":true,"recently_played":[],"for_you":[{"id":"personal-1","title":"Personal Album","cover_url":"https://cdn.example.com/p.jpg","reason":"根据你的收听习惯"}]}}
                """)
            case "/api/v1/music/recommend/albums":
                return Self.response(request, body: """
                {"data":[{"id":"hot-1","title":"Hot Album","target_path":"/music/album/hot-1"}]}
                """)
            case "/api/v1/music/recommend/artists", "/api/v1/music/playlists/public":
                return Self.response(request, body: "{\"data\":[]}")
            default: throw URLError(.unsupportedURL)
            }
        }

        let home = try await api.homeFeed()
        XCTAssertEqual(home.recommended.map(\.id), ["personal-1"])
        XCTAssertEqual(home.recommended.first?.displaySubtitle, "根据你的收听习惯")
    }

    func testSearchPageMergesAndDeduplicatesStableResults() async throws {
        let api = makeAPI { request in
            let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let page = comps?.queryItems?.first(where: { $0.name == "page" })?.value
            return Self.response(request, body: """
            {"data":{"songs":[{"id":"song-\(page == "1" ? "one" : "two")","title":"Song","audio_url":"https://example.com/s.mp3"}],"albums":[],"artists":[],"playlists":[],"meta":{"page":\(page ?? "1"),"page_size":20,"totals":{"song":40,"album":0,"artist":0,"playlist":0},"has_more":{"song":\(page == "1" ? "true" : "false"),"album":false,"artist":false,"playlist":false}}}}
            """)
        }
        let first = try await api.search(query: "song")
        XCTAssertTrue(first.meta?.hasNextPage == true)
        let second = try await api.search(query: "song", page: 2)
        let joined = first.appending(second).appending(second)
        XCTAssertEqual(joined.songs.map(\.id), ["song-one", "song-two"])
        XCTAssertFalse(joined.meta?.hasNextPage ?? true)
    }

    func testRemotePlaybackSessionAndProgressUseBackendFields() async throws {
        let id = "fd1663f9-96bc-43a7-a805-fd829622e37a"
        var savedPaths: [String] = []
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            let path = request.url!.path
            if request.httpMethod == "GET" {
                XCTAssertEqual(path, "/api/v1/music/playback-session")
                return Self.response(request, body: """
                {"data":{"queue":[{"id":"\(id)","title":"Track","audio_url":"https://cdn.example.com/song.mp3"}],"current_song_id":"\(id)","position_seconds":42.5,"playback_mode":"single","updated_at":"2026-10-27T12:00:00Z"}}
                """)
            }
            savedPaths.append(path)
            let body = try XCTUnwrap(Self.jsonBody(from: request))
            XCTAssertNotNil(body["reported_at"] as? String)
            if path == "/api/v1/music/playback-session" {
                XCTAssertEqual(body["current_song_id"] as? String, id)
                XCTAssertEqual(body["playback_mode"] as? String, "single")
                XCTAssertEqual(body["song_ids"] as? [String], [id])
            } else {
                XCTAssertEqual(body["song_id"] as? String, id)
                XCTAssertEqual(body["position_seconds"] as? Double, 42.5)
            }
            return Self.response(request, body: "{\"data\":{}}")
        }
        let remote = try await api.remotePlaybackSession()
        let session = try XCTUnwrap(remote)
        XCTAssertEqual(session.queue.first?.id, id)
        XCTAssertEqual(session.positionSeconds, 42.5)
        let snapshot = MusicPlaybackSnapshot(songs: session.queue, currentSongID: id, currentTime: 42.5, playbackMode: .repeatOne)
        try await api.savePlaybackSession(snapshot)
        try await api.savePlaybackProgress(songID: id, position: 42.5, duration: 200, completed: false)
        XCTAssertEqual(savedPaths, ["/api/v1/music/playback-session", "/api/v1/music/playback-progress"])
    }

    func testAlbumDecodesPlayableSongs() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/music/albums/album-1")
            return Self.response(request, body: """
            {"data":{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}],"songs":[{"id":"song-1","title":"Echo Song","track_number":1,"audio_url":"https://cdn.example.com/echo.mp3"}]}}
            """)
        }

        let album = try await api.album(id: "album-1")

        XCTAssertEqual(album.songs.first?.title, "Echo Song")
        XCTAssertEqual(album.songs.first?.audioURL, "https://cdn.example.com/echo.mp3")
        XCTAssertEqual(album.songs.first?.resolvedCoverURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(album.songs.first?.album?.title, "Echo Album")
    }

    func testLibraryEndpointsDecodeAuthenticatedCollections() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            switch request.url?.path {
            case "/api/v1/music/bookmarks/albums":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-album","album_id":"album-1","album":{"id":"album-1","title":"Liked Album"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/bookmarks/artists":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-artist","artist_id":"artist-1","artist":{"id":"artist-1","name":"Liked Artist"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists":
                return Self.response(request, body: """
                {"data":[{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1},{"id":"playlist-1","name":"My Mix","is_public":false,"is_favorite":false,"song_count":1}],"meta":{"page":1,"page_size":50,"total":2,"has_more":false}}
                """)
            case "/api/v1/music/playlists/favorite-1":
                return Self.response(request, body: """
                {"data":{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1}}
                """)
            case "/api/v1/music/playlists/favorite-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Liked Song","audio_url":"https://cdn.example.com/liked.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/history":
                return Self.response(request, body: """
                {"data":[{"id":"history-1","play_count":2,"last_played_at":"2026-07-18T10:00:00Z","song":{"id":"song-1","title":"Recent Song","audio_url":"https://cdn.example.com/recent.mp3"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let favorite = try await api.favoritePlaylist()
        let albums = try await api.favoriteAlbums()
        let artists = try await api.favoriteArtists()
        let playlists = try await api.playlists()
        let history = try await api.history()

        XCTAssertEqual(favorite?.songs.first?.title, "Liked Song")
        XCTAssertEqual(albums.first?.album?.title, "Liked Album")
        XCTAssertEqual(artists.first?.artist?.name, "Liked Artist")
        XCTAssertEqual(playlists.first(where: { !$0.isFavorite })?.name, "My Mix")
        XCTAssertEqual(history.first?.song?.title, "Recent Song")
    }

    func testPlaybackAndLibraryMutationsUseMusicV1Contracts() async throws {
        var requests: [URLRequest] = []
        let api = makeAPI(token: "token-1") { request in
            requests.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/music/plays"):
                return Self.response(request, body: "{\"data\":{\"recorded\":true}}")
            case ("POST", "/api/v1/music/playlists/favorite-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"favorite-entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/favorite-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/albums"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-album\",\"album_id\":\"album-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/albums/album-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-artist\",\"artist_id\":\"artist-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/artists/artist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/playlists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"playlist-1\",\"name\":\"My Mix\",\"is_public\":false,\"is_favorite\":false,\"song_count\":0}}")
            case ("POST", "/api/v1/music/playlists/playlist-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("PUT", "/api/v1/music/playlists/playlist-1/songs/order"):
                return Self.response(request, body: "{\"data\":{\"reordered\":true}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            default:
                throw URLError(.unsupportedURL)
            }
        }

        try await api.recordPlay(songID: "song-1")
        try await api.addSong(id: "song-1", toPlaylist: "favorite-1")
        try await api.removeSong(id: "song-1", fromPlaylist: "favorite-1")
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: true)
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: false)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: true)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: false)
        let playlist = try await api.createPlaylist(name: "My Mix")
        try await api.addSong(id: "song-1", toPlaylist: playlist.id)
        try await api.removeSong(id: "song-1", fromPlaylist: playlist.id)
        try await api.reorderPlaylist(id: playlist.id, songIDs: ["song-2", "song-1"])
        try await api.deletePlaylist(id: playlist.id)

        XCTAssertEqual(requests.count, 12)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token-1" })
        let bodies = try requests.compactMap { try Self.jsonBody(from: $0) }
        XCTAssertTrue(bodies.contains { $0["song_id"] as? String == "song-1" })
        XCTAssertTrue(bodies.contains { $0["name"] as? String == "My Mix" })
        XCTAssertTrue(bodies.contains { $0["song_ids"] as? [String] == ["song-2", "song-1"] })
    }

    func testArtistAndPlaylistDetailsDecodeForGuest() async throws {
        let api = makeAPI { request in
            switch request.url?.path {
            case "/api/v1/music/artists/artist-1":
                return Self.response(request, body: """
                {"data":{"id":"artist-1","name":"Echo Artist","image_url":"https://external.example.com/artist.jpg","albums":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg"}]}}
                """)
            case "/api/v1/music/playlists/playlist-1":
                return Self.response(request, body: """
                {"data":{"id":"playlist-1","name":"Public Mix","is_public":true,"is_favorite":false,"song_count":1}}
                """)
            case "/api/v1/music/playlists/playlist-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Echo Song","audio_url":"https://cdn.example.com/echo.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let artist = try await api.artist(id: "artist-1")
        let playlist = try await api.playlist(id: "playlist-1")

        XCTAssertEqual(artist.albums.first?.title, "Echo Album")
        XCTAssertEqual(artist.resolvedImageURL, "https://external.example.com/artist.jpg")
        XCTAssertEqual(artist.fallbackImageURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(playlist.songs.first?.title, "Echo Song")
    }

    func testUpdatePlaylistSendsEditableMetadata() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/music/playlists/playlist-1")
            let body = try Self.jsonBody(from: request)
            XCTAssertEqual(body?["name"] as? String, "Evening Mix")
            XCTAssertEqual(body?["description"] as? String, "Quiet songs")
            XCTAssertEqual(body?["is_public"] as? Bool, true)
            return Self.response(request, body: """
            {"data":{"id":"playlist-1","name":"Evening Mix","description":"Quiet songs","is_public":true,"is_favorite":false,"song_count":3}}
            """)
        }

        let playlist = try await api.updatePlaylist(
            id: "playlist-1",
            name: "Evening Mix",
            description: "Quiet songs",
            isPublic: true
        )

        XCTAssertEqual(playlist.name, "Evening Mix")
        XCTAssertTrue(playlist.isPublic)
    }

    func testSearchPaginationUsesServerHasMoreAndNextPage() async throws {
        let api = makeAPI { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "page" })?.value
            XCTAssertEqual(page, "2")
            return Self.response(request, body: """
            {"data":{"songs":[{"id":"song-2","title":"Second Page"}],"albums":[],"artists":[],"playlists":[],"meta":{"page":2,"page_size":20,"totals":{"song":21,"album":0,"artist":0,"playlist":0},"has_more":{"song":false,"album":false,"artist":false,"playlist":false}}}}
            """)
        }
        let page = try await api.searchPage(query: "echo", page: 2)
        XCTAssertEqual(page.results.songs.first?.title, "Second Page")
        XCTAssertFalse(page.hasMore)
    }

    func testLibraryPaginatesUntilHasMoreIsFalse() async throws {
        var pages: [String] = []
        let api = makeAPI { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "page" })?.value ?? ""
            pages.append(page)
            return Self.response(request, body: """
            {"data":[{"id":"playlist-\(page)","name":"List \(page)","is_public":false,"is_favorite":false,"song_count":0}],"meta":{"page":\(page),"page_size":50,"total":2,"has_more":\(page == "1" ? "true" : "false")}}
            """)
        }
        let playlists = try await api.playlists()
        XCTAssertEqual(pages, ["1", "2"])
        XCTAssertEqual(playlists.map(\.name), ["List 1", "List 2"])
    }

    func testPlaybackSessionLoadsSavedQueueWithoutMutation() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.url?.path, "/api/v1/music/playback-session")
            XCTAssertEqual(request.httpMethod, "GET")
            return Self.response(request, body: """
            {"data":{"queue":[{"id":"song-1","title":"From Desktop","audio_url":"https://cdn.example.com/song.mp3"}],"current_song_id":"song-1","position_seconds":47.25,"playback_mode":"single","updated_at":"2026-10-27T10:00:00Z"}}
            """)
        }
        let response = try await api.playbackSession()
        let state = try XCTUnwrap(response)
        XCTAssertEqual(state.currentSongID, "song-1")
        XCTAssertEqual(state.currentTime, 47.25)
        XCTAssertEqual(state.playbackMode, .repeatOne)
    }

    func testPlaybackSessionWritesValidCatalogQueueAndProgress() async throws {
        var requests: [URLRequest] = []
        let api = makeAPI(token: "token-1") { request in
            requests.append(request)
            return Self.response(request, body: "{\"data\":{}}")
        }
        let state = MusicPlaybackSnapshot(
            songs: [try XCTUnwrap(JSONDecoder().decode([MusicSong].self, from: Data("""
            [{"id":"11111111-1111-4111-8111-111111111111","title":"QA","audio_url":"https://cdn.example.com/qa.mp3"}]
            """.utf8)).first)],
            currentSongID: "11111111-1111-4111-8111-111111111111", currentTime: 12.5,
            playbackMode: .repeatAll
        )
        try await api.savePlaybackSnapshot(state)
        XCTAssertEqual(requests.map { $0.url!.path }, ["/api/v1/music/playback-session", "/api/v1/music/playback-progress"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "PUT" })
        XCTAssertEqual(requests.count, 2)
    }

    func testDiscoverUsesCurrentCatalogEndpointsForGuest() async throws {
        var requestedPaths: [String] = []
        let api = makeAPI { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            requestedPaths.append(request.url?.path ?? "")
            switch request.url?.path {
            case "/api/v1/music/albums":
                return Self.response(request, body: """
                {"data":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}]}],"meta":{"page":1,"page_size":20,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists/public":
                return Self.response(request, body: """
                {"data":[{"id":"playlist-1","name":"Echo Mix","cover_url":"https://cdn.example.com/mix.jpg","is_public":true,"is_favorite":false,"song_count":3}],"meta":{"page":1,"page_size":8,"total":1,"has_more":false}}
                """)
            default:
                XCTFail("Unexpected music home request: \(request.url?.absoluteString ?? "")")
                throw URLError(.unsupportedURL)
            }
        }

        let items = try await api.discover()
        XCTAssertEqual(requestedPaths, ["/api/v1/music/albums", "/api/v1/music/playlists/public"])
        XCTAssertEqual(items.first?.type, .album)
        XCTAssertEqual(items.first?.title, "Echo Album")
        XCTAssertEqual(items.first?.displaySubtitle, "Echo Artist")
        XCTAssertEqual(items.last?.displaySubtitle, "歌单 · 3 首")
    }

    func testDiscoverKeepsAlbumsWhenPublicPlaylistsFail() async throws {
        let api = makeAPI { request in
            if request.url?.path == "/api/v1/music/albums" {
                return Self.response(request, body: """
                {"data":[{"id":"album-1","title":"Keep Playing"}],"meta":{"page":1,"page_size":20,"total":1,"has_more":false}}
                """)
            }
            return Self.response(request, statusCode: 503, body: "{}")
        }
        let items = try await api.discover()
        XCTAssertEqual(items.map(\.title), ["Keep Playing"])
    }

    func testAlbumDecodesPlayableSongs() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/music/albums/album-1")
            return Self.response(request, body: """
            {"data":{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}],"songs":[{"id":"song-1","title":"Echo Song","track_number":1,"audio_url":"https://cdn.example.com/echo.mp3"}]}}
            """)
        }

        let album = try await api.album(id: "album-1")

        XCTAssertEqual(album.songs.first?.title, "Echo Song")
        XCTAssertEqual(album.songs.first?.audioURL, "https://cdn.example.com/echo.mp3")
        XCTAssertEqual(album.songs.first?.resolvedCoverURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(album.songs.first?.album?.title, "Echo Album")
    }

    func testLibraryEndpointsDecodeAuthenticatedCollections() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            switch request.url?.path {
            case "/api/v1/music/bookmarks/albums":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-album","album_id":"album-1","album":{"id":"album-1","title":"Liked Album"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/bookmarks/artists":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-artist","artist_id":"artist-1","artist":{"id":"artist-1","name":"Liked Artist"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists":
                return Self.response(request, body: """
                {"data":[{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1},{"id":"playlist-1","name":"My Mix","is_public":false,"is_favorite":false,"song_count":1}],"meta":{"page":1,"page_size":50,"total":2,"has_more":false}}
                """)
            case "/api/v1/music/playlists/favorite-1":
                return Self.response(request, body: """
                {"data":{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1}}
                """)
            case "/api/v1/music/playlists/favorite-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Liked Song","audio_url":"https://cdn.example.com/liked.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/history":
                return Self.response(request, body: """
                {"data":[{"id":"history-1","play_count":2,"last_played_at":"2026-07-18T10:00:00Z","song":{"id":"song-1","title":"Recent Song","audio_url":"https://cdn.example.com/recent.mp3"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let favorite = try await api.favoritePlaylist()
        let albums = try await api.favoriteAlbums()
        let artists = try await api.favoriteArtists()
        let playlists = try await api.playlists()
        let history = try await api.history()

        XCTAssertEqual(favorite?.songs.first?.title, "Liked Song")
        XCTAssertEqual(albums.first?.album?.title, "Liked Album")
        XCTAssertEqual(artists.first?.artist?.name, "Liked Artist")
        XCTAssertEqual(playlists.first(where: { !$0.isFavorite })?.name, "My Mix")
        XCTAssertEqual(history.first?.song?.title, "Recent Song")
    }

    func testPlaybackAndLibraryMutationsUseMusicV1Contracts() async throws {
        var requests: [URLRequest] = []
        let api = makeAPI(token: "token-1") { request in
            requests.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/music/plays"):
                return Self.response(request, body: "{\"data\":{\"recorded\":true}}")
            case ("POST", "/api/v1/music/playlists/favorite-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"favorite-entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/favorite-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/albums"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-album\",\"album_id\":\"album-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/albums/album-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-artist\",\"artist_id\":\"artist-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/artists/artist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/playlists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"playlist-1\",\"name\":\"My Mix\",\"is_public\":false,\"is_favorite\":false,\"song_count\":0}}")
            case ("POST", "/api/v1/music/playlists/playlist-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("PUT", "/api/v1/music/playlists/playlist-1/songs/order"):
                return Self.response(request, body: "{\"data\":{\"reordered\":true}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            default:
                throw URLError(.unsupportedURL)
            }
        }

        try await api.recordPlay(songID: "song-1")
        try await api.addSong(id: "song-1", toPlaylist: "favorite-1")
        try await api.removeSong(id: "song-1", fromPlaylist: "favorite-1")
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: true)
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: false)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: true)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: false)
        let playlist = try await api.createPlaylist(name: "My Mix")
        try await api.addSong(id: "song-1", toPlaylist: playlist.id)
        try await api.removeSong(id: "song-1", fromPlaylist: playlist.id)
        try await api.reorderPlaylist(id: playlist.id, songIDs: ["song-2", "song-1"])
        try await api.deletePlaylist(id: playlist.id)

        XCTAssertEqual(requests.count, 12)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token-1" })
        let bodies = try requests.compactMap { try Self.jsonBody(from: $0) }
        XCTAssertTrue(bodies.contains { $0["song_id"] as? String == "song-1" })
        XCTAssertTrue(bodies.contains { $0["name"] as? String == "My Mix" })
        XCTAssertTrue(bodies.contains { $0["song_ids"] as? [String] == ["song-2", "song-1"] })
    }

    func testArtistAndPlaylistDetailsDecodeForGuest() async throws {
        let api = makeAPI { request in
            switch request.url?.path {
            case "/api/v1/music/artists/artist-1":
                return Self.response(request, body: """
                {"data":{"id":"artist-1","name":"Echo Artist","image_url":"https://external.example.com/artist.jpg","albums":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg"}]}}
                """)
            case "/api/v1/music/playlists/playlist-1":
                return Self.response(request, body: """
                {"data":{"id":"playlist-1","name":"Public Mix","is_public":true,"is_favorite":false,"song_count":1}}
                """)
            case "/api/v1/music/playlists/playlist-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Echo Song","audio_url":"https://cdn.example.com/echo.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let artist = try await api.artist(id: "artist-1")
        let playlist = try await api.playlist(id: "playlist-1")

        XCTAssertEqual(artist.albums.first?.title, "Echo Album")
        XCTAssertEqual(artist.resolvedImageURL, "https://external.example.com/artist.jpg")
        XCTAssertEqual(artist.fallbackImageURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(playlist.songs.first?.title, "Echo Song")
    }

    func testUpdatePlaylistSendsEditableMetadata() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/music/playlists/playlist-1")
            let body = try Self.jsonBody(from: request)
            XCTAssertEqual(body?["name"] as? String, "Evening Mix")
            XCTAssertEqual(body?["description"] as? String, "Quiet songs")
            XCTAssertEqual(body?["is_public"] as? Bool, true)
            return Self.response(request, body: """
            {"data":{"id":"playlist-1","name":"Evening Mix","description":"Quiet songs","is_public":true,"is_favorite":false,"song_count":3}}
            """)
        }

        let playlist = try await api.updatePlaylist(
            id: "playlist-1",
            name: "Evening Mix",
            description: "Quiet songs",
            isPublic: true
        )

        XCTAssertEqual(playlist.name, "Evening Mix")
        XCTAssertTrue(playlist.isPublic)
    }

    func testLibraryPaginatesUntilHasMoreIsFalse() async throws {
        var pages: [String] = []
        let api = makeAPI { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "page" })?.value ?? ""
            pages.append(page)
            return Self.response(request, body: """
            {"data":[{"id":"playlist-\(page)","name":"List \(page)","is_public":false,"is_favorite":false,"song_count":0}],"meta":{"page":\(page),"page_size":50,"total":2,"has_more":\(page == "1" ? "true" : "false")}}
            """)
        }
        let playlists = try await api.playlists()
        XCTAssertEqual(pages, ["1", "2"])
        XCTAssertEqual(playlists.map(\.name), ["List 1", "List 2"])
    }

    func testPlaybackSessionLoadsSavedQueueWithoutMutation() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.url?.path, "/api/v1/music/playback-session")
            XCTAssertEqual(request.httpMethod, "GET")
            return Self.response(request, body: """
            {"data":{"queue":[{"id":"song-1","title":"From Desktop","audio_url":"https://cdn.example.com/song.mp3"}],"current_song_id":"song-1","position_seconds":47.25,"playback_mode":"single","updated_at":"2026-10-27T10:00:00Z"}}
            """)
        }
        let response = try await api.playbackSession()
        let state = try XCTUnwrap(response)
        XCTAssertEqual(state.currentSongID, "song-1")
        XCTAssertEqual(state.currentTime, 47.25)
        XCTAssertEqual(state.playbackMode, .repeatOne)
    }

    func testPlaybackSessionWritesValidCatalogQueueAndProgress() async throws {
        var requests: [URLRequest] = []
        let api = makeAPI(token: "token-1") { request in
            requests.append(request)
            return Self.response(request, body: "{\"data\":{}}")
        }
        let state = MusicPlaybackSnapshot(
            songs: [try XCTUnwrap(JSONDecoder().decode([MusicSong].self, from: Data("""
            [{"id":"11111111-1111-4111-8111-111111111111","title":"QA","audio_url":"https://cdn.example.com/qa.mp3"}]
            """.utf8)).first)],
            currentSongID: "11111111-1111-4111-8111-111111111111", currentTime: 12.5,
            playbackMode: .repeatAll
        )
        try await api.savePlaybackSnapshot(state)
        XCTAssertEqual(requests.map { $0.url!.path }, ["/api/v1/music/playback-session", "/api/v1/music/playback-progress"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "PUT" })
        XCTAssertEqual(requests.count, 2)
    }

    func testDiscoverUsesCurrentCatalogEndpointsForGuest() async throws {
        var requestedPaths: [String] = []
        let api = makeAPI { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            requestedPaths.append(request.url?.path ?? "")
            switch request.url?.path {
            case "/api/v1/music/albums":
                return Self.response(request, body: """
                {"data":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}]}],"meta":{"page":1,"page_size":20,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists/public":
                return Self.response(request, body: """
                {"data":[{"id":"playlist-1","name":"Echo Mix","cover_url":"https://cdn.example.com/mix.jpg","is_public":true,"is_favorite":false,"song_count":3}],"meta":{"page":1,"page_size":8,"total":1,"has_more":false}}
                """)
            default:
                XCTFail("Unexpected music home request: \(request.url?.absoluteString ?? "")")
                throw URLError(.unsupportedURL)
            }
        }

        let items = try await api.discover()
        XCTAssertEqual(requestedPaths, ["/api/v1/music/albums", "/api/v1/music/playlists/public"])
        XCTAssertEqual(items.first?.type, .album)
        XCTAssertEqual(items.first?.title, "Echo Album")
        XCTAssertEqual(items.first?.displaySubtitle, "Echo Artist")
        XCTAssertEqual(items.last?.displaySubtitle, "歌单 · 3 首")
    }

    func testDiscoverKeepsAlbumsWhenPublicPlaylistsFail() async throws {
        let api = makeAPI { request in
            if request.url?.path == "/api/v1/music/albums" {
                return Self.response(request, body: """
                {"data":[{"id":"album-1","title":"Keep Playing"}],"meta":{"page":1,"page_size":20,"total":1,"has_more":false}}
                """)
            }
            return Self.response(request, statusCode: 503, body: "{}")
        }
        let items = try await api.discover()
        XCTAssertEqual(items.map(\.title), ["Keep Playing"])
    }

    func testAlbumDecodesPlayableSongs() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/music/albums/album-1")
            return Self.response(request, body: """
            {"data":{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}],"songs":[{"id":"song-1","title":"Echo Song","track_number":1,"audio_url":"https://cdn.example.com/echo.mp3"}]}}
            """)
        }

        let album = try await api.album(id: "album-1")

        XCTAssertEqual(album.songs.first?.title, "Echo Song")
        XCTAssertEqual(album.songs.first?.audioURL, "https://cdn.example.com/echo.mp3")
        XCTAssertEqual(album.songs.first?.resolvedCoverURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(album.songs.first?.album?.title, "Echo Album")
    }

    func testLibraryEndpointsDecodeAuthenticatedCollections() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            switch request.url?.path {
            case "/api/v1/music/bookmarks/albums":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-album","album_id":"album-1","album":{"id":"album-1","title":"Liked Album"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/bookmarks/artists":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-artist","artist_id":"artist-1","artist":{"id":"artist-1","name":"Liked Artist"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists":
                return Self.response(request, body: """
                {"data":[{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1},{"id":"playlist-1","name":"My Mix","is_public":false,"is_favorite":false,"song_count":1}],"meta":{"page":1,"page_size":50,"total":2,"has_more":false}}
                """)
            case "/api/v1/music/playlists/favorite-1":
                return Self.response(request, body: """
                {"data":{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1}}
                """)
            case "/api/v1/music/playlists/favorite-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Liked Song","audio_url":"https://cdn.example.com/liked.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/history":
                return Self.response(request, body: """
                {"data":[{"id":"history-1","play_count":2,"last_played_at":"2026-07-18T10:00:00Z","song":{"id":"song-1","title":"Recent Song","audio_url":"https://cdn.example.com/recent.mp3"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let favorite = try await api.favoritePlaylist()
        let albums = try await api.favoriteAlbums()
        let artists = try await api.favoriteArtists()
        let playlists = try await api.playlists()
        let history = try await api.history()

        XCTAssertEqual(favorite?.songs.first?.title, "Liked Song")
        XCTAssertEqual(albums.first?.album?.title, "Liked Album")
        XCTAssertEqual(artists.first?.artist?.name, "Liked Artist")
        XCTAssertEqual(playlists.first(where: { !$0.isFavorite })?.name, "My Mix")
        XCTAssertEqual(history.first?.song?.title, "Recent Song")
    }

    func testPlaybackAndLibraryMutationsUseMusicV1Contracts() async throws {
        var requests: [URLRequest] = []
        let api = makeAPI(token: "token-1") { request in
            requests.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/music/plays"):
                return Self.response(request, body: "{\"data\":{\"recorded\":true}}")
            case ("POST", "/api/v1/music/playlists/favorite-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"favorite-entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/favorite-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/albums"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-album\",\"album_id\":\"album-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/albums/album-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-artist\",\"artist_id\":\"artist-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/artists/artist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/playlists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"playlist-1\",\"name\":\"My Mix\",\"is_public\":false,\"is_favorite\":false,\"song_count\":0}}")
            case ("POST", "/api/v1/music/playlists/playlist-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("PUT", "/api/v1/music/playlists/playlist-1/songs/order"):
                return Self.response(request, body: "{\"data\":{\"reordered\":true}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            default:
                throw URLError(.unsupportedURL)
            }
        }

        try await api.recordPlay(songID: "song-1")
        try await api.addSong(id: "song-1", toPlaylist: "favorite-1")
        try await api.removeSong(id: "song-1", fromPlaylist: "favorite-1")
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: true)
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: false)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: true)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: false)
        let playlist = try await api.createPlaylist(name: "My Mix")
        try await api.addSong(id: "song-1", toPlaylist: playlist.id)
        try await api.removeSong(id: "song-1", fromPlaylist: playlist.id)
        try await api.reorderPlaylist(id: playlist.id, songIDs: ["song-2", "song-1"])
        try await api.deletePlaylist(id: playlist.id)

        XCTAssertEqual(requests.count, 12)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token-1" })
        let bodies = try requests.compactMap { try Self.jsonBody(from: $0) }
        XCTAssertTrue(bodies.contains { $0["song_id"] as? String == "song-1" })
        XCTAssertTrue(bodies.contains { $0["name"] as? String == "My Mix" })
        XCTAssertTrue(bodies.contains { $0["song_ids"] as? [String] == ["song-2", "song-1"] })
    }

    func testArtistAndPlaylistDetailsDecodeForGuest() async throws {
        let api = makeAPI { request in
            switch request.url?.path {
            case "/api/v1/music/artists/artist-1":
                return Self.response(request, body: """
                {"data":{"id":"artist-1","name":"Echo Artist","image_url":"https://external.example.com/artist.jpg","albums":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg"}]}}
                """)
            case "/api/v1/music/playlists/playlist-1":
                return Self.response(request, body: """
                {"data":{"id":"playlist-1","name":"Public Mix","is_public":true,"is_favorite":false,"song_count":1}}
                """)
            case "/api/v1/music/playlists/playlist-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Echo Song","audio_url":"https://cdn.example.com/echo.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let artist = try await api.artist(id: "artist-1")
        let playlist = try await api.playlist(id: "playlist-1")

        XCTAssertEqual(artist.albums.first?.title, "Echo Album")
        XCTAssertEqual(artist.resolvedImageURL, "https://external.example.com/artist.jpg")
        XCTAssertEqual(artist.fallbackImageURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(playlist.songs.first?.title, "Echo Song")
    }

    func testUpdatePlaylistSendsEditableMetadata() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/music/playlists/playlist-1")
            let body = try Self.jsonBody(from: request)
            XCTAssertEqual(body?["name"] as? String, "Evening Mix")
            XCTAssertEqual(body?["description"] as? String, "Quiet songs")
            XCTAssertEqual(body?["is_public"] as? Bool, true)
            return Self.response(request, body: """
            {"data":{"id":"playlist-1","name":"Evening Mix","description":"Quiet songs","is_public":true,"is_favorite":false,"song_count":3}}
            """)
        }

        let playlist = try await api.updatePlaylist(
            id: "playlist-1",
            name: "Evening Mix",
            description: "Quiet songs",
            isPublic: true
        )

        XCTAssertEqual(playlist.name, "Evening Mix")
        XCTAssertTrue(playlist.isPublic)
    }

    func testPlaybackSessionLoadsSavedQueueWithoutMutation() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.url?.path, "/api/v1/music/playback-session")
            XCTAssertEqual(request.httpMethod, "GET")
            return Self.response(request, body: """
            {"data":{"queue":[{"id":"song-1","title":"From Desktop","audio_url":"https://cdn.example.com/song.mp3"}],"current_song_id":"song-1","position_seconds":47.25,"playback_mode":"single","updated_at":"2026-10-27T10:00:00Z"}}
            """)
        }
        let response = try await api.playbackSession()
        let state = try XCTUnwrap(response)
        XCTAssertEqual(state.currentSongID, "song-1")
        XCTAssertEqual(state.currentTime, 47.25)
        XCTAssertEqual(state.playbackMode, .repeatOne)
    }

    func testPlaybackSessionWritesValidCatalogQueueAndProgress() async throws {
        var requests: [URLRequest] = []
        let api = makeAPI(token: "token-1") { request in
            requests.append(request)
            return Self.response(request, body: "{\"data\":{}}")
        }
        let state = MusicPlaybackSnapshot(
            songs: [try XCTUnwrap(JSONDecoder().decode([MusicSong].self, from: Data("""
            [{"id":"11111111-1111-4111-8111-111111111111","title":"QA","audio_url":"https://cdn.example.com/qa.mp3"}]
            """.utf8)).first)],
            currentSongID: "11111111-1111-4111-8111-111111111111", currentTime: 12.5,
            playbackMode: .repeatAll
        )
        try await api.savePlaybackSnapshot(state)
        XCTAssertEqual(requests.map { $0.url!.path }, ["/api/v1/music/playback-session", "/api/v1/music/playback-progress"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "PUT" })
        XCTAssertEqual(requests.count, 2)
    }

    func testDiscoverUsesCurrentCatalogEndpointsForGuest() async throws {
        var requestedPaths: [String] = []
        let api = makeAPI { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            requestedPaths.append(request.url?.path ?? "")
            switch request.url?.path {
            case "/api/v1/music/albums":
                return Self.response(request, body: """
                {"data":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}]}],"meta":{"page":1,"page_size":20,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists/public":
                return Self.response(request, body: """
                {"data":[{"id":"playlist-1","name":"Echo Mix","cover_url":"https://cdn.example.com/mix.jpg","is_public":true,"is_favorite":false,"song_count":3}],"meta":{"page":1,"page_size":8,"total":1,"has_more":false}}
                """)
            default:
                XCTFail("Unexpected music home request: \(request.url?.absoluteString ?? "")")
                throw URLError(.unsupportedURL)
            }
        }

        let items = try await api.discover()
        XCTAssertEqual(requestedPaths, ["/api/v1/music/albums", "/api/v1/music/playlists/public"])
        XCTAssertEqual(items.first?.type, .album)
        XCTAssertEqual(items.first?.title, "Echo Album")
        XCTAssertEqual(items.first?.displaySubtitle, "Echo Artist")
        XCTAssertEqual(items.last?.displaySubtitle, "歌单 · 3 首")
    }

    func testDiscoverKeepsAlbumsWhenPublicPlaylistsFail() async throws {
        let api = makeAPI { request in
            if request.url?.path == "/api/v1/music/albums" {
                return Self.response(request, body: """
                {"data":[{"id":"album-1","title":"Keep Playing"}],"meta":{"page":1,"page_size":20,"total":1,"has_more":false}}
                """)
            }
            return Self.response(request, statusCode: 503, body: "{}")
        }
        let items = try await api.discover()
        XCTAssertEqual(items.map(\.title), ["Keep Playing"])
    }

    func testAlbumDecodesPlayableSongs() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/music/albums/album-1")
            return Self.response(request, body: """
            {"data":{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}],"songs":[{"id":"song-1","title":"Echo Song","track_number":1,"audio_url":"https://cdn.example.com/echo.mp3"}]}}
            """)
        }

        let album = try await api.album(id: "album-1")

        XCTAssertEqual(album.songs.first?.title, "Echo Song")
        XCTAssertEqual(album.songs.first?.audioURL, "https://cdn.example.com/echo.mp3")
        XCTAssertEqual(album.songs.first?.resolvedCoverURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(album.songs.first?.album?.title, "Echo Album")
    }

    func testLibraryEndpointsDecodeAuthenticatedCollections() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            switch request.url?.path {
            case "/api/v1/music/bookmarks/albums":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-album","album_id":"album-1","album":{"id":"album-1","title":"Liked Album"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/bookmarks/artists":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-artist","artist_id":"artist-1","artist":{"id":"artist-1","name":"Liked Artist"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists":
                return Self.response(request, body: """
                {"data":[{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1},{"id":"playlist-1","name":"My Mix","is_public":false,"is_favorite":false,"song_count":1}],"meta":{"page":1,"page_size":50,"total":2,"has_more":false}}
                """)
            case "/api/v1/music/playlists/favorite-1":
                return Self.response(request, body: """
                {"data":{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1}}
                """)
            case "/api/v1/music/playlists/favorite-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Liked Song","audio_url":"https://cdn.example.com/liked.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/history":
                return Self.response(request, body: """
                {"data":[{"id":"history-1","play_count":2,"last_played_at":"2026-07-18T10:00:00Z","song":{"id":"song-1","title":"Recent Song","audio_url":"https://cdn.example.com/recent.mp3"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let favorite = try await api.favoritePlaylist()
        let albums = try await api.favoriteAlbums()
        let artists = try await api.favoriteArtists()
        let playlists = try await api.playlists()
        let history = try await api.history()

        XCTAssertEqual(favorite?.songs.first?.title, "Liked Song")
        XCTAssertEqual(albums.first?.album?.title, "Liked Album")
        XCTAssertEqual(artists.first?.artist?.name, "Liked Artist")
        XCTAssertEqual(playlists.first(where: { !$0.isFavorite })?.name, "My Mix")
        XCTAssertEqual(history.first?.song?.title, "Recent Song")
    }

    func testPlaybackAndLibraryMutationsUseMusicV1Contracts() async throws {
        var requests: [URLRequest] = []
        let api = makeAPI(token: "token-1") { request in
            requests.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/music/plays"):
                return Self.response(request, body: "{\"data\":{\"recorded\":true}}")
            case ("POST", "/api/v1/music/playlists/favorite-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"favorite-entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/favorite-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/albums"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-album\",\"album_id\":\"album-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/albums/album-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-artist\",\"artist_id\":\"artist-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/artists/artist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/playlists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"playlist-1\",\"name\":\"My Mix\",\"is_public\":false,\"is_favorite\":false,\"song_count\":0}}")
            case ("POST", "/api/v1/music/playlists/playlist-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("PUT", "/api/v1/music/playlists/playlist-1/songs/order"):
                return Self.response(request, body: "{\"data\":{\"reordered\":true}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            default:
                throw URLError(.unsupportedURL)
            }
        }

        try await api.recordPlay(songID: "song-1")
        try await api.addSong(id: "song-1", toPlaylist: "favorite-1")
        try await api.removeSong(id: "song-1", fromPlaylist: "favorite-1")
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: true)
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: false)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: true)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: false)
        let playlist = try await api.createPlaylist(name: "My Mix")
        try await api.addSong(id: "song-1", toPlaylist: playlist.id)
        try await api.removeSong(id: "song-1", fromPlaylist: playlist.id)
        try await api.reorderPlaylist(id: playlist.id, songIDs: ["song-2", "song-1"])
        try await api.deletePlaylist(id: playlist.id)

        XCTAssertEqual(requests.count, 12)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token-1" })
        let bodies = try requests.compactMap { try Self.jsonBody(from: $0) }
        XCTAssertTrue(bodies.contains { $0["song_id"] as? String == "song-1" })
        XCTAssertTrue(bodies.contains { $0["name"] as? String == "My Mix" })
        XCTAssertTrue(bodies.contains { $0["song_ids"] as? [String] == ["song-2", "song-1"] })
    }

    func testArtistAndPlaylistDetailsDecodeForGuest() async throws {
        let api = makeAPI { request in
            switch request.url?.path {
            case "/api/v1/music/artists/artist-1":
                return Self.response(request, body: """
                {"data":{"id":"artist-1","name":"Echo Artist","image_url":"https://external.example.com/artist.jpg","albums":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg"}]}}
                """)
            case "/api/v1/music/playlists/playlist-1":
                return Self.response(request, body: """
                {"data":{"id":"playlist-1","name":"Public Mix","is_public":true,"is_favorite":false,"song_count":1}}
                """)
            case "/api/v1/music/playlists/playlist-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Echo Song","audio_url":"https://cdn.example.com/echo.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let artist = try await api.artist(id: "artist-1")
        let playlist = try await api.playlist(id: "playlist-1")

        XCTAssertEqual(artist.albums.first?.title, "Echo Album")
        XCTAssertEqual(artist.resolvedImageURL, "https://external.example.com/artist.jpg")
        XCTAssertEqual(artist.fallbackImageURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(playlist.songs.first?.title, "Echo Song")
    }

    func testUpdatePlaylistSendsEditableMetadata() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/music/playlists/playlist-1")
            let body = try Self.jsonBody(from: request)
            XCTAssertEqual(body?["name"] as? String, "Evening Mix")
            XCTAssertEqual(body?["description"] as? String, "Quiet songs")
            XCTAssertEqual(body?["is_public"] as? Bool, true)
            return Self.response(request, body: """
            {"data":{"id":"playlist-1","name":"Evening Mix","description":"Quiet songs","is_public":true,"is_favorite":false,"song_count":3}}
            """)
        }

        let playlist = try await api.updatePlaylist(
            id: "playlist-1",
            name: "Evening Mix",
            description: "Quiet songs",
            isPublic: true
        )

        XCTAssertEqual(playlist.name, "Evening Mix")
        XCTAssertTrue(playlist.isPublic)
    }

    func testPlaybackSessionWritesValidCatalogQueueAndProgress() async throws {
        var requests: [URLRequest] = []
        let api = makeAPI(token: "token-1") { request in
            requests.append(request)
            return Self.response(request, body: "{\"data\":{}}")
        }
        let state = MusicPlaybackSnapshot(
            songs: [try XCTUnwrap(JSONDecoder().decode([MusicSong].self, from: Data("""
            [{"id":"11111111-1111-4111-8111-111111111111","title":"QA","audio_url":"https://cdn.example.com/qa.mp3"}]
            """.utf8)).first)],
            currentSongID: "11111111-1111-4111-8111-111111111111", currentTime: 12.5,
            playbackMode: .repeatAll
        )
        try await api.savePlaybackSnapshot(state)
        XCTAssertEqual(requests.map { $0.url!.path }, ["/api/v1/music/playback-session", "/api/v1/music/playback-progress"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "PUT" })
        XCTAssertEqual(requests.count, 2)
    }

    func testDiscoverUsesCurrentCatalogEndpointsForGuest() async throws {
        var requestedPaths: [String] = []
        let api = makeAPI { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            requestedPaths.append(request.url?.path ?? "")
            switch request.url?.path {
            case "/api/v1/music/albums":
                return Self.response(request, body: """
                {"data":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}]}],"meta":{"page":1,"page_size":20,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists/public":
                return Self.response(request, body: """
                {"data":[{"id":"playlist-1","name":"Echo Mix","cover_url":"https://cdn.example.com/mix.jpg","is_public":true,"is_favorite":false,"song_count":3}],"meta":{"page":1,"page_size":8,"total":1,"has_more":false}}
                """)
            default:
                XCTFail("Unexpected music home request: \(request.url?.absoluteString ?? "")")
                throw URLError(.unsupportedURL)
            }
        }

        let items = try await api.discover()
        XCTAssertEqual(requestedPaths, ["/api/v1/music/albums", "/api/v1/music/playlists/public"])
        XCTAssertEqual(items.first?.type, .album)
        XCTAssertEqual(items.first?.title, "Echo Album")
        XCTAssertEqual(items.first?.displaySubtitle, "Echo Artist")
        XCTAssertEqual(items.last?.displaySubtitle, "歌单 · 3 首")
    }

    func testDiscoverKeepsAlbumsWhenPublicPlaylistsFail() async throws {
        let api = makeAPI { request in
            if request.url?.path == "/api/v1/music/albums" {
                return Self.response(request, body: """
                {"data":[{"id":"album-1","title":"Keep Playing"}],"meta":{"page":1,"page_size":20,"total":1,"has_more":false}}
                """)
            }
            return Self.response(request, statusCode: 503, body: "{}")
        }
        let items = try await api.discover()
        XCTAssertEqual(items.map(\.title), ["Keep Playing"])
    }

    func testAlbumDecodesPlayableSongs() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/music/albums/album-1")
            return Self.response(request, body: """
            {"data":{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}],"songs":[{"id":"song-1","title":"Echo Song","track_number":1,"audio_url":"https://cdn.example.com/echo.mp3"}]}}
            """)
        }

        let album = try await api.album(id: "album-1")

        XCTAssertEqual(album.songs.first?.title, "Echo Song")
        XCTAssertEqual(album.songs.first?.audioURL, "https://cdn.example.com/echo.mp3")
        XCTAssertEqual(album.songs.first?.resolvedCoverURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(album.songs.first?.album?.title, "Echo Album")
    }

    func testLibraryEndpointsDecodeAuthenticatedCollections() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            switch request.url?.path {
            case "/api/v1/music/bookmarks/albums":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-album","album_id":"album-1","album":{"id":"album-1","title":"Liked Album"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/bookmarks/artists":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-artist","artist_id":"artist-1","artist":{"id":"artist-1","name":"Liked Artist"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists":
                return Self.response(request, body: """
                {"data":[{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1},{"id":"playlist-1","name":"My Mix","is_public":false,"is_favorite":false,"song_count":1}],"meta":{"page":1,"page_size":50,"total":2,"has_more":false}}
                """)
            case "/api/v1/music/playlists/favorite-1":
                return Self.response(request, body: """
                {"data":{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1}}
                """)
            case "/api/v1/music/playlists/favorite-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Liked Song","audio_url":"https://cdn.example.com/liked.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/history":
                return Self.response(request, body: """
                {"data":[{"id":"history-1","play_count":2,"last_played_at":"2026-07-18T10:00:00Z","song":{"id":"song-1","title":"Recent Song","audio_url":"https://cdn.example.com/recent.mp3"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let favorite = try await api.favoritePlaylist()
        let albums = try await api.favoriteAlbums()
        let artists = try await api.favoriteArtists()
        let playlists = try await api.playlists()
        let history = try await api.history()

        XCTAssertEqual(favorite?.songs.first?.title, "Liked Song")
        XCTAssertEqual(albums.first?.album?.title, "Liked Album")
        XCTAssertEqual(artists.first?.artist?.name, "Liked Artist")
        XCTAssertEqual(playlists.first(where: { !$0.isFavorite })?.name, "My Mix")
        XCTAssertEqual(history.first?.song?.title, "Recent Song")
    }

    func testPlaybackAndLibraryMutationsUseMusicV1Contracts() async throws {
        var requests: [URLRequest] = []
        let api = makeAPI(token: "token-1") { request in
            requests.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/music/plays"):
                return Self.response(request, body: "{\"data\":{\"recorded\":true}}")
            case ("POST", "/api/v1/music/playlists/favorite-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"favorite-entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/favorite-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/albums"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-album\",\"album_id\":\"album-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/albums/album-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-artist\",\"artist_id\":\"artist-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/artists/artist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/playlists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"playlist-1\",\"name\":\"My Mix\",\"is_public\":false,\"is_favorite\":false,\"song_count\":0}}")
            case ("POST", "/api/v1/music/playlists/playlist-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("PUT", "/api/v1/music/playlists/playlist-1/songs/order"):
                return Self.response(request, body: "{\"data\":{\"reordered\":true}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            default:
                throw URLError(.unsupportedURL)
            }
        }

        try await api.recordPlay(songID: "song-1")
        try await api.addSong(id: "song-1", toPlaylist: "favorite-1")
        try await api.removeSong(id: "song-1", fromPlaylist: "favorite-1")
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: true)
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: false)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: true)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: false)
        let playlist = try await api.createPlaylist(name: "My Mix")
        try await api.addSong(id: "song-1", toPlaylist: playlist.id)
        try await api.removeSong(id: "song-1", fromPlaylist: playlist.id)
        try await api.reorderPlaylist(id: playlist.id, songIDs: ["song-2", "song-1"])
        try await api.deletePlaylist(id: playlist.id)

        XCTAssertEqual(requests.count, 12)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token-1" })
        let bodies = try requests.compactMap { try Self.jsonBody(from: $0) }
        XCTAssertTrue(bodies.contains { $0["song_id"] as? String == "song-1" })
        XCTAssertTrue(bodies.contains { $0["name"] as? String == "My Mix" })
        XCTAssertTrue(bodies.contains { $0["song_ids"] as? [String] == ["song-2", "song-1"] })
    }

    func testArtistAndPlaylistDetailsDecodeForGuest() async throws {
        let api = makeAPI { request in
            switch request.url?.path {
            case "/api/v1/music/artists/artist-1":
                return Self.response(request, body: """
                {"data":{"id":"artist-1","name":"Echo Artist","image_url":"https://external.example.com/artist.jpg","albums":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg"}]}}
                """)
            case "/api/v1/music/playlists/playlist-1":
                return Self.response(request, body: """
                {"data":{"id":"playlist-1","name":"Public Mix","is_public":true,"is_favorite":false,"song_count":1}}
                """)
            case "/api/v1/music/playlists/playlist-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Echo Song","audio_url":"https://cdn.example.com/echo.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let artist = try await api.artist(id: "artist-1")
        let playlist = try await api.playlist(id: "playlist-1")

        XCTAssertEqual(artist.albums.first?.title, "Echo Album")
        XCTAssertEqual(artist.resolvedImageURL, "https://external.example.com/artist.jpg")
        XCTAssertEqual(artist.fallbackImageURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(playlist.songs.first?.title, "Echo Song")
    }

    func testUpdatePlaylistSendsEditableMetadata() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/music/playlists/playlist-1")
            let body = try Self.jsonBody(from: request)
            XCTAssertEqual(body?["name"] as? String, "Evening Mix")
            XCTAssertEqual(body?["description"] as? String, "Quiet songs")
            XCTAssertEqual(body?["is_public"] as? Bool, true)
            return Self.response(request, body: """
            {"data":{"id":"playlist-1","name":"Evening Mix","description":"Quiet songs","is_public":true,"is_favorite":false,"song_count":3}}
            """)
        }

        let playlist = try await api.updatePlaylist(
            id: "playlist-1",
            name: "Evening Mix",
            description: "Quiet songs",
            isPublic: true
        )

        XCTAssertEqual(playlist.name, "Evening Mix")
        XCTAssertTrue(playlist.isPublic)
    }

    func testDiscoverUsesCurrentCatalogEndpointsForGuest() async throws {
        var requestedPaths: [String] = []
        let api = makeAPI { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            requestedPaths.append(request.url?.path ?? "")
            switch request.url?.path {
            case "/api/v1/music/albums":
                return Self.response(request, body: """
                {"data":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}]}],"meta":{"page":1,"page_size":20,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists/public":
                return Self.response(request, body: """
                {"data":[{"id":"playlist-1","name":"Echo Mix","cover_url":"https://cdn.example.com/mix.jpg","is_public":true,"is_favorite":false,"song_count":3}],"meta":{"page":1,"page_size":8,"total":1,"has_more":false}}
                """)
            default:
                XCTFail("Unexpected music home request: \(request.url?.absoluteString ?? "")")
                throw URLError(.unsupportedURL)
            }
        }

        let items = try await api.discover()
        XCTAssertEqual(requestedPaths, ["/api/v1/music/albums", "/api/v1/music/playlists/public"])
        XCTAssertEqual(items.first?.type, .album)
        XCTAssertEqual(items.first?.title, "Echo Album")
        XCTAssertEqual(items.first?.displaySubtitle, "Echo Artist")
        XCTAssertEqual(items.last?.displaySubtitle, "歌单 · 3 首")
    }

    func testDiscoverKeepsAlbumsWhenPublicPlaylistsFail() async throws {
        let api = makeAPI { request in
            if request.url?.path == "/api/v1/music/albums" {
                return Self.response(request, body: """
                {"data":[{"id":"album-1","title":"Keep Playing"}],"meta":{"page":1,"page_size":20,"total":1,"has_more":false}}
                """)
            }
            return Self.response(request, statusCode: 503, body: "{}")
        }
        let items = try await api.discover()
        XCTAssertEqual(items.map(\.title), ["Keep Playing"])
    }

    func testAlbumDecodesPlayableSongs() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/music/albums/album-1")
            return Self.response(request, body: """
            {"data":{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}],"songs":[{"id":"song-1","title":"Echo Song","track_number":1,"audio_url":"https://cdn.example.com/echo.mp3"}]}}
            """)
        }

        let album = try await api.album(id: "album-1")

        XCTAssertEqual(album.songs.first?.title, "Echo Song")
        XCTAssertEqual(album.songs.first?.audioURL, "https://cdn.example.com/echo.mp3")
        XCTAssertEqual(album.songs.first?.resolvedCoverURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(album.songs.first?.album?.title, "Echo Album")
    }

    func testLibraryEndpointsDecodeAuthenticatedCollections() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            switch request.url?.path {
            case "/api/v1/music/bookmarks/albums":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-album","album_id":"album-1","album":{"id":"album-1","title":"Liked Album"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/bookmarks/artists":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-artist","artist_id":"artist-1","artist":{"id":"artist-1","name":"Liked Artist"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists":
                return Self.response(request, body: """
                {"data":[{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1},{"id":"playlist-1","name":"My Mix","is_public":false,"is_favorite":false,"song_count":1}],"meta":{"page":1,"page_size":50,"total":2,"has_more":false}}
                """)
            case "/api/v1/music/playlists/favorite-1":
                return Self.response(request, body: """
                {"data":{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1}}
                """)
            case "/api/v1/music/playlists/favorite-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Liked Song","audio_url":"https://cdn.example.com/liked.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/history":
                return Self.response(request, body: """
                {"data":[{"id":"history-1","play_count":2,"last_played_at":"2026-07-18T10:00:00Z","song":{"id":"song-1","title":"Recent Song","audio_url":"https://cdn.example.com/recent.mp3"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let favorite = try await api.favoritePlaylist()
        let albums = try await api.favoriteAlbums()
        let artists = try await api.favoriteArtists()
        let playlists = try await api.playlists()
        let history = try await api.history()

        XCTAssertEqual(favorite?.songs.first?.title, "Liked Song")
        XCTAssertEqual(albums.first?.album?.title, "Liked Album")
        XCTAssertEqual(artists.first?.artist?.name, "Liked Artist")
        XCTAssertEqual(playlists.first(where: { !$0.isFavorite })?.name, "My Mix")
        XCTAssertEqual(history.first?.song?.title, "Recent Song")
    }

    func testPlaybackAndLibraryMutationsUseMusicV1Contracts() async throws {
        var requests: [URLRequest] = []
        let api = makeAPI(token: "token-1") { request in
            requests.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/music/plays"):
                return Self.response(request, body: "{\"data\":{\"recorded\":true}}")
            case ("POST", "/api/v1/music/playlists/favorite-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"favorite-entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/favorite-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/albums"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-album\",\"album_id\":\"album-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/albums/album-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-artist\",\"artist_id\":\"artist-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/artists/artist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/playlists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"playlist-1\",\"name\":\"My Mix\",\"is_public\":false,\"is_favorite\":false,\"song_count\":0}}")
            case ("POST", "/api/v1/music/playlists/playlist-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("PUT", "/api/v1/music/playlists/playlist-1/songs/order"):
                return Self.response(request, body: "{\"data\":{\"reordered\":true}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            default:
                throw URLError(.unsupportedURL)
            }
        }

        try await api.recordPlay(songID: "song-1")
        try await api.addSong(id: "song-1", toPlaylist: "favorite-1")
        try await api.removeSong(id: "song-1", fromPlaylist: "favorite-1")
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: true)
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: false)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: true)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: false)
        let playlist = try await api.createPlaylist(name: "My Mix")
        try await api.addSong(id: "song-1", toPlaylist: playlist.id)
        try await api.removeSong(id: "song-1", fromPlaylist: playlist.id)
        try await api.reorderPlaylist(id: playlist.id, songIDs: ["song-2", "song-1"])
        try await api.deletePlaylist(id: playlist.id)

        XCTAssertEqual(requests.count, 12)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token-1" })
        let bodies = try requests.compactMap { try Self.jsonBody(from: $0) }
        XCTAssertTrue(bodies.contains { $0["song_id"] as? String == "song-1" })
        XCTAssertTrue(bodies.contains { $0["name"] as? String == "My Mix" })
        XCTAssertTrue(bodies.contains { $0["song_ids"] as? [String] == ["song-2", "song-1"] })
    }

    func testArtistAndPlaylistDetailsDecodeForGuest() async throws {
        let api = makeAPI { request in
            switch request.url?.path {
            case "/api/v1/music/artists/artist-1":
                return Self.response(request, body: """
                {"data":{"id":"artist-1","name":"Echo Artist","image_url":"https://external.example.com/artist.jpg","albums":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg"}]}}
                """)
            case "/api/v1/music/playlists/playlist-1":
                return Self.response(request, body: """
                {"data":{"id":"playlist-1","name":"Public Mix","is_public":true,"is_favorite":false,"song_count":1}}
                """)
            case "/api/v1/music/playlists/playlist-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Echo Song","audio_url":"https://cdn.example.com/echo.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let artist = try await api.artist(id: "artist-1")
        let playlist = try await api.playlist(id: "playlist-1")

        XCTAssertEqual(artist.albums.first?.title, "Echo Album")
        XCTAssertEqual(artist.resolvedImageURL, "https://external.example.com/artist.jpg")
        XCTAssertEqual(artist.fallbackImageURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(playlist.songs.first?.title, "Echo Song")
    }

    func testUpdatePlaylistSendsEditableMetadata() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/music/playlists/playlist-1")
            let body = try Self.jsonBody(from: request)
            XCTAssertEqual(body?["name"] as? String, "Evening Mix")
            XCTAssertEqual(body?["description"] as? String, "Quiet songs")
            XCTAssertEqual(body?["is_public"] as? Bool, true)
            return Self.response(request, body: """
            {"data":{"id":"playlist-1","name":"Evening Mix","description":"Quiet songs","is_public":true,"is_favorite":false,"song_count":3}}
            """)
        }

        let playlist = try await api.updatePlaylist(
            id: "playlist-1",
            name: "Evening Mix",
            description: "Quiet songs",
            isPublic: true
        )

        XCTAssertEqual(playlist.name, "Evening Mix")
        XCTAssertTrue(playlist.isPublic)
    }

    func testDiscoverKeepsAlbumsWhenPublicPlaylistsFail() async throws {
        let api = makeAPI { request in
            if request.url?.path == "/api/v1/music/albums" {
                return Self.response(request, body: """
                {"data":[{"id":"album-1","title":"Keep Playing"}],"meta":{"page":1,"page_size":20,"total":1,"has_more":false}}
                """)
            }
            return Self.response(request, statusCode: 503, body: "{}")
        }
        let items = try await api.discover()
        XCTAssertEqual(items.map(\.title), ["Keep Playing"])
    }

    func testAlbumDecodesPlayableSongs() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/music/albums/album-1")
            return Self.response(request, body: """
            {"data":{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg","artists":[{"id":"artist-1","name":"Echo Artist"}],"songs":[{"id":"song-1","title":"Echo Song","track_number":1,"audio_url":"https://cdn.example.com/echo.mp3"}]}}
            """)
        }

        let album = try await api.album(id: "album-1")

        XCTAssertEqual(album.songs.first?.title, "Echo Song")
        XCTAssertEqual(album.songs.first?.audioURL, "https://cdn.example.com/echo.mp3")
        XCTAssertEqual(album.songs.first?.resolvedCoverURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(album.songs.first?.album?.title, "Echo Album")
    }

    func testLibraryEndpointsDecodeAuthenticatedCollections() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            switch request.url?.path {
            case "/api/v1/music/bookmarks/albums":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-album","album_id":"album-1","album":{"id":"album-1","title":"Liked Album"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/bookmarks/artists":
                return Self.response(request, body: """
                {"data":[{"id":"bookmark-artist","artist_id":"artist-1","artist":{"id":"artist-1","name":"Liked Artist"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/playlists":
                return Self.response(request, body: """
                {"data":[{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1},{"id":"playlist-1","name":"My Mix","is_public":false,"is_favorite":false,"song_count":1}],"meta":{"page":1,"page_size":50,"total":2,"has_more":false}}
                """)
            case "/api/v1/music/playlists/favorite-1":
                return Self.response(request, body: """
                {"data":{"id":"favorite-1","name":"最爱","is_public":false,"is_favorite":true,"song_count":1}}
                """)
            case "/api/v1/music/playlists/favorite-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Liked Song","audio_url":"https://cdn.example.com/liked.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            case "/api/v1/music/history":
                return Self.response(request, body: """
                {"data":[{"id":"history-1","play_count":2,"last_played_at":"2026-07-18T10:00:00Z","song":{"id":"song-1","title":"Recent Song","audio_url":"https://cdn.example.com/recent.mp3"}}],"meta":{"page":1,"page_size":50,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let favorite = try await api.favoritePlaylist()
        let albums = try await api.favoriteAlbums()
        let artists = try await api.favoriteArtists()
        let playlists = try await api.playlists()
        let history = try await api.history()

        XCTAssertEqual(favorite?.songs.first?.title, "Liked Song")
        XCTAssertEqual(albums.first?.album?.title, "Liked Album")
        XCTAssertEqual(artists.first?.artist?.name, "Liked Artist")
        XCTAssertEqual(playlists.first(where: { !$0.isFavorite })?.name, "My Mix")
        XCTAssertEqual(history.first?.song?.title, "Recent Song")
    }

    func testPlaybackAndLibraryMutationsUseMusicV1Contracts() async throws {
        var requests: [URLRequest] = []
        let api = makeAPI(token: "token-1") { request in
            requests.append(request)
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/music/plays"):
                return Self.response(request, body: "{\"data\":{\"recorded\":true}}")
            case ("POST", "/api/v1/music/playlists/favorite-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"favorite-entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/favorite-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/albums"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-album\",\"album_id\":\"album-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/albums/album-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/bookmarks/artists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"bookmark-artist\",\"artist_id\":\"artist-1\"}}")
            case ("DELETE", "/api/v1/music/bookmarks/artists/artist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("POST", "/api/v1/music/playlists"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"playlist-1\",\"name\":\"My Mix\",\"is_public\":false,\"is_favorite\":false,\"song_count\":0}}")
            case ("POST", "/api/v1/music/playlists/playlist-1/songs"):
                return Self.response(request, statusCode: 201, body: "{\"data\":{\"id\":\"entry-1\"}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1/songs/song-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            case ("PUT", "/api/v1/music/playlists/playlist-1/songs/order"):
                return Self.response(request, body: "{\"data\":{\"reordered\":true}}")
            case ("DELETE", "/api/v1/music/playlists/playlist-1"):
                return Self.response(request, body: "{\"data\":{\"deleted\":true}}")
            default:
                throw URLError(.unsupportedURL)
            }
        }

        try await api.recordPlay(songID: "song-1")
        try await api.addSong(id: "song-1", toPlaylist: "favorite-1")
        try await api.removeSong(id: "song-1", fromPlaylist: "favorite-1")
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: true)
        try await api.setFavoriteAlbum(id: "album-1", isFavorite: false)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: true)
        try await api.setFavoriteArtist(id: "artist-1", isFavorite: false)
        let playlist = try await api.createPlaylist(name: "My Mix")
        try await api.addSong(id: "song-1", toPlaylist: playlist.id)
        try await api.removeSong(id: "song-1", fromPlaylist: playlist.id)
        try await api.reorderPlaylist(id: playlist.id, songIDs: ["song-2", "song-1"])
        try await api.deletePlaylist(id: playlist.id)

        XCTAssertEqual(requests.count, 12)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token-1" })
        let bodies = try requests.compactMap { try Self.jsonBody(from: $0) }
        XCTAssertTrue(bodies.contains { $0["song_id"] as? String == "song-1" })
        XCTAssertTrue(bodies.contains { $0["name"] as? String == "My Mix" })
        XCTAssertTrue(bodies.contains { $0["song_ids"] as? [String] == ["song-2", "song-1"] })
    }

    func testArtistAndPlaylistDetailsDecodeForGuest() async throws {
        let api = makeAPI { request in
            switch request.url?.path {
            case "/api/v1/music/artists/artist-1":
                return Self.response(request, body: """
                {"data":{"id":"artist-1","name":"Echo Artist","image_url":"https://external.example.com/artist.jpg","albums":[{"id":"album-1","title":"Echo Album","cover_url":"https://cdn.example.com/album.jpg"}]}}
                """)
            case "/api/v1/music/playlists/playlist-1":
                return Self.response(request, body: """
                {"data":{"id":"playlist-1","name":"Public Mix","is_public":true,"is_favorite":false,"song_count":1}}
                """)
            case "/api/v1/music/playlists/playlist-1/songs":
                return Self.response(request, body: """
                {"data":[{"id":"entry-1","position":1,"song":{"id":"song-1","title":"Echo Song","audio_url":"https://cdn.example.com/echo.mp3"}}],"meta":{"page":1,"page_size":100,"total":1,"has_more":false}}
                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let artist = try await api.artist(id: "artist-1")
        let playlist = try await api.playlist(id: "playlist-1")

        XCTAssertEqual(artist.albums.first?.title, "Echo Album")
        XCTAssertEqual(artist.resolvedImageURL, "https://external.example.com/artist.jpg")
        XCTAssertEqual(artist.fallbackImageURL, "https://cdn.example.com/album.jpg")
        XCTAssertEqual(playlist.songs.first?.title, "Echo Song")
    }

    func testUpdatePlaylistSendsEditableMetadata() async throws {
        let api = makeAPI(token: "token-1") { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/music/playlists/playlist-1")
            let body = try Self.jsonBody(from: request)
            XCTAssertEqual(body?["name"] as? String, "Evening Mix")
            XCTAssertEqual(body?["description"] as? String, "Quiet songs")
            XCTAssertEqual(body?["is_public"] as? Bool, true)
            return Self.response(request, body: """
            {"data":{"id":"playlist-1","name":"Evening Mix","description":"Quiet songs","is_public":true,"is_favorite":false,"song_count":3}}
            """)
        }

        let playlist = try await api.updatePlaylist(
            id: "playlist-1",
            name: "Evening Mix",
            description: "Quiet songs",
            isPublic: true
        )

        XCTAssertEqual(playlist.name, "Evening Mix")
        XCTAssertTrue(playlist.isPublic)
    }

    private func makeAPI(
        token: String? = nil,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> MusicAPI {
        URLProtocolStub.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        return MusicAPI(
            client: APIClient(baseURL: URL(string: "https://example.com/api/v1")!, session: session),
            authSession: AuthSessionStore(token: token)
        )
    }

    private static func response(
        _ request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    private static func jsonBody(from request: URLRequest) throws -> [String: Any]? {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var result = Data()
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                result.append(buffer, count: count)
            }
            data = result
        } else {
            return nil
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
