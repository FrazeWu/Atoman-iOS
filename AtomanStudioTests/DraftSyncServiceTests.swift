import XCTest
@testable import AtomanStudio

final class DraftSyncServiceTests: XCTestCase {
    func testNewerLocalDraftWinsRecoveryComparison() throws {
        let service = DraftSyncService(clock: { Date(timeIntervalSince1970: 200) })
        let olderRemote = DraftSyncCandidate(source: .remote, payload: .fixture(title: "remote"), savedAt: Date(timeIntervalSince1970: 100))
        let newerLocal = DraftSyncCandidate(source: .local, payload: .fixture(title: "local"), savedAt: Date(timeIntervalSince1970: 200))

        let winner = service.pickRecoveryCandidate(local: newerLocal, remote: olderRemote)

        XCTAssertEqual(winner?.source, .local)
        XCTAssertEqual(winner?.payload.title, "local")
    }
}
