import Foundation

public extension JSONDecoder {
    static var feed: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum FeedTimelineFilter: String, CaseIterable, Identifiable, Equatable {
    case all
    case unread
    case starred

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "全部"
        case .unread: "未读"
        case .starred: "星标"
        }
    }
}

public struct FeedTimelinePage: Decodable, Equatable {
    public let items: [FeedTimelineItem]
    public let total: Int
    public let page: Int
    public let limit: Int

    private enum CodingKeys: String, CodingKey { case data, meta, total, page, limit }

    private struct Meta: Decodable {
        let page: Int
        let pageSize: Int
        let total: Int

        private enum CodingKeys: String, CodingKey {
            case page
            case pageSize = "page_size"
            case total
        }
    }

    public init(items: [FeedTimelineItem], total: Int, page: Int, limit: Int) {
        self.items = items
        self.total = total
        self.page = page
        self.limit = limit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payloads = try container.decode([FeedTimelineItemPayload].self, forKey: .data)
        items = payloads.compactMap(FeedTimelineItem.init(payload:))
        let meta = try container.decodeIfPresent(Meta.self, forKey: .meta)
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? meta?.total ?? payloads.count
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? meta?.page ?? 1
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? meta?.pageSize ?? payloads.count
    }
}

private struct FeedTimelineItemPayload: Decodable {
    let type: String
    let feedItem: FeedItem?
    let publishedAt: Date
    let isRead: Bool

    private enum CodingKeys: String, CodingKey {
        case type
        case feedItem = "feed_item"
        case publishedAt = "published_at"
        case isRead = "is_read"
    }
}

public struct FeedTimelineItem: Identifiable, Equatable {
    public let feedItem: FeedItem
    public var isRead: Bool
    public var isStarred: Bool
    public let publishedAt: Date

    public var id: String { feedItem.id }
    public var displayTitle: String { feedItem.title.isEmpty ? "未命名条目" : feedItem.title }
    public var summary: String { feedItem.summary }
    public var sourceTitle: String { feedItem.sourceTitle }
    public var link: String { feedItem.link }

    public init(feedItem: FeedItem, isRead: Bool, isStarred: Bool = false, publishedAt: Date) {
        self.feedItem = feedItem
        self.isRead = isRead
        self.isStarred = isStarred
        self.publishedAt = publishedAt
    }

    fileprivate init?(payload: FeedTimelineItemPayload) {
        guard payload.type == "feed_item", let feedItem = payload.feedItem else { return nil }
        self.init(feedItem: feedItem, isRead: payload.isRead, publishedAt: payload.publishedAt)
    }
}

public struct FeedItem: Codable, Identifiable, Equatable {
    public let id: String
    public let feedSourceID: String
    public let guid: String
    public let title: String
    public let link: String
    public let summary: String
    public let author: String
    public let publishedAt: Date
    public let fetchedAt: Date?
    public let imageURL: String?
    public let fullTextHTML: String?
    public let feedSource: FeedSource?
    public let sourceTitleOverride: String?

    public var sourceTitle: String {
        if let sourceTitleOverride, !sourceTitleOverride.isEmpty { return sourceTitleOverride }
        if let title = feedSource?.title, !title.isEmpty { return title }
        return author.isEmpty ? "未知来源" : author
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case feedSourceID = "feed_source_id"
        case guid, title, link, summary, author
        case publishedAt = "published_at"
        case fetchedAt = "fetched_at"
        case imageURL = "image_url"
        case fullTextHTML = "full_text_html"
        case feedSource = "feed_source"
        case sourceTitleOverride = "source_title"
    }
}

public struct FeedSource: Codable, Identifiable, Equatable {
    public let id: String
    public let sourceType: String
    public let rssURL: String
    public let siteURL: String?
    public let title: String
    public let healthStatus: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceType = "source_type"
        case rssURL = "rss_url"
        case siteURL = "site_url"
        case title
        case healthStatus = "health_status"
    }
}

public struct FeedStarredPage: Decodable, Equatable {
    public let items: [FeedItem]
    public let page: Int
    public let total: Int
}

public struct FeedStarToggleResponse: Decodable, Equatable {
    public let starred: Bool
}
