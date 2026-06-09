import Foundation

public struct EditorDraftPayload: Codable, Equatable {
    public let contextKey: String
    public let sourcePostID: String?
    public var title: String
    public var content: String
    public var summary: String
    public var coverURL: String
    public var visibility: BlogVisibility
    public var allowComments: Bool
    public var channelID: String?
    public var collectionIDs: [String]

    public init(
        contextKey: String,
        sourcePostID: String?,
        title: String,
        content: String,
        summary: String,
        coverURL: String,
        visibility: BlogVisibility,
        allowComments: Bool,
        channelID: String?,
        collectionIDs: [String]
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
        self.collectionIDs = collectionIDs
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
        case collectionIDs = "collection_ids"
    }
}

public extension EditorDraftPayload {
    static func fixture(title: String = "Draft") -> EditorDraftPayload {
        EditorDraftPayload(
            contextKey: "blog:new",
            sourcePostID: nil,
            title: title,
            content: "Body",
            summary: "",
            coverURL: "",
            visibility: .public,
            allowComments: true,
            channelID: nil,
            collectionIDs: []
        )
    }
}
