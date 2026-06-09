import Foundation
import GRDB

public struct AppDatabase {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public static func openDefault() throws -> AppDatabase {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = directory.appending(path: "atoman-studio.sqlite")
        let queue = try DatabaseQueue(path: url.path)
        try migrator.migrate(queue)
        return AppDatabase(writer: queue)
    }

    public static func inMemory() throws -> AppDatabase {
        let queue = try DatabaseQueue()
        try migrator.migrate(queue)
        return AppDatabase(writer: queue)
    }

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create_local_editor_drafts") { db in
            try db.create(table: "local_editor_drafts") { t in
                t.column("context_key", .text).notNull().primaryKey()
                t.column("source_post_id", .text)
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("cover_url", .text).notNull()
                t.column("visibility", .text).notNull()
                t.column("allow_comments", .boolean).notNull()
                t.column("channel_id", .text)
                t.column("collection_ids_json", .text).notNull()
                t.column("saved_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("create_pending_sync_records") { db in
            try db.create(table: "pending_sync_records") { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("context_key", .text).notNull().indexed()
                t.column("payload_json", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }
        }
        return migrator
    }
}
