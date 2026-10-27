import AtomanCore
import Foundation

public struct MusicAPI {
    public let client: APIClient
    public let authSession: AuthSessionStore

    public init(client: APIClient, authSession: AuthSessionStore) {
        self.client = client
        self.authSession = authSession
    }

    public func search(query: String, pageSize: Int = 20) async throws -> MusicSearchResults {
        try await searchPage(query: query, page: 1, pageSize: pageSize).results
    }

    public func searchPage(query: String, page: Int, pageSize: Int = 20) async throws -> MusicSearchPage {
        let (data, response) = try await client.request(
            path: "music/search",
            token: authSession.token,
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: String(max(1, page))),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ]
        )
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        let payload = try JSONDecoder().decode(MusicEnvelope<MusicSearchPayload>.self, from: data).data
        let results = MusicSearchResults(songs: payload.songs, albums: payload.albums,
                                         artists: payload.artists, playlists: payload.playlists)
        return MusicSearchPage(results: results, hasMore: payload.meta?.hasMore.values.contains(true) ?? false)
    }

    // The legacy /music/discover route was removed. Compose the native home
    // from the current public catalog endpoints instead of depending on it.
    public func discover(pageSize: Int = 20) async throws -> [MusicDiscoverItem] {
        let (albumsData, albumsResponse) = try await client.request(
            path: "music/albums",
            token: authSession.token,
            queryItems: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ]
        )
        guard albumsResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let albums = try JSONDecoder().decode(MusicEnvelope<[MusicAlbum]>.self, from: albumsData).data
        var results = albums.map(MusicDiscoverItem.init(album:))

        // A transient public-playlist error must not blank a working album home.
        if let (playlistData, playlistResponse) = try? await client.request(
            path: "music/playlists/public",
            token: authSession.token,
            queryItems: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "page_size", value: String(min(pageSize, 8))),
            ]
        ), playlistResponse.statusCode == 200,
           let playlists = try? JSONDecoder().decode(MusicEnvelope<[MusicPlaylist]>.self, from: playlistData).data {
            results.append(contentsOf: playlists.map(MusicDiscoverItem.init(playlist:)))
        }
        return results
    }

    public func album(id: String) async throws -> MusicAlbum {
        let (data, response) = try await client.request(
            path: "music/albums/\(id)",
            token: authSession.token
        )
        guard response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MusicEnvelope<MusicAlbum>.self, from: data).data
    }

    public func artist(id: String) async throws -> MusicArtistDetail {
        let (data, response) = try await client.request(
            path: "music/artists/\(id)",
            token: authSession.token
        )
        guard response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MusicEnvelope<MusicArtistDetail>.self, from: data).data
    }

    public func playlist(id: String) async throws -> MusicPlaylistDetail {
        let (playlistData, playlistResponse) = try await client.request(
            path: "music/playlists/\(id)",
            token: authSession.token
        )
        guard playlistResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let playlist = try JSONDecoder().decode(MusicEnvelope<MusicPlaylist>.self, from: playlistData).data
        let entries: [MusicPlaylistEntry] = try await list(
            path: "music/playlists/\(id)/songs",
            pageSize: 100
        )
        return MusicPlaylistDetail(playlist: playlist, songs: entries.compactMap(\.song))
    }

    public func favoritePlaylist() async throws -> MusicPlaylistDetail? {
        let ownedPlaylists = try await playlists(pageSize: 100)
        guard let favorite = ownedPlaylists.first(where: \.isFavorite) else {
            return nil
        }
        return try await playlist(id: favorite.id)
    }

    public func favoriteAlbums(pageSize: Int = 50) async throws -> [MusicAlbumBookmark] {
        try await list(path: "music/bookmarks/albums", pageSize: pageSize)
    }

    public func favoriteArtists(pageSize: Int = 50) async throws -> [MusicArtistBookmark] {
        try await list(path: "music/bookmarks/artists", pageSize: pageSize)
    }

    public func playlists(pageSize: Int = 50) async throws -> [MusicPlaylist] {
        try await list(path: "music/playlists", pageSize: pageSize)
    }

    public func history(pageSize: Int = 50) async throws -> [MusicHistoryItem] {
        try await list(path: "music/history", pageSize: pageSize)
    }

    public func recordPlay(songID: String) async throws {
        let body = try JSONEncoder().encode(MusicSongIDRequest(songID: songID))
        try await send(path: "music/plays", method: "POST", body: body, expectedStatus: 200)
    }

    public func setFavoriteAlbum(id: String, isFavorite: Bool) async throws {
        if isFavorite {
            let body = try JSONEncoder().encode(MusicAlbumIDRequest(albumID: id))
            try await send(path: "music/bookmarks/albums", method: "POST", body: body, expectedStatus: 201)
        } else {
            try await send(path: "music/bookmarks/albums/\(id)", method: "DELETE", body: nil, expectedStatus: 200)
        }
    }

    public func setFavoriteArtist(id: String, isFavorite: Bool) async throws {
        if isFavorite {
            let body = try JSONEncoder().encode(MusicArtistIDRequest(artistID: id))
            try await send(path: "music/bookmarks/artists", method: "POST", body: body, expectedStatus: 201)
        } else {
            try await send(path: "music/bookmarks/artists/\(id)", method: "DELETE", body: nil, expectedStatus: 200)
        }
    }

    public func createPlaylist(name: String) async throws -> MusicPlaylist {
        let body = try JSONEncoder().encode(MusicCreatePlaylistRequest(name: name, isPublic: false))
        let (data, response) = try await client.request(
            path: "music/playlists",
            method: "POST",
            token: authSession.token,
            body: body
        )
        guard response.statusCode == 201 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MusicEnvelope<MusicPlaylist>.self, from: data).data
    }

    public func updatePlaylist(
        id: String,
        name: String,
        description: String,
        isPublic: Bool
    ) async throws -> MusicPlaylist {
        let body = try JSONEncoder().encode(MusicUpdatePlaylistRequest(
            name: name,
            description: description,
            isPublic: isPublic
        ))
        let (data, response) = try await client.request(
            path: "music/playlists/\(id)",
            method: "PATCH",
            token: authSession.token,
            body: body
        )
        guard response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MusicEnvelope<MusicPlaylist>.self, from: data).data
    }

    public func addSong(id: String, toPlaylist playlistID: String) async throws {
        let body = try JSONEncoder().encode(MusicSongIDRequest(songID: id))
        try await send(
            path: "music/playlists/\(playlistID)/songs",
            method: "POST",
            body: body,
            expectedStatus: 201
        )
    }

    public func removeSong(id: String, fromPlaylist playlistID: String) async throws {
        try await send(
            path: "music/playlists/\(playlistID)/songs/\(id)",
            method: "DELETE",
            body: nil,
            expectedStatus: 200
        )
    }

    public func reorderPlaylist(id: String, songIDs: [String]) async throws {
        let body = try JSONEncoder().encode(MusicSongIDsRequest(songIDs: songIDs))
        try await send(
            path: "music/playlists/\(id)/songs/order",
            method: "PUT",
            body: body,
            expectedStatus: 200
        )
    }

    public func deletePlaylist(id: String) async throws {
        try await send(
            path: "music/playlists/\(id)",
            method: "DELETE",
            body: nil,
            expectedStatus: 200
        )
    }

    private func list<Value: Decodable>(path: String, pageSize: Int) async throws -> [Value] {
        var all: [Value] = []
        var page = 1
        let size = max(1, min(pageSize, 100))
        while true {
            let (data, response) = try await client.request(
                path: path,
                token: authSession.token,
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page_size", value: String(size)),
                ]
            )
            guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
            let result = try JSONDecoder().decode(MusicListEnvelope<Value>.self, from: data)
            all.append(contentsOf: result.data)
            guard result.meta?.hasMore == true, !result.data.isEmpty else { break }
            page += 1
        }
        return all
    }

    private func send(
        path: String,
        method: String,
        body: Data?,
        expectedStatus: Int
    ) async throws {
        let (_, response) = try await client.request(
            path: path,
            method: method,
            token: authSession.token,
            body: body
        )
        guard response.statusCode == expectedStatus else {
            throw URLError(.badServerResponse)
        }
    }
}

