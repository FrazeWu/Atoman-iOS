import Foundation

public struct MusicPlaybackSnapshot: Codable, Hashable, Sendable {
    public let songs: [MusicSong]
    public let currentSongID: String
    public let currentTime: TimeInterval
    public let playbackMode: MusicPlaybackMode

    public init(
        songs: [MusicSong],
        currentSongID: String,
        currentTime: TimeInterval,
        playbackMode: MusicPlaybackMode
    ) {
        self.songs = songs
        self.currentSongID = currentSongID
        self.currentTime = currentTime
        self.playbackMode = playbackMode
    }
}

@MainActor
public protocol MusicPlaybackStateStore: AnyObject {
    func load() -> MusicPlaybackSnapshot?
    func save(_ snapshot: MusicPlaybackSnapshot)
}

@MainActor
public final class UserDefaultsMusicPlaybackStateStore: MusicPlaybackStateStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "atoman.music.playback-state") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> MusicPlaybackSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MusicPlaybackSnapshot.self, from: data)
    }

    public func save(_ snapshot: MusicPlaybackSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
