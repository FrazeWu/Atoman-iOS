import AtomanCore
import Foundation

public protocol FeedServicing {
    func fetchTimeline(filter: FeedTimelineFilter, page: Int, pageSize: Int) async throws -> FeedTimelinePage
    func markRead(itemIDs: [String]) async throws
    func toggleStar(feedItemID: String) async throws -> Bool
}

public struct FeedAPI: FeedServicing {
    public let client: APIClient
    public let authSession: AuthSessionStore

    public init(client: APIClient, authSession: AuthSessionStore) {
        self.client = client
        self.authSession = authSession
    }

    public func fetchTimeline(filter: FeedTimelineFilter, page: Int = 1, pageSize: Int = 20) async throws -> FeedTimelinePage {
        if filter == .starred {
            return try await fetchStarred(page: page, pageSize: pageSize)
        }

        var queryItems = [
            URLQueryItem(name: "hide_duplicates", value: "true"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]
        if filter == .unread {
            queryItems.append(URLQueryItem(name: "is_read", value: "false"))
        }
        let (data, response) = try await client.request(
            path: "feed/timeline",
            token: authSession.token,
            queryItems: queryItems
        )
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder.feed.decode(FeedTimelinePage.self, from: data)
    }

    public func markRead(itemIDs: [String]) async throws {
        let body = try JSONEncoder().encode(MarkReadRequest(feedItemIDs: itemIDs))
        let (_, response) = try await client.request(
            path: "feed/timeline/mark-read",
            method: "POST",
            token: authSession.token,
            body: body
        )
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    public func toggleStar(feedItemID: String) async throws -> Bool {
        let body = try JSONEncoder().encode(StarRequest(feedItemID: feedItemID))
        let (data, response) = try await client.request(
            path: "feed/timeline/star",
            method: "POST",
            token: authSession.token,
            body: body
        )
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(FeedStarToggleResponse.self, from: data).starred
    }

    private func fetchStarred(page: Int, pageSize: Int) async throws -> FeedTimelinePage {
        let queryItems = [
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        let (data, response) = try await client.request(
            path: "feed/stars",
            token: authSession.token,
            queryItems: queryItems
        )
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        let starredPage = try JSONDecoder.feed.decode(FeedStarredPage.self, from: data)
        let items = starredPage.items.map { item in
            FeedTimelineItem(feedItem: item, isRead: true, isStarred: true, publishedAt: item.publishedAt)
        }
        return FeedTimelinePage(items: items, total: starredPage.total, page: starredPage.page, limit: pageSize)
    }
}

private struct MarkReadRequest: Encodable {
    let feedItemIDs: [String]

    enum CodingKeys: String, CodingKey {
        case feedItemIDs = "feed_item_ids"
    }
}

private struct StarRequest: Encodable {
    let feedItemID: String

    enum CodingKeys: String, CodingKey {
        case feedItemID = "feed_item_id"
    }
}
