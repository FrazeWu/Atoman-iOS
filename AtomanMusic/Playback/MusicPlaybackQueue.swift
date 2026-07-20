import Foundation

public enum MusicPlaybackMode: String, CaseIterable, Codable, Sendable {
    case sequential
    case repeatAll
    case repeatOne
    case shuffle
}

public struct MusicPlaybackQueue: Sendable {
    public private(set) var songs: [MusicSong] = []
    public private(set) var currentIndex: Int?
    public var mode: MusicPlaybackMode

    public var currentSong: MusicSong? {
        guard let currentIndex, songs.indices.contains(currentIndex) else {
            return nil
        }
        return songs[currentIndex]
    }

    public init(mode: MusicPlaybackMode = .sequential) {
        self.mode = mode
    }

    public mutating func load(_ songs: [MusicSong], startingAt songID: String? = nil) {
        self.songs = songs
        guard !songs.isEmpty else {
            currentIndex = nil
            return
        }
        currentIndex = songID.flatMap { id in songs.firstIndex { $0.id == id } } ?? 0
    }

    @discardableResult
    public mutating func moveNext() -> MusicSong? {
        guard let currentIndex, !songs.isEmpty else {
            return nil
        }
        switch mode {
        case .repeatOne:
            break
        case .repeatAll:
            self.currentIndex = (currentIndex + 1) % songs.count
        case .shuffle:
            self.currentIndex = songs.count == 1 ? 0 : randomIndex(excluding: currentIndex)
        case .sequential:
            guard currentIndex + 1 < songs.count else {
                return nil
            }
            self.currentIndex = currentIndex + 1
        }
        return currentSong
    }

    @discardableResult
    public mutating func movePrevious() -> MusicSong? {
        guard let currentIndex, !songs.isEmpty else {
            return nil
        }
        switch mode {
        case .repeatOne:
            break
        case .repeatAll:
            self.currentIndex = (currentIndex - 1 + songs.count) % songs.count
        case .shuffle:
            self.currentIndex = songs.count == 1 ? 0 : randomIndex(excluding: currentIndex)
        case .sequential:
            guard currentIndex > 0 else {
                return nil
            }
            self.currentIndex = currentIndex - 1
        }
        return currentSong
    }

    private func randomIndex(excluding index: Int) -> Int {
        var candidate = Int.random(in: songs.indices)
        while candidate == index {
            candidate = Int.random(in: songs.indices)
        }
        return candidate
    }
}

public struct MusicPlaybackRecordPolicy: Sendable {
    private var currentSongID: String?
    private var didRecordCurrentSong = false

    public init() {}

    public mutating func shouldRecord(songID: String, elapsed: TimeInterval) -> Bool {
        if currentSongID != songID {
            currentSongID = songID
            didRecordCurrentSong = false
        }
        guard elapsed >= 5, !didRecordCurrentSong else {
            return false
        }
        didRecordCurrentSong = true
        return true
    }
}
