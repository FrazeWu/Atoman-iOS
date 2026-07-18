import XCTest
@testable import AtomanStudio

@MainActor
final class FeedTimelineViewModelTests: XCTestCase {
    func testLoadInitialStoresItemsAndUnreadFilter() async {
        let service = FeedServiceMock()
        service.pages[.all] = FeedTimelinePage(items: [makeItem(isRead: false)], total: 1, page: 1, limit: 20)
        let viewModel = FeedTimelineViewModel(feedService: service)

        await viewModel.loadInitial()

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertFalse(viewModel.items[0].isRead)
        XCTAssertEqual(service.fetchCalls.first?.filter, .all)
    }

    func testOpeningUnreadItemMarksItReadAfterServerSuccess() async {
        let service = FeedServiceMock()
        let viewModel = FeedTimelineViewModel(feedService: service)
        viewModel.items = [makeItem(isRead: false)]

        await viewModel.markReadAfterOpening(itemID: "item-1")

        XCTAssertTrue(viewModel.items[0].isRead)
        XCTAssertEqual(service.markReadIDs, [["item-1"]])
    }

    func testToggleStarUpdatesLocalState() async {
        let service = FeedServiceMock()
        service.starredResult = true
        let viewModel = FeedTimelineViewModel(feedService: service)
        viewModel.items = [makeItem(isRead: true)]

        await viewModel.toggleStar(itemID: "item-1")

        XCTAssertTrue(viewModel.items[0].isStarred)
        XCTAssertEqual(service.starIDs, ["item-1"])
    }

    private func makeItem(isRead: Bool) -> FeedTimelineItem {
        let source = FeedSource(
            id: "source-1",
            sourceType: "external_rss",
            rssURL: "https://example.com/feed.xml",
            siteURL: "https://example.com",
            title: "Example Feed",
            healthStatus: "healthy"
        )
        let item = FeedItem(
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
            feedSource: source,
            sourceTitleOverride: nil
        )
        return FeedTimelineItem(feedItem: item, isRead: isRead, publishedAt: item.publishedAt)
    }
}

private final class FeedServiceMock: FeedServicing {
    var pages: [FeedTimelineFilter: FeedTimelinePage] = [:]
    var fetchCalls: [(filter: FeedTimelineFilter, page: Int, pageSize: Int)] = []
    var markReadIDs: [[String]] = []
    var starIDs: [String] = []
    var starredResult = false

    func fetchTimeline(filter: FeedTimelineFilter, page: Int, pageSize: Int) async throws -> FeedTimelinePage {
        fetchCalls.append((filter, page, pageSize))
        return pages[filter] ?? FeedTimelinePage(items: [], total: 0, page: page, limit: pageSize)
    }

    func markRead(itemIDs: [String]) async throws {
        markReadIDs.append(itemIDs)
    }

    func toggleStar(feedItemID: String) async throws -> Bool {
        starIDs.append(feedItemID)
        return starredResult
    }
}
