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

    func testRestoresSavedShuffleOrderWithoutShufflingAgain() throws {
        let songs = try (1...9).map { try song(id: String($0)) }
        let store = PlaybackStateStoreSpy(
            snapshot: MusicPlaybackSnapshot(
                songs: songs,
                currentSongID: "1",
                currentTime: 0,
                playbackMode: .shuffle
            )
        )
        let player = MusicPlayer(engine: StatePlaybackEngineSpy(), stateStore: store)

        player.playNext()

        XCTAssertEqual(player.currentSong?.id, "2")
        XCTAssertEqual(player.songs.map(\.id), songs.map(\.id))
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

    func testRemoteSessionRestoresQueuePausedAndRetainsPosition() throws {
        let remote = try JSONDecoder().decode(MusicRemotePlaybackSession.self, from: Data("""
        {"queue":[{"id":"one","title":"One","audio_url":"https://example.com/one.mp3"},{"id":"two","title":"Two","audio_url":"https://example.com/two.mp3"}],"current_song_id":"two","position_seconds":62.5,"playback_mode":"single"}
        """.utf8))
        let engine = StatePlaybackEngineSpy()
        let store = PlaybackStateStoreSpy(snapshot: nil)
        let player = MusicPlayer(engine: engine, stateStore: store)

        XCTAssertTrue(player.restoreRemoteSession(remote))
        XCTAssertEqual(player.currentSong?.id, "two")
        XCTAssertEqual(player.currentTime, 62.5)
        XCTAssertEqual(player.playbackMode, .repeatOne)
        XCTAssertEqual(player.songs.map(\.id), ["one", "two"])
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(engine.loadCallCount, 0)
        XCTAssertEqual(engine.playCallCount, 0)
        XCTAssertEqual(store.snapshot?.currentTime, 62.5)
    }

    func testRemoteSessionDoesNotInterruptLocalPlayback() throws {
        let remote = try JSONDecoder().decode(MusicRemotePlaybackSession.self, from: Data("""
        {"queue":[{"id":"remote","title":"Remote","audio_url":"https://example.com/remote.mp3"}],"current_song_id":"remote","position_seconds":12,"playback_mode":"loop"}
        """.utf8))
        let player = MusicPlayer(engine: StatePlaybackEngineSpy())
        player.play(songs: try [song(id: "local")], startingAt: "local")

        XCTAssertFalse(player.restoreRemoteSession(remote))
        XCTAssertEqual(player.currentSong?.id, "local")
    }

    func testRemoteCallbacksSendQueueAndProgressAfterPlaybackStarts() async throws {
        let engine = StatePlaybackEngineSpy()
        let player = MusicPlayer(engine: engine)
        let sessionSaved = expectation(description: "session saved")
        let progressSaved = expectation(description: "progress saved")
        player.enableRemoteSync(
            session: { snapshot, _ in
                XCTAssertEqual(snapshot.currentSongID, "one")
                sessionSaved.fulfill()
            },
            progress: { id, position, duration, completed, _ in
                XCTAssertEqual(id, "one")
                XCTAssertEqual(position, 15)
                XCTAssertEqual(duration, 120)
                XCTAssertFalse(completed)
                progressSaved.fulfill()
            }
        )
        player.play(songs: try [song(id: "one")], startingAt: "one")
        engine.onTimeUpdate?(15, 120)
        await fulfillment(of: [sessionSaved, progressSaved], timeout: 1)
    }

    func testSignOutPreservesCurrentPlaybackButClearsCachedSnapshot() throws {
        let suite = "music.signout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsMusicPlaybackStateStore(defaults: defaults, key: "playback")
        let player = MusicPlayer(engine: StatePlaybackEngineSpy(), stateStore: store)
        player.play(songs: try [song(id: "one")], startingAt: "one")
        XCTAssertNotNil(store.load())
        player.handleLogout()
        XCTAssertNil(store.load())
        XCTAssertEqual(player.currentSong?.id, "one")
        XCTAssertTrue(player.isPlaying)
        player.seek(to: 12)
        XCTAssertNil(store.load(), "Signed-out playback must not restore the previous account's snapshot")
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
