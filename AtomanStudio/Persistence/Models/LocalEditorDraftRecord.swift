import Foundation
import GRDB

public struct LocalEditorDraftRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    public static let databaseTableName = "local_editor_drafts"

    public var contextKey: String
    public var sourcePostID: String?
    public var title: String
    public var content: String
    public var summary: String
    public var coverURL: String
    public var visibility: String
    public var allowComments: Bool
    public var channelID: String?
    public var collectionIDsJSON: String
    public var savedAt: Date

    public init(
        contextKey: String,
        sourcePostID: String?,
        title: String,
        content: String,
        summary: String,
        coverURL: String,
        visibility: String,
        allowComments: Bool,
        channelID: String?,
        collectionIDsJSON: String,
        savedAt: Date
    ) {
        self.contextKey = contextKey
        self.sourcePostID = sourcePostID
        self.title = title
        self.content = content
        self.summary = summary
        self.coverURL = coverURL
        self.visibility = visibility
        self.allowComments = allowComments
        self.channelID = channelID
        self.collectionIDsJSON = collectionIDsJSON
        self.savedAt = savedAt
    }

    enum CodingKeys: String, CodingKey {
        case contextKey = "context_key"
        case sourcePostID = "source_post_id"
        case title
        case content
        case summary
        case coverURL = "cover_url"
        case visibility
        case allowComments = "allow_comments"
        case channelID = "channel_id"
        case collectionIDsJSON = "collection_ids_json"
        case savedAt = "saved_at"
    }

    public enum Columns: String, ColumnExpression {
        case contextKey = "context_key"
        case sourcePostID = "source_post_id"
        case title
        case content
        case summary
        case coverURL = "cover_url"
        case visibility
        case allowComments = "allow_comments"
        case channelID = "channel_id"
        case collectionIDsJSON = "collection_ids_json"
        case savedAt = "saved_at"
    }
}
