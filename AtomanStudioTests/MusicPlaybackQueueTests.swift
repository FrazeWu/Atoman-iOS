import Foundation
import XCTest
@testable import AtomanMusic

final class MusicPlaybackQueueTests: XCTestCase {
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
