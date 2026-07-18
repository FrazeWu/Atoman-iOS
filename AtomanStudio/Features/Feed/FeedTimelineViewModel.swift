import Foundation
import Observation

@MainActor
@Observable
public final class FeedTimelineViewModel {
    public var items: [FeedTimelineItem] = []
    public var selectedFilter: FeedTimelineFilter = .all
    public var isLoading = false
    public var isLoadingMore = false
    public var errorMessage: String?
    public private(set) var currentPage = 1
    public private(set) var canLoadMore = true

    private let feedService: FeedServicing
    private let pageSize: Int

    public init(feedService: FeedServicing, pageSize: Int = 20) {
        self.feedService = feedService
        self.pageSize = pageSize
    }

    public func loadInitial() async {
        currentPage = 1
        canLoadMore = true
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await feedService.fetchTimeline(filter: selectedFilter, page: 1, pageSize: pageSize)
            items = page.items
            canLoadMore = page.items.count < page.total
            errorMessage = nil
        } catch {
            items = []
            canLoadMore = false
            errorMessage = "加载订阅失败"
        }
    }

    public func selectFilter(_ filter: FeedTimelineFilter) async {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        await loadInitial()
    }

    public func loadMoreIfNeeded(currentItemID: String?) async {
        guard canLoadMore, !isLoadingMore, currentItemID == items.last?.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = currentPage + 1
            let page = try await feedService.fetchTimeline(filter: selectedFilter, page: nextPage, pageSize: pageSize)
            currentPage = nextPage
            items.append(contentsOf: page.items)
            canLoadMore = items.count < page.total
            errorMessage = nil
        } catch {
            errorMessage = "加载更多失败"
        }
    }

    public func markReadAfterOpening(itemID: String) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }), !items[index].isRead else { return }
        do {
            try await feedService.markRead(itemIDs: [itemID])
            items[index].isRead = true
            errorMessage = nil
        } catch {
            errorMessage = "标记已读失败"
        }
    }

    public func toggleStar(itemID: String) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        do {
            let starred = try await feedService.toggleStar(feedItemID: itemID)
            items[index].isStarred = starred
            errorMessage = nil
        } catch {
            errorMessage = "星标失败"
        }
    }
}
