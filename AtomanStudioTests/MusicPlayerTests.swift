import Foundation
import XCTest
@testable import AtomanMusic

@MainActor
final class MusicPlayerTests: XCTestCase {
    func testPlayQueueLoadsRequestedSongAndStartsEngine() throws {
        let engine = PlaybackEngineSpy()
        let player = MusicPlayer(engine: engine)
        let songs = try [song(id: "one"), song(id: "two")]

        player.play(songs: songs, startingAt: "two")

        XCTAssertEqual(player.currentSong?.id, "two")
        XCTAssertEqual(engine.loadedURL?.absoluteString, "https://cdn.example.com/two.mp3")
        XCTAssertEqual(engine.playCallCount, 1)
        XCTAssertTrue(player.isPlaying)
    }

    func testNextLoadsFollowingSong() throws {
        let engine = PlaybackEngineSpy()
        let player = MusicPlayer(engine: engine)
        let songs = try [song(id: "one"), song(id: "two")]
        player.play(songs: songs, startingAt: "one")

        player.playNext()

        XCTAssertEqual(player.currentSong?.id, "two")
        XCTAssertEqual(engine.loadedURL?.absoluteString, "https://cdn.example.com/two.mp3")
        XCTAssertEqual(engine.playCallCount, 2)
    }

    func testPlayNextSongUpdatesAndPersistsQueue() throws {
        let engine = PlaybackEngineSpy()
        let store = PlayerStateStoreSpy()
        let player = MusicPlayer(engine: engine, stateStore: store)
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        player.play(songs: songs, startingAt: "one")

        player.playNext(songs[2])

        XCTAssertEqual(player.songs.map(\.id), ["one", "three", "two"])
        XCTAssertEqual(player.upcomingSongs.map(\.id), ["three", "two"])
        XCTAssertEqual(store.snapshot?.songs.map(\.id), ["one", "three", "two"])
        XCTAssertEqual(player.queueActionMessage, "已设为下一首")
    }

    func testEnqueueSongMovesItToQueueEndAndPersists() throws {
        let engine = PlaybackEngineSpy()
        let store = PlayerStateStoreSpy()
        let player = MusicPlayer(engine: engine, stateStore: store)
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        player.play(songs: songs, startingAt: "one")

        player.enqueue(songs[1])

        XCTAssertEqual(player.songs.map(\.id), ["one", "three", "two"])
        XCTAssertEqual(store.snapshot?.songs.map(\.id), ["one", "three", "two"])
        XCTAssertEqual(player.queueActionMessage, "已加入队列")
    }

    func testMoveUpcomingPersistsEditedOrder() throws {
        let store = PlayerStateStoreSpy()
        let player = MusicPlayer(engine: PlaybackEngineSpy(), stateStore: store)
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three"), song(id: "four")]
        player.play(songs: songs, startingAt: "one")

        player.moveUpcoming(from: 2, to: 0)

        XCTAssertEqual(player.upcomingSongs.map(\.id), ["four", "two", "three"])
        XCTAssertEqual(store.snapshot?.songs.map(\.id), ["one", "four", "two", "three"])
    }

    func testRemoveUpcomingPersistsShortenedQueue() throws {
        let store = PlayerStateStoreSpy()
        let player = MusicPlayer(engine: PlaybackEngineSpy(), stateStore: store)
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        player.play(songs: songs, startingAt: "one")

        player.removeUpcoming(at: 0)

        XCTAssertEqual(player.upcomingSongs.map(\.id), ["three"])
        XCTAssertEqual(store.snapshot?.songs.map(\.id), ["one", "three"])
    }

    func testClearUpcomingPersistsCurrentAndHistory() throws {
        let store = PlayerStateStoreSpy()
        let player = MusicPlayer(engine: PlaybackEngineSpy(), stateStore: store)
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        player.play(songs: songs, startingAt: "two")

        player.clearUpcoming()

        XCTAssertEqual(player.songs.map(\.id), ["one", "two"])
        XCTAssertEqual(player.currentSong?.id, "two")
        XCTAssertTrue(player.upcomingSongs.isEmpty)
        XCTAssertEqual(store.snapshot?.songs.map(\.id), ["one", "two"])
    }

    func testChangingPlaybackModePersistsVisibleQueueOrder() throws {
        let store = PlayerStateStoreSpy()
        let player = MusicPlayer(engine: PlaybackEngineSpy(), stateStore: store)
        player.play(
            songs: try [song(id: "one"), song(id: "two"), song(id: "three")],
            startingAt: "one"
        )

        player.playbackMode = .shuffle

        XCTAssertEqual(store.snapshot?.playbackMode, .shuffle)
        XCTAssertEqual(store.snapshot?.songs.map(\.id), player.songs.map(\.id))
    }

