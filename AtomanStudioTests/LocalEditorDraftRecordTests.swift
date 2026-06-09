import XCTest
@testable import AtomanStudio

final class LocalEditorDraftRecordTests: XCTestCase {
    func testDraftRoundTrip() throws {
        let database = try AppDatabase.inMemory()
        var record = LocalEditorDraftRecord(
            contextKey: "blog:new",
            sourcePostID: nil,
            title: "Hello",
            content: "World",
            summary: "",
            coverURL: "",
            visibility: "followers",
            allowComments: true,
            channelID: "channel-1",
            collectionIDsJSON: "[\"c1\",\"c2\"]",
            savedAt: Date()
        )

        try database.writer.write { db in
            try record.insert(db)
        }

        let fetched = try database.writer.read { db in
            try LocalEditorDraftRecord.fetchOne(db, key: ["context_key": "blog:new"])
        }

        XCTAssertEqual(fetched?.visibility, "followers")
        XCTAssertEqual(fetched?.title, "Hello")
    }
}
