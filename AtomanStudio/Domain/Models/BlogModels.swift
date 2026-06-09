import Foundation

public enum BlogVisibility: String, Codable, CaseIterable {
    case `public`
    case followers
    case `private`
}

public struct BlogChannel: Codable, Equatable, Identifiable {
    public let id: String
    public let userID: String
    public let name: String
    public let slug: String
    public let description: String?
    public let coverURL: String?
    public let isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case slug
        case description
        case coverURL = "cover_url"
        case isDefault = "is_default"
    }
}

public struct BlogCollection: Codable, Equatable, Identifiable {
    public let id: String
    public let channelID: String
    public let name: String
    public let isDefault: Bool?
    public let description: String?
    public let coverURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case channelID = "channel_id"
        case name
        case isDefault = "is_default"
        case description
        case coverURL = "cover_url"
    }
}

public struct BlogPost: Codable, Equatable, Identifiable {
    public let id: String
    public let userID: String
    public let channelID: String?
    public let title: String
    public let content: String
    public let summary: String?
    public let coverURL: String?
    public let status: String
    public let visibility: BlogVisibility
    public let allowComments: Bool
    public let collections: [BlogCollection]?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case channelID = "channel_id"
        case title
        case content
        case summary
        case coverURL = "cover_url"
        case status
        case visibility
        case allowComments = "allow_comments"
        case collections
    }
}

public struct APIEnvelope<T: Decodable>: Decodable {
    public let data: T
}
