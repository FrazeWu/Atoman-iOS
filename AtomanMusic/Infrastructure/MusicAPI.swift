import AtomanCore
import Foundation

public struct MusicAPI {
    public let client: APIClient
    public let authSession: AuthSessionStore

    public init(client: APIClient, authSession: AuthSessionStore) {
        self.client = client
        self.authSession = authSession
    }

    public func search(query: String, page: Int = 1, pageSize: Int = 20) async throws -> MusicSearchResults {
        let (data, response) = try await client.request(
            path: "music/search",
            token: authSession.token,
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: String(max(1, page))),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ]
        )
        guard response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MusicEnvelope<MusicSearchResults>.self, from: data).data
    }

    public func searchPage(query: String, page: Int, pageSize: Int = 20) async throws -> MusicSearchPage {
        let response = try await search(query: query, page: page, pageSize: pageSize)
        return MusicSearchPage(results: response, hasMore: response.meta?.hasNextPage ?? false)
    }

    // Legacy API kept for existing SDK clients. The native home uses homeFeed.
    public func discover(pageSize: Int = 20) async throws -> [MusicDiscoverItem] {
        let albums: MusicPage<MusicAlbum> = try await listPage(
            path: "music/albums", page: 1, pageSize: pageSize
        )
        var items = albums.data.map(MusicDiscoverItem.init(album:))
        if let playlists: MusicPage<MusicPublicPlaylistCard> = try? await listPage(
            path: "music/playlists/public", page: 1, pageSize: min(pageSize, 8)
        ) {
            items.append(contentsOf: playlists.data.map {
                MusicDiscoverItem(
                    type: .playlist, id: $0.id, title: $0.name,
                    summary: $0.description, imageURL: $0.coverURL,
                    targetPath: "/music/playlist/\($0.id)", songCount: $0.songCount
                )
            })
        }
        return items
    }

    // The old /music/discover endpoint was removed. The new home feed uses the
    // public recommendation and playlist APIs plus personalized /music/home.
    public func homeFeed(pageSize: Int = 20) async throws -> MusicHomeFeed {
        let pageSize = min(max(pageSize, 1), 40)
        async let hotAlbums = recommendations(kind: .album, mode: "hot", limit: min(pageSize, 8))
        async let latestAlbums = recommendations(kind: .album, mode: "latest", limit: pageSize)
        async let hotArtists = recommendations(kind: .artist, mode: "hot", limit: min(pageSize, 6))
        async let publicPlaylists: MusicPage<MusicPublicPlaylistCard> = listPage(
            path: "music/playlists/public", page: 1, pageSize: min(pageSize, 6)
        )
        let hot = try await hotAlbums
        let latest = (try? await latestAlbums) ?? []
        let artists = (try? await hotArtists) ?? []
        let playlists = (try? await publicPlaylists)?.data ?? []

        let personalized = authSession.isAuthenticated
            ? ((try? await personalizedHomeAlbums()) ?? [])
            : []
        let recommended = personalized.isEmpty ? hot : personalized
        let recommendedIDs = Set(recommended.map(\.id))
        return MusicHomeFeed(
            recommended: recommended,
            latest: Array(latest.filter { !recommendedIDs.contains($0.id) }.prefix(8)),
            artists: artists,
            playlists: playlists.map {
                MusicDiscoverItem(
                    type: .playlist, id: $0.id, title: $0.name,
                    summary: $0.description, imageURL: $0.coverURL,
                    targetPath: "/music/playlist/\($0.id)", songCount: $0.songCount
                )
            }
        )
    }

    private func recommendations(kind: MusicDiscoverType, mode: String, limit: Int) async throws -> [MusicDiscoverItem] {
        let path = kind == .artist ? "music/recommend/artists" : "music/recommend/albums"
        let (data, response) = try await client.request(
            path: path, token: authSession.token,
            queryItems: [URLQueryItem(name: "mode", value: mode), URLQueryItem(name: "page_size", value: String(limit))]
        )
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(MusicEnvelope<[MusicRecommendationCard]>.self, from: data).data.map {
            MusicDiscoverItem(
                type: kind, id: $0.id, title: $0.title, summary: $0.summary,
                imageURL: $0.imageURL,
                targetPath: $0.targetPath
            )
        }
    }

    private func personalizedHomeAlbums() async throws -> [MusicDiscoverItem] {
        let (data, response) = try await client.request(path: "music/home", token: authSession.token)
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(MusicEnvelope<MusicPersonalizedHome>.self, from: data).data.forYou.map {
            MusicDiscoverItem(
                type: .album, id: $0.id, title: $0.title,
                summary: $0.reason, imageURL: $0.coverURL,
                targetPath: "/music/album/\($0.id)", artists: $0.artists ?? []
            )
        }
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
        var entries: [MusicPlaylistEntry] = []
        // A playlist can exceed 100 tracks. Fetch its paginated rows before
        // exposing the queue, rather than silently truncating favorites.
        for page in 1...40 {
            let batch: MusicPage<MusicPlaylistEntry> = try await listPage(
                path: "music/playlists/\(id)/songs", page: page, pageSize: 100
            )
            entries.append(contentsOf: batch.data)
            if !batch.hasMore {
                return MusicPlaylistDetail(playlist: playlist, songs: entries.compactMap(\.song))
            }
        }
        throw URLError(.dataLengthExceedsMaximum)
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

    public func remotePlaybackSession() async throws -> MusicRemotePlaybackSession? {
        let (data, response) = try await client.request(
            path: "music/playback-session", token: authSession.token
        )
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(MusicEnvelope<MusicRemotePlaybackSession?>.self, from: data).data
    }

    // Preserve the original snapshot-based SDK contract for existing callers.
    public func playbackSession() async throws -> MusicPlaybackSnapshot? {
        guard let session = try await remotePlaybackSession(),
              !session.queue.isEmpty,
              session.queue.contains(where: { $0.id == session.currentSongID }) else { return nil }
        let mode: MusicPlaybackMode
        switch session.playbackMode {
        case "single": mode = .repeatOne
        case "random": mode = .shuffle
        default: mode = .repeatAll
        }
        return MusicPlaybackSnapshot(
            songs: session.queue, currentSongID: session.currentSongID,
            currentTime: session.positionSeconds, playbackMode: mode
        )
    }

    public func savePlaybackSnapshot(_ snapshot: MusicPlaybackSnapshot) async throws {
        try await savePlaybackSession(snapshot)
        guard let song = snapshot.songs.first(where: { $0.id == snapshot.currentSongID }) else { return }
        try await savePlaybackProgress(
            songID: snapshot.currentSongID,
            position: snapshot.currentTime,
            duration: Double(song.durationSeconds ?? 0), completed: false
        )
    }

    public func savePlaybackSession(_ snapshot: MusicPlaybackSnapshot, reportedAt: Date = Date()) async throws {
        let fullQueue = snapshot.songs.map(\.id)
        let activeIndex = fullQueue.firstIndex(of: snapshot.currentSongID) ?? 0
        let start = min(max(0, activeIndex - 40), max(0, fullQueue.count - 200))
        let songIDs = Array(fullQueue.dropFirst(start).prefix(200))
        guard !songIDs.isEmpty,
              songIDs.allSatisfy({ UUID(uuidString: $0) != nil }),
              UUID(uuidString: snapshot.currentSongID) != nil,
              songIDs.contains(snapshot.currentSongID),
              Set(songIDs).count == songIDs.count else { return }
        let mode: String
        switch snapshot.playbackMode {
        case .repeatOne: mode = "single"
        case .shuffle: mode = "random"
        // The web session protocol has no distinct sequential mode.
        case .sequential, .repeatAll: mode = "loop"
        }
        let body = try JSONEncoder().encode(MusicPlaybackSessionInput(
            songIDs: songIDs, currentSongID: snapshot.currentSongID,
            positionSeconds: max(0, snapshot.currentTime), playbackMode: mode,
            reportedAt: Self.timestamp(reportedAt)
        ))
        try await send(path: "music/playback-session", method: "PUT", body: body, expectedStatus: 200)
    }

    public func savePlaybackProgress(songID: String, position: Double, duration: Double, completed: Bool, reportedAt: Date = Date()) async throws {
        guard UUID(uuidString: songID) != nil else { return }
        let body = try JSONEncoder().encode(MusicPlaybackProgressInput(
            songID: songID, positionSeconds: max(0, position),
            durationSeconds: max(0, duration), completed: completed,
            reportedAt: Self.timestamp(reportedAt)
        ))
        try await send(path: "music/playback-progress", method: "PUT", body: body, expectedStatus: 200)
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
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

    // The server exposes page/meta for every library list. Keep the previous
    // first-page API for existing callers, but expose pagination to views.
    public func playlistPage(page: Int = 1, pageSize: Int = 50) async throws -> MusicPage<MusicPlaylist> {
        try await listPage(path: "music/playlists", page: page, pageSize: pageSize)
    }

    public func favoriteAlbumPage(page: Int = 1, pageSize: Int = 50) async throws -> MusicPage<MusicAlbumBookmark> {
        try await listPage(path: "music/bookmarks/albums", page: page, pageSize: pageSize)
    }

    public func favoriteArtistPage(page: Int = 1, pageSize: Int = 50) async throws -> MusicPage<MusicArtistBookmark> {
        try await listPage(path: "music/bookmarks/artists", page: page, pageSize: pageSize)
    }

    public func historyPage(page: Int = 1, pageSize: Int = 50) async throws -> MusicPage<MusicHistoryItem> {
        try await listPage(path: "music/history", page: page, pageSize: pageSize)
    }

    private func list<Value: Decodable>(path: String, pageSize: Int) async throws -> [Value] {
        var all: [Value] = []
        for page in 1...40 {
            let batch: MusicPage<Value> = try await listPage(path: path, page: page, pageSize: pageSize)
            all.append(contentsOf: batch.data)
            if !batch.hasMore || batch.data.isEmpty { return all }
        }
        throw URLError(.dataLengthExceedsMaximum)
    }

    private func listPage<Value: Decodable>(path: String, page: Int, pageSize: Int) async throws -> MusicPage<Value> {
        let (data, response) = try await client.request(
            path: path,
            token: authSession.token,
            queryItems: [
                URLQueryItem(name: "page", value: String(max(1, page))),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ]
        )
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(MusicListEnvelope<Value>.self, from: data)
        return MusicPage(data: decoded.data, hasMore: decoded.meta?.hasMore ?? (decoded.data.count >= pageSize))
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

public struct MusicPage<Value: Decodable> {
    public let data: [Value]
    public let hasMore: Bool
}

private struct MusicListEnvelope<Value: Decodable>: Decodable {
    let data: [Value]
    let meta: MusicListMeta?
}

private struct MusicListMeta: Decodable {
    let hasMore: Bool
    enum CodingKeys: String, CodingKey { case hasMore = "has_more" }
}

private struct MusicPlaybackSessionInput: Encodable {
    let songIDs: [String]
    let currentSongID: String
    let positionSeconds: Double
    let playbackMode: String
    let reportedAt: String
    enum CodingKeys: String, CodingKey {
        case songIDs = "song_ids"
        case currentSongID = "current_song_id"
        case positionSeconds = "position_seconds"
        case playbackMode = "playback_mode"
        case reportedAt = "reported_at"
    }
}

private struct MusicPlaybackProgressInput: Encodable {
    let songID: String
    let positionSeconds: Double
    let durationSeconds: Double
    let completed: Bool
    let reportedAt: String
    enum CodingKeys: String, CodingKey {
        case songID = "song_id"
        case positionSeconds = "position_seconds"
        case durationSeconds = "duration_seconds"
        case completed
        case reportedAt = "reported_at"
    }
}

private struct MusicRecommendationCard: Decodable {
    let id: String
    let title: String
    let summary: String?
    let imageURL: String?
    let targetPath: String

    enum CodingKeys: String, CodingKey {
        case id, title, summary
        case imageURL = "image_url"
        case targetPath = "target_path"
    }
}

private struct MusicPublicPlaylistCard: Decodable {
    let id: String
    let name: String
    let description: String?
    let coverURL: String?
    let songCount: Int
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case coverURL = "cover_url"
        case songCount = "song_count"
    }
}

private struct MusicPersonalizedHome: Decodable {
    let forYou: [MusicPersonalizedAlbum]
    enum CodingKeys: String, CodingKey { case forYou = "for_you" }
}

private struct MusicPersonalizedAlbum: Decodable {
    let id: String
    let title: String
    let coverURL: String?
    let artists: [MusicArtist]?
    let reason: String?
    enum CodingKeys: String, CodingKey { case id, title, artists, reason; case coverURL = "cover_url" }
}

private struct MusicEnvelope<Value: Decodable>: Decodable {
    let data: Value
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
