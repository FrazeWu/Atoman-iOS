import SwiftUI
import XCTest
@testable import AtomanStudio

final class AppSmokeTests: XCTestCase {
    func testEnvironmentCanBootInMemory() throws {
        let database = try AppDatabase.inMemory()
        let authSession = AuthSessionStore(token: nil)
        let apiClient = APIClient(baseURL: URL(string: "https://example.com/api")!)
        let blogAPI = BlogAPI(client: apiClient, authSession: authSession)
        let feedAPI = FeedAPI(client: apiClient, authSession: authSession)
        let env = AppEnvironment(apiClient: apiClient, blogAPI: blogAPI, feedAPI: feedAPI, authSession: authSession, database: database)

        XCTAssertNotNil(env)
    }

    @MainActor
    func testRootAppViewCanBeCreated() throws {
        let view = RootAppView()

        XCTAssertNotNil(view)
    }

    @MainActor
    func testMainTabViewCanBeCreatedWithEnvironment() throws {
        let database = try AppDatabase.inMemory()
        let authSession = AuthSessionStore(token: nil)
        let apiClient = APIClient(baseURL: URL(string: "https://example.com/api")!)
        let blogAPI = BlogAPI(client: apiClient, authSession: authSession)
        let feedAPI = FeedAPI(client: apiClient, authSession: authSession)
        let env = AppEnvironment(apiClient: apiClient, blogAPI: blogAPI, feedAPI: feedAPI, authSession: authSession, database: database)
        let view = MainTabView(environment: env)

        XCTAssertNotNil(view)
    }

    @MainActor
    func testFeedViewsCanBeCreated() throws {
        let item = FeedTimelineItem(
            feedItem: FeedItem(
                id: "item-1",
                feedSourceID: "source-1",
                guid: "guid-1",
                title: "Article",
                link: "https://example.com/article",
                summary: "Summary",
                author: "Author",
                publishedAt: Date(timeIntervalSince1970: 1_786_000_000),
                fetchedAt: nil,
                imageURL: nil,
                fullTextHTML: nil,
                feedSource: nil,
                sourceTitleOverride: "Example Feed"
            ),
            isRead: false,
            publishedAt: Date(timeIntervalSince1970: 1_786_000_000)
        )
        let viewModel = FeedTimelineViewModel(feedService: FeedServiceSmokeMock())

        XCTAssertNotNil(FeedTimelineView(viewModel: viewModel))
        XCTAssertNotNil(FeedArticleDetailView(item: item, onToggleStar: {}, onMarkRead: {}))
    }
}

private struct FeedServiceSmokeMock: FeedServicing {
    func fetchTimeline(filter: FeedTimelineFilter, page: Int, pageSize: Int) async throws -> FeedTimelinePage {
        FeedTimelinePage(items: [], total: 0, page: page, limit: pageSize)
    }

    func markRead(itemIDs: [String]) async throws {}

    func toggleStar(feedItemID: String) async throws -> Bool { false }
}
