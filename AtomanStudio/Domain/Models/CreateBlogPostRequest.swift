import Foundation

public struct CreateBlogPostRequest: Encodable {
    public let title: String
    public let content: String
    public let summary: String
    public let coverURL: String
    public let visibility: BlogVisibility
    public let allowComments: Bool
    public let status: String
    public let channelID: String?
    public let collectionIDs: [String]

    public init(
        title: String,
        content: String,
        summary: String,
        coverURL: String,
        visibility: BlogVisibility,
        allowComments: Bool,
        status: String,
        channelID: String?,
        collectionIDs: [String]
    ) {
        self.title = title
        self.content = content
        self.summary = summary
        self.coverURL = coverURL
        self.visibility = visibility
        self.allowComments = allowComments
        self.status = status
        self.channelID = channelID
        self.collectionIDs = collectionIDs
    }

    enum CodingKeys: String, CodingKey {
        case title
        case content
        case summary
        case coverURL = "cover_url"
        case visibility
        case allowComments = "allow_comments"
        case status
        case channelID = "channel_id"
        case collectionIDs = "collection_ids"
    }
}
