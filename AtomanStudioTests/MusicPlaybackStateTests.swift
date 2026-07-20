import Foundation
import XCTest
@testable import AtomanMusic

@MainActor
final class MusicPlaybackStateTests: XCTestCase {
    func testUserDefaultsStoreRoundTripsPlaybackSnapshot() throws {
        let suiteName = "MusicPlaybackStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMusicPlaybackStateStore(defaults: defaults, key: "playback")
        let snapshot = MusicPlaybackSnapshot(
            songs: try [song(id: "one"), song(id: "two")],
            currentSongID: "two",
            currentTime: 73.5,
            playbackMode: .shuffle
        )

        store.save(snapshot)

        XCTAssertEqual(store.load(), snapshot)
    }

    func testRestoresSavedQueuePausedWithoutLoadingAudio() throws {
        let songs = try [song(id: "one"), song(id: "two")]
        let store = PlaybackStateStoreSpy(
            snapshot: MusicPlaybackSnapshot(
                songs: songs,
                currentSongID: "two",
                currentTime: 42,
                playbackMode: .repeatAll
            )
        )
        let engine = StatePlaybackEngineSpy()

        let player = MusicPlayer(engine: engine, stateStore: store)

        XCTAssertEqual(player.currentSong?.id, "two")
        XCTAssertEqual(player.currentTime, 42)
        XCTAssertEqual(player.playbackMode, .repeatAll)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(engine.loadCallCount, 0)
        XCTAssertEqual(engine.playCallCount, 0)
    }

    func testResumingRestoredQueueLoadsAndSeeksBeforePlaying() throws {
        let songs = try [song(id: "one")]
        let store = PlaybackStateStoreSpy(
            snapshot: MusicPlaybackSnapshot(
                songs: songs,
                currentSongID: "one",
                currentTime: 37,
                playbackMode: .sequential
            )
        )
        let engine = StatePlaybackEngineSpy()
        let player = MusicPlayer(engine: engine, stateStore: store)

        player.togglePlayback()

        XCTAssertEqual(engine.loadCallCount, 1)
        XCTAssertEqual(engine.seekTimes, [37])
        XCTAssertEqual(engine.playCallCount, 1)
        XCTAssertTrue(player.isPlaying)
    }

    func testNowPlayingMetadataIncludesResolvedArtworkURL() throws {
        let publisher = NowPlayingPublisherSpy()
        let player = MusicPlayer(engine: StatePlaybackEngineSpy(), nowPlayingPublisher: publisher)

        player.play(songs: try [song(id: "one")], startingAt: "one")

        XCTAssertEqual(publisher.metadata?.title, "Song one")
        XCTAssertEqual(publisher.metadata?.artworkURL?.absoluteString, "https://cdn.example.com/one.jpg")
    }

    private func song(id: String) throws -> MusicSong {
        try JSONDecoder().decode(
            MusicSong.self,
            from: Data("{\"id\":\"\(id)\",\"title\":\"Song \(id)\",\"audio_url\":\"https://cdn.example.com/\(id).mp3\",\"cover_url\":\"https://cdn.example.com/\(id).jpg\"}".utf8)
        )
    }
}

@MainActor
private final class PlaybackStateStoreSpy: MusicPlaybackStateStore {
    var snapshot: MusicPlaybackSnapshot?

    init(snapshot: MusicPlaybackSnapshot?) {
        self.snapshot = snapshot
    }

    func load() -> MusicPlaybackSnapshot? { snapshot }
    func save(_ snapshot: MusicPlaybackSnapshot) { self.snapshot = snapshot }
}

@MainActor
private final class NowPlayingPublisherSpy: MusicNowPlayingPublishing {
    var metadata: MusicNowPlayingMetadata?

    func update(_ metadata: MusicNowPlayingMetadata) {
        self.metadata = metadata
    }

    func clear() {
        metadata = nil
    }
}

@MainActor
private final class StatePlaybackEngineSpy: MusicPlaybackEngine {
    var onTimeUpdate: ((TimeInterval, TimeInterval) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onBufferingChanged: ((Bool) -> Void)?
    var onPlaybackFailed: ((String) -> Void)?
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?
    var onOutputDisconnected: (() -> Void)?
    var loadCallCount = 0
    var playCallCount = 0
    var seekTimes: [TimeInterval] = []

    func load(url: URL) { loadCallCount += 1 }
    func play() { playCallCount += 1 }
    func pause() {}
    func seek(to time: TimeInterval) { seekTimes.append(time) }
}
