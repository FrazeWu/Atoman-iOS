import Foundation

public struct MusicArtist: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let imageURL: String?
    public let bio: String?

    enum CodingKeys: String, CodingKey {
        case id, name, bio
        case imageURL = "image_url"
    }
}

public struct MusicArtistDetail: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let imageURL: String?
    public let bio: String?
    public let albums: [MusicAlbum]

    public var resolvedImageURL: String? {
        imageURL?.isEmpty == false ? imageURL : albums.lazy.compactMap(\.resolvedCoverURL).first
    }

    public var fallbackImageURL: String? {
        albums.lazy.compactMap(\.resolvedCoverURL).first
    }

    enum CodingKeys: String, CodingKey {
        case id, name, bio, albums
        case imageURL = "image_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        albums = try container.decodeIfPresent([MusicAlbum].self, forKey: .albums) ?? []
    }
}

public struct MusicAlbumSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let coverURL: String?
    public let artists: [MusicArtist]

    enum CodingKeys: String, CodingKey {
        case id, title, artists
        case coverURL = "cover_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        coverURL = try container.decodeIfPresent(String.self, forKey: .coverURL)
        artists = try container.decodeIfPresent([MusicArtist].self, forKey: .artists) ?? []
    }

    init(id: String, title: String, coverURL: String?, artists: [MusicArtist]) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.artists = artists
    }
}

public struct MusicSong: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let trackNumber: Int?
    public let audioURL: String?
    public let coverURL: String?
    public let lyrics: String?
    public let durationSeconds: Int?
    public let artists: [MusicArtist]
    public let album: MusicAlbumSummary?

    public var artistText: String {
        let names = artists.map(\.name)
        return names.isEmpty ? "未知艺人" : names.joined(separator: "、")
    }

    public var resolvedCoverURL: String? {
        if coverURL?.isEmpty == false { return coverURL }
        return album?.coverURL
    }

    enum CodingKeys: String, CodingKey {
        case id, title, lyrics, artists, album
        case trackNumber = "track_number"
        case audioURL = "audio_url"
        case coverURL = "cover_url"
        case durationSeconds = "duration_sec"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        trackNumber = try container.decodeIfPresent(Int.self, forKey: .trackNumber)
        audioURL = try container.decodeIfPresent(String.self, forKey: .audioURL)
        coverURL = try container.decodeIfPresent(String.self, forKey: .coverURL)
        lyrics = try container.decodeIfPresent(String.self, forKey: .lyrics)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        artists = try container.decodeIfPresent([MusicArtist].self, forKey: .artists) ?? []
        album = try container.decodeIfPresent(MusicAlbumSummary.self, forKey: .album)
    }

    func inheritingAlbum(_ album: MusicAlbumSummary) -> MusicSong {
        guard self.album == nil else { return self }
        return MusicSong(
            id: id,
            title: title,
            trackNumber: trackNumber,
            audioURL: audioURL,
            coverURL: self.coverURL,
            lyrics: lyrics,
            durationSeconds: durationSeconds,
            artists: artists,
            album: album
        )
    }

    private init(
        id: String,
        title: String,
        trackNumber: Int?,
        audioURL: String?,
        coverURL: String?,
        lyrics: String?,
        durationSeconds: Int?,
        artists: [MusicArtist],
        album: MusicAlbumSummary?
    ) {
        self.id = id
        self.title = title
        self.trackNumber = trackNumber
        self.audioURL = audioURL
        self.coverURL = coverURL
        self.lyrics = lyrics
        self.durationSeconds = durationSeconds
        self.artists = artists
        self.album = album
    }
}