    func testPlayQueuedSongKeepsExistingQueueOrder() throws {
        let engine = PlaybackEngineSpy()
        let player = MusicPlayer(engine: engine)
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        player.play(songs: songs, startingAt: "one")

        player.playQueuedSong(id: "three")

        XCTAssertEqual(player.currentSong?.id, "three")
        XCTAssertEqual(player.songs.map(\.id), ["one", "two", "three"])
        XCTAssertEqual(engine.loadedURL?.absoluteString, "https://cdn.example.com/three.mp3")
    }

    func testTogglePlaybackPausesAndResumes() throws {
        let engine = PlaybackEngineSpy()
        let player = MusicPlayer(engine: engine)
        player.play(songs: try [song(id: "one")], startingAt: "one")

        player.togglePlayback()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(engine.pauseCallCount, 1)

        player.togglePlayback()
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(engine.playCallCount, 2)
    }

    func testReplayingSameSongRecordsEachPlaybackAfterFiveSeconds() async throws {
        let engine = PlaybackEngineSpy()
        let recordedTwice = expectation(description: "records both playbacks")
        recordedTwice.expectedFulfillmentCount = 2
        let player = MusicPlayer(engine: engine) { songID in
            XCTAssertEqual(songID, "one")
            recordedTwice.fulfill()
        }
        let songs = try [song(id: "one")]

        player.play(songs: songs, startingAt: "one")
        engine.onTimeUpdate?(5, 120)
        player.play(songs: songs, startingAt: "one")
        engine.onTimeUpdate?(5, 120)

        await fulfillment(of: [recordedTwice], timeout: 0.2)
    }

    func testPlaybackFailureStopsPlaybackAndRetryReloadsCurrentSong() throws {
        let engine = PlaybackEngineSpy()
        let player = MusicPlayer(engine: engine)
        player.play(songs: try [song(id: "one")], startingAt: "one")

        engine.onPlaybackFailed?("音频加载失败")

        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.errorMessage, "音频加载失败")

        player.retryCurrentSong()

        XCTAssertTrue(player.isPlaying)
        XCTAssertNil(player.errorMessage)
        XCTAssertEqual(engine.loadCallCount, 2)
        XCTAssertEqual(engine.playCallCount, 2)
    }

    func testBufferingStateFollowsPlaybackEngine() throws {
        let engine = PlaybackEngineSpy()
        let player = MusicPlayer(engine: engine)
        player.play(songs: try [song(id: "one")], startingAt: "one")

        engine.onBufferingChanged?(true)
        XCTAssertTrue(player.isBuffering)

        engine.onBufferingChanged?(false)
        XCTAssertFalse(player.isBuffering)
    }

    func testInterruptionResumesOnlyWhenSystemRecommendsIt() throws {
        let engine = PlaybackEngineSpy()
        let player = MusicPlayer(engine: engine)
        player.play(songs: try [song(id: "one")], startingAt: "one")

        engine.onInterruptionBegan?()
        XCTAssertFalse(player.isPlaying)

        engine.onInterruptionEnded?(true)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(engine.playCallCount, 2)
    }

    func testOutputDisconnectPausesPlayback() throws {
        let engine = PlaybackEngineSpy()
        let player = MusicPlayer(engine: engine)
        player.play(songs: try [song(id: "one")], startingAt: "one")

        engine.onOutputDisconnected?()

        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(engine.pauseCallCount, 1)
    }

    private func song(id: String) throws -> MusicSong {
        try JSONDecoder().decode(
            MusicSong.self,
            from: Data("{\"id\":\"\(id)\",\"title\":\"Song \(id)\",\"audio_url\":\"https://cdn.example.com/\(id).mp3\"}".utf8)
        )
    }
}

@MainActor
private final class PlayerStateStoreSpy: MusicPlaybackStateStore {
    var snapshot: MusicPlaybackSnapshot?

    func load() -> MusicPlaybackSnapshot? { snapshot }
    func save(_ snapshot: MusicPlaybackSnapshot) { self.snapshot = snapshot }
}

@MainActor
private final class PlaybackEngineSpy: MusicPlaybackEngine {
    var onTimeUpdate: ((TimeInterval, TimeInterval) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onBufferingChanged: ((Bool) -> Void)?
    var onPlaybackFailed: ((String) -> Void)?
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?
    var onOutputDisconnected: (() -> Void)?
    var loadedURL: URL?
    var loadCallCount = 0
    var playCallCount = 0
    var pauseCallCount = 0

    func load(url: URL) {
        loadedURL = url
        loadCallCount += 1
    }

    func play() {
        playCallCount += 1
    }

    func pause() {
        pauseCallCount += 1
    }

    func seek(to time: TimeInterval) {}
}
