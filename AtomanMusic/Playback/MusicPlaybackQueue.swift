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
    public var mode: MusicPlaybackMode {
        didSet {
            if mode == .shuffle && oldValue != .shuffle {
                shuffleUpcoming()
            }
        }
    }

    public var currentSong: MusicSong? {
        guard let currentIndex, songs.indices.contains(currentIndex) else {
            return nil
        }
        return songs[currentIndex]
    }

    public var upcomingSongs: [MusicSong] {
        guard let currentIndex, currentIndex + 1 < songs.count else { return [] }
        return Array(songs[(currentIndex + 1)...])
    }

    public init(mode: MusicPlaybackMode = .sequential) {
        self.mode = mode
    }

    public mutating func load(
        _ songs: [MusicSong],
        startingAt songID: String? = nil,
        preservingOrder: Bool = false
    ) {
        self.songs = songs
        guard !songs.isEmpty else {
            currentIndex = nil
            return
        }
        currentIndex = songID.flatMap { id in songs.firstIndex { $0.id == id } } ?? 0
        if mode == .shuffle && !preservingOrder {
            shuffleUpcoming()
        }
    }

    @discardableResult
    public mutating func prioritize(_ song: MusicSong) -> Bool {
        guard let currentIndex, currentSong?.id != song.id else { return false }
        var insertionIndex = currentIndex + 1
        if let existingIndex = songs.firstIndex(where: { $0.id == song.id }) {
            songs.remove(at: existingIndex)
            if existingIndex < insertionIndex {
                insertionIndex -= 1
            }
            self.currentIndex = existingIndex < currentIndex ? currentIndex - 1 : currentIndex
        }
        songs.insert(song, at: insertionIndex)
        return true
    }

    @discardableResult
    public mutating func enqueue(_ song: MusicSong) -> Bool {
        guard let currentIndex, currentSong?.id != song.id else { return false }
        if let existingIndex = songs.firstIndex(where: { $0.id == song.id }) {
            songs.remove(at: existingIndex)
            if existingIndex < currentIndex {
                self.currentIndex = currentIndex - 1
            }
        }
        songs.append(song)
        return true
    }

    @discardableResult
    public mutating func moveUpcoming(from sourceIndex: Int, to destinationIndex: Int) -> Bool {
        guard let currentIndex else { return false }
        let upcomingCount = songs.count - currentIndex - 1
        guard upcomingCount > 1, (0..<upcomingCount).contains(sourceIndex) else { return false }
        let targetIndex = min(max(0, destinationIndex), upcomingCount - 1)
        guard sourceIndex != targetIndex else { return false }

        let song = songs.remove(at: currentIndex + 1 + sourceIndex)
        songs.insert(song, at: currentIndex + 1 + targetIndex)
        return true
    }

    @discardableResult
    public mutating func removeUpcoming(at index: Int) -> Bool {
        guard let currentIndex else { return false }
        let absoluteIndex = currentIndex + 1 + index
        guard songs.indices.contains(absoluteIndex) else { return false }
        songs.remove(at: absoluteIndex)
        return true
    }

    @discardableResult
    public mutating func clearUpcoming() -> Bool {
        guard let currentIndex, currentIndex + 1 < songs.count else { return false }
        songs.removeSubrange((currentIndex + 1)...)
        return true
    }

    @discardableResult
    public mutating func select(songID: String) -> MusicSong? {
        guard let index = songs.firstIndex(where: { $0.id == songID }) else { return nil }
        currentIndex = index
        return currentSong
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
        case .shuffle, .sequential:
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
        case .shuffle, .sequential:
            guard currentIndex > 0 else {
                return nil
            }
            self.currentIndex = currentIndex - 1
        }
        return currentSong
    }

    private mutating func shuffleUpcoming() {
        guard let currentIndex, currentIndex + 1 < songs.count else { return }
        var upcoming = Array(songs[(currentIndex + 1)...])
        upcoming.shuffle()
        songs.replaceSubrange((currentIndex + 1)..., with: upcoming)
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