public struct MusicAlbum: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let year: Int?
    public let coverURL: String?
    public let artists: [MusicArtist]
    public let songs: [MusicSong]

    public var resolvedCoverURL: String? {
        coverURL?.isEmpty == false ? coverURL : songs.lazy.compactMap(\.resolvedCoverURL).first
    }

    enum CodingKeys: String, CodingKey {
        case id, title, year, artists, songs
        case coverURL = "cover_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decode(String.self, forKey: .id)
        let decodedTitle = try container.decode(String.self, forKey: .title)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        let decodedCoverURL = try container.decodeIfPresent(String.self, forKey: .coverURL)
        let decodedArtists = try container.decodeIfPresent([MusicArtist].self, forKey: .artists) ?? []
        id = decodedID
        title = decodedTitle
        coverURL = decodedCoverURL
        artists = decodedArtists
        let decodedSongs = try container.decodeIfPresent([MusicSong].self, forKey: .songs) ?? []
        let albumSummary = MusicAlbumSummary(
            id: decodedID,
            title: decodedTitle,
            coverURL: decodedCoverURL,
            artists: decodedArtists
        )
        songs = decodedSongs.map { $0.inheritingAlbum(albumSummary) }
    }
}

public struct MusicPlaylist: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let coverURL: String?
    public let isPublic: Bool
    public let isFavorite: Bool
    public let songCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case coverURL = "cover_url"
        case isPublic = "is_public"
        case isFavorite = "is_favorite"
        case songCount = "song_count"
    }
}

public struct MusicPlaylistEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let position: Int
    public let song: MusicSong?
}

public struct MusicPlaylistDetail: Hashable, Identifiable, Sendable {
    public let playlist: MusicPlaylist
    public let songs: [MusicSong]

    public var id: String { playlist.id }
    public var name: String { playlist.name }
    public var description: String? { playlist.description }
    public var coverURL: String? { playlist.coverURL ?? songs.first?.resolvedCoverURL }
}

public enum MusicDiscoverType: String, Codable, Hashable, Sendable {
    case album
    case artist
    case playlist
}

public struct MusicDiscoverItem: Codable, Hashable, Identifiable, Sendable {
    public let type: MusicDiscoverType
    public let id: String
    public let title: String
    public let summary: String?
    public let imageURL: String?
    public let targetPath: String
    public let artists: [MusicArtist]
    public let songCount: Int

    public init(album: MusicAlbum) {
        self.type = .album
        self.id = album.id
        self.title = album.title
        self.summary = nil
        self.imageURL = album.resolvedCoverURL
        self.targetPath = "/music/album/\(album.id)"
        self.artists = album.artists
        self.songCount = album.songs.count
    }

    public init(playlist: MusicPlaylist) {
        self.type = .playlist
        self.id = playlist.id
        self.title = playlist.name
        self.summary = playlist.description
        self.imageURL = playlist.coverURL
        self.targetPath = "/music/playlist/\(playlist.id)"
        self.artists = []
        self.songCount = playlist.songCount
    }

    public var displaySubtitle: String? {
        switch type {
        case .album:
            let names = artists.map(\.name).joined(separator: "、")
            return names.isEmpty ? nonemptySummary : names
        case .artist:
            return nonemptySummary ?? "艺人"
        case .playlist:
            return songCount > 0 ? "歌单 · \(songCount) 首" : "歌单"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, id, title, summary, artists
        case imageURL = "image_url"
        case targetPath = "target_path"
        case songCount = "song_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(MusicDiscoverType.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        targetPath = try container.decode(String.self, forKey: .targetPath)
        artists = try container.decodeIfPresent([MusicArtist].self, forKey: .artists) ?? []
        songCount = try container.decodeIfPresent(Int.self, forKey: .songCount) ?? 0
    }

    private var nonemptySummary: String? {
        guard let summary, !summary.isEmpty else { return nil }
        return summary
    }
}

public struct MusicSearchResults: Codable, Hashable, Sendable {
    public let songs: [MusicSong]
    public let albums: [MusicAlbum]
    public let artists: [MusicArtist]
    public let playlists: [MusicPlaylist]
}

public struct MusicAlbumBookmark: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let albumID: String
    public let album: MusicAlbum?

    enum CodingKeys: String, CodingKey {
        case id, album
        case albumID = "album_id"
    }
}

public struct MusicArtistBookmark: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let artistID: String
    public let artist: MusicArtist?

    enum CodingKeys: String, CodingKey {
        case id, artist
        case artistID = "artist_id"
    }
}

public struct MusicHistoryItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let playCount: Int
    public let lastPlayedAt: String
    public let song: MusicSong?

    enum CodingKeys: String, CodingKey {
        case id, song
        case playCount = "play_count"
        case lastPlayedAt = "last_played_at"
    }
}