private struct MusicEnvelope<Value: Decodable>: Decodable {
    let data: Value
}

private struct MusicSearchPayload: Decodable {
    let songs: [MusicSong]
    let albums: [MusicAlbum]
    let artists: [MusicArtist]
    let playlists: [MusicPlaylist]
    let meta: MusicSearchMeta?
}

private struct MusicSearchMeta: Decodable {
    let hasMore: [String: Bool]
    enum CodingKeys: String, CodingKey { case hasMore = "has_more" }
}

private struct MusicListEnvelope<Value: Decodable>: Decodable {
    let data: [Value]
    let meta: MusicListMeta?
}

private struct MusicListMeta: Decodable {
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case hasMore = "has_more" }
}

private struct MusicSongIDRequest: Encodable {
    let songID: String

    enum CodingKeys: String, CodingKey {
        case songID = "song_id"
    }
}

private struct MusicAlbumIDRequest: Encodable {
    let albumID: String

    enum CodingKeys: String, CodingKey {
        case albumID = "album_id"
    }
}

private struct MusicArtistIDRequest: Encodable {
    let artistID: String

    enum CodingKeys: String, CodingKey {
        case artistID = "artist_id"
    }
}

private struct MusicCreatePlaylistRequest: Encodable {
    let name: String
    let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case isPublic = "is_public"
    }
}

private struct MusicUpdatePlaylistRequest: Encodable {
    let name: String
    let description: String
    let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case name, description
        case isPublic = "is_public"
    }
}

private struct MusicSongIDsRequest: Encodable {
    let songIDs: [String]

    enum CodingKeys: String, CodingKey {
        case songIDs = "song_ids"
    }
}
