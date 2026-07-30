import Foundation
import XCTest
@testable import AtomanMusic

final class MusicPlaybackQueueTests: XCTestCase {
    func testPlaybackModesHaveChineseAccessibilityNames() {
        XCTAssertEqual(MusicPlaybackMode.sequential.accessibilityName, "顺序播放")
        XCTAssertEqual(MusicPlaybackMode.repeatAll.accessibilityName, "列表循环")
        XCTAssertEqual(MusicPlaybackMode.repeatOne.accessibilityName, "单曲循环")
        XCTAssertEqual(MusicPlaybackMode.shuffle.accessibilityName, "随机播放")
    }

    func testLoadsQueueAtRequestedSongAndMovesSequentially() throws {
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        var queue = MusicPlaybackQueue()

        queue.load(songs, startingAt: "two")

        XCTAssertEqual(queue.currentSong?.id, "two")
        XCTAssertEqual(queue.moveNext()?.id, "three")
        XCTAssertEqual(queue.movePrevious()?.id, "two")
    }

    func testRepeatAllWrapsAtQueueBoundary() throws {
        let songs = try [song(id: "one"), song(id: "two")]
        var queue = MusicPlaybackQueue(mode: .repeatAll)
        queue.load(songs, startingAt: "two")

        XCTAssertEqual(queue.moveNext()?.id, "one")
        XCTAssertEqual(queue.movePrevious()?.id, "two")
    }

    func testPrioritizeMovesExistingSongDirectlyAfterCurrentWithoutDuplication() throws {
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        var queue = MusicPlaybackQueue()
        queue.load(songs, startingAt: "two")

        queue.prioritize(songs[0])

        XCTAssertEqual(queue.songs.map(\.id), ["two", "one", "three"])
        XCTAssertEqual(queue.currentSong?.id, "two")
        XCTAssertEqual(queue.upcomingSongs.map(\.id), ["one", "three"])
    }

    func testEnqueueMovesExistingSongToEndWithoutDuplication() throws {
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        var queue = MusicPlaybackQueue()
        queue.load(songs, startingAt: "one")

        queue.enqueue(songs[1])
        queue.enqueue(try song(id: "four"))

        XCTAssertEqual(queue.songs.map(\.id), ["one", "three", "two", "four"])
        XCTAssertEqual(queue.currentSong?.id, "one")
    }

    func testMoveUpcomingReordersOnlySongsAfterCurrent() throws {
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three"), song(id: "four")]
        var queue = MusicPlaybackQueue()
        queue.load(songs, startingAt: "one")

        queue.moveUpcoming(from: 2, to: 0)

        XCTAssertEqual(queue.currentSong?.id, "one")
        XCTAssertEqual(queue.upcomingSongs.map(\.id), ["four", "two", "three"])
    }

    func testRemoveUpcomingKeepsCurrentSong() throws {
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        var queue = MusicPlaybackQueue()
        queue.load(songs, startingAt: "one")

        queue.removeUpcoming(at: 0)

        XCTAssertEqual(queue.currentSong?.id, "one")
        XCTAssertEqual(queue.songs.map(\.id), ["one", "three"])
    }

    func testClearUpcomingKeepsHistoryAndCurrentSong() throws {
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        var queue = MusicPlaybackQueue()
        queue.load(songs, startingAt: "two")

        queue.clearUpcoming()

        XCTAssertEqual(queue.songs.map(\.id), ["one", "two"])
        XCTAssertEqual(queue.currentSong?.id, "two")
        XCTAssertTrue(queue.upcomingSongs.isEmpty)
    }

    func testShuffleHonorsPrioritizedSongThenContinuesArrangedOrder() throws {
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        var queue = MusicPlaybackQueue(mode: .shuffle)
        queue.load(songs, startingAt: "one", preservingOrder: true)
        queue.prioritize(songs[2])

        XCTAssertEqual(queue.moveNext()?.id, "three")
        XCTAssertEqual(queue.moveNext()?.id, "two")
    }

    func testSelectChangesCurrentSongWithoutChangingQueueOrder() throws {
        let songs = try [song(id: "one"), song(id: "two"), song(id: "three")]
        var queue = MusicPlaybackQueue()
        queue.load(songs, startingAt: "one")

        let selected = queue.select(songID: "three")

        XCTAssertEqual(selected?.id, "three")
        XCTAssertEqual(queue.songs.map(\.id), ["one", "two", "three"])
    }

    func testPlaybackRecordPolicyRecordsOnceAfterFiveSeconds() {
        var policy = MusicPlaybackRecordPolicy()

        XCTAssertFalse(policy.shouldRecord(songID: "one", elapsed: 4.9))
        XCTAssertTrue(policy.shouldRecord(songID: "one", elapsed: 5.0))
        XCTAssertFalse(policy.shouldRecord(songID: "one", elapsed: 10.0))
        XCTAssertTrue(policy.shouldRecord(songID: "two", elapsed: 5.0))
    }

    private func song(id: String) throws -> MusicSong {
        try JSONDecoder().decode(
            MusicSong.self,
            from: Data("{\"id\":\"\(id)\",\"title\":\"Song \(id)\",\"audio_url\":\"https://cdn.example.com/\(id).mp3\"}".utf8)
        )
    }
}
