import Foundation
import GRDB

public struct PendingSyncRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    public static let databaseTableName = "pending_sync_records"

    public var id: String
    public var contextKey: String
    public var payloadJSON: String
    public var createdAt: Date

    public init(id: String, contextKey: String, payloadJSON: String, createdAt: Date) {
        self.id = id
        self.contextKey = contextKey
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case contextKey = "context_key"
        case payloadJSON = "payload_json"
        case createdAt = "created_at"
    }

    public enum Columns: String, ColumnExpression {
        case id
        case contextKey = "context_key"
        case payloadJSON = "payload_json"
        case createdAt = "created_at"
    }
}
