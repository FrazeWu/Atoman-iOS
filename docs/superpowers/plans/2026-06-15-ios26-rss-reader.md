# iOS 26 RSS Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first iOS RSS reader experience: a Creator Studio “订阅” tab with Today Flow timeline, detail reading, read state, star state, and `/api/v1` backend integration.

**Architecture:** Add a focused Feed feature slice beside existing Blog/Auth/Channel code. Keep networking in `FeedAPI`, DTOs in `Domain/Models`, UI state in `FeedTimelineViewModel`, and SwiftUI screens in `Features/Feed`. Switch the live base URL to `/api/v1` once, then keep endpoint paths relative.

**Tech Stack:** Swift 5.10, SwiftUI, Observation, XCTest, URLSession, existing `APIClient`, existing `AuthSessionStore`, backend `/api/v1/feed` endpoints.

---

## Scope and file map

### Create

- `AtomanStudio/Domain/Models/FeedModels.swift`  
  Feed DTOs, timeline filters, page envelopes, star response models, and safe derived display helpers.

- `AtomanStudio/Infrastructure/API/FeedAPI.swift`  
  Feed networking wrapper using the existing `APIClient` and `AuthSessionStore`.

- `AtomanStudio/Features/Feed/FeedTimelineViewModel.swift`  
  Observable state and actions for loading timeline pages, switching filters, marking read, and toggling stars.

- `AtomanStudio/Features/Feed/FeedTimelineView.swift`  
  Creator Studio Today Flow tab UI.

- `AtomanStudio/Features/Feed/FeedArticleDetailView.swift`  
  Detail reading screen for a feed item.

- `AtomanStudioTests/FeedModelsTests.swift`  
  JSON decoding coverage for timeline and starred responses.

- `AtomanStudioTests/FeedAPITests.swift`  
  URL construction and response handling tests using an in-memory `URLProtocol` mock.

- `AtomanStudioTests/FeedTimelineViewModelTests.swift`  
  View model behavior tests using a mock feed service.

### Modify

- `AtomanStudio/App/AppEnvironment.swift`  
  Add `feedAPI` and change live base URL to `http://localhost:8080/api/v1`.

- `AtomanStudio/App/RootAppView.swift`  
  Add a fourth “订阅” tab wrapped in `AuthenticationGateView`.

- `AtomanStudio/Infrastructure/API/APIClient.swift`  
  Add query-safe request construction if needed for `feed/timeline?page=...` and preserve existing behavior.

- `AtomanStudioTests/AppSmokeTests.swift`  
  Update environment setup for `FeedAPI`.

- Existing tests that instantiate `AppEnvironment` directly  
  Add `feedAPI` argument where required.

---

## Task 1: Feed models and decoding

**Files:**
- Create: `AtomanStudio/Domain/Models/FeedModels.swift`
- Test: `AtomanStudioTests/FeedModelsTests.swift`

- [ ] **Step 1: Write failing model decoding tests**

Create `AtomanStudioTests/FeedModelsTests.swift`:

```swift
import XCTest
@testable import AtomanStudio

final class FeedModelsTests: XCTestCase {
    func testTimelineDecodesFeedItemEnvelope() throws {
        let json = """
        {
          "data": [
            {
              "type": "feed_item",
              "published_at": "2026-06-15T08:30:00Z",
              "is_read": false,
              "feed_item": {
                "id": "item-1",
                "feed_source_id": "source-1",
                "guid": "guid-1",
                "title": "A modern RSS reader",
                "link": "https://example.com/post",
                "summary": "Short summary",
                "author": "Author",
                "published_at": "2026-06-15T08:30:00Z",
                "fetched_at": "2026-06-15T08:31:00Z",
                "image_url": "https://example.com/image.png",
                "feed_source": {
                  "id": "source-1",
                  "source_type": "external_rss",
                  "rss_url": "https://example.com/feed.xml",
                  "site_url": "https://example.com",
                  "title": "Example Feed",
                  "health_status": "healthy"
                }
              }
            }
          ],
          "total": 1,
          "page": 1,
          "limit": 20,
          "message": "ok"
        }
        """.data(using: .utf8)!

        let page = try JSONDecoder.feed.decode(FeedTimelinePage.self, from: json)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.items[0].id, "item-1")
        XCTAssertEqual(page.items[0].displayTitle, "A modern RSS reader")
        XCTAssertEqual(page.items[0].sourceTitle, "Example Feed")
        XCTAssertFalse(page.items[0].isRead)
    }

    func testTimelineSkipsUnsupportedPostItemsForFirstRelease() throws {
        let json = """
        {
          "data": [
            {
              "type": "post",
              "published_at": "2026-06-15T08:30:00Z",
              "is_read": false,
              "post": {"id":"post-1","user_id":"user-1","title":"Blog","content":"Body","status":"published","visibility":"public","allow_comments":true}
            }
          ],
          "total": 1,
          "page": 1,
          "limit": 20,
          "message": "ok"
        }
        """.data(using: .utf8)!

        let page = try JSONDecoder.feed.decode(FeedTimelinePage.self, from: json)

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.total, 1)
    }

    func testStarredItemsResponseDecodesLegacyShape() throws {
        let json = """
        {
          "items": [
            {
              "id": "item-2",
              "feed_source_id": "source-2",
              "guid": "guid-2",
              "title": "Saved article",
              "link": "https://example.com/saved",
              "summary": "Saved summary",
              "author": "Writer",
              "published_at": "2026-06-15T09:00:00Z",
              "fetched_at": "2026-06-15T09:01:00Z",
              "source_title": "Saved Feed"
            }
          ],
          "page": 1,
          "total": 1
        }
        """.data(using: .utf8)!

        let page = try JSONDecoder.feed.decode(FeedStarredPage.self, from: json)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].id, "item-2")
        XCTAssertEqual(page.items[0].sourceTitle, "Saved Feed")
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter FeedModelsTests
```

Expected: compile failure because `FeedTimelinePage`, `FeedStarredPage`, and `JSONDecoder.feed` do not exist.

- [ ] **Step 3: Implement feed models**

Create `AtomanStudio/Domain/Models/FeedModels.swift`:

```swift
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

    enum CodingKeys: String, CodingKey {
        case data
        case total
        case page
        case limit
    }

    public init(items: [FeedTimelineItem], total: Int, page: Int, limit: Int) {
        self.items = items
        self.total = total
        self.page = page
        self.limit = limit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawItems = try container.decode([FeedTimelineItemPayload].self, forKey: .data)
        self.items = rawItems.compactMap(FeedTimelineItem.init(payload:))
        self.total = try container.decode(Int.self, forKey: .total)
        self.page = try container.decode(Int.self, forKey: .page)
        self.limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? rawItems.count
    }
}

private struct FeedTimelineItemPayload: Decodable {
    let type: String
    let feedItem: FeedItem?
    let publishedAt: Date
    let isRead: Bool

    enum CodingKeys: String, CodingKey {
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

    enum CodingKeys: String, CodingKey {
        case id
        case feedSourceID = "feed_source_id"
        case guid
        case title
        case link
        case summary
        case author
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

    enum CodingKeys: String, CodingKey {
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
```

- [ ] **Step 4: Run model tests and verify pass**

Run:

```bash
swift test --filter FeedModelsTests
```

Expected: all `FeedModelsTests` pass.

- [ ] **Step 5: Commit**

```bash
git add AtomanStudio/Domain/Models/FeedModels.swift AtomanStudioTests/FeedModelsTests.swift
git commit -m "feat: add feed timeline models"
```

---

## Task 2: API client query support and FeedAPI

**Files:**
- Modify: `AtomanStudio/Infrastructure/API/APIClient.swift`
- Create: `AtomanStudio/Infrastructure/API/FeedAPI.swift`
- Test: `AtomanStudioTests/FeedAPITests.swift`

- [ ] **Step 1: Write failing API tests**

Create `AtomanStudioTests/FeedAPITests.swift`:

```swift
import Foundation
import XCTest
@testable import AtomanStudio

final class FeedAPITests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testFetchTimelineBuildsUnreadTimelineRequest() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/feed/timeline?hide_duplicates=true&is_read=false&page=2&page_size=10")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            let data = """{"data":[],"total":0,"page":2,"limit":10,"message":"ok"}""".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let page = try await api.fetchTimeline(filter: .unread, page: 2, pageSize: 10)

        XCTAssertEqual(page.page, 2)
        XCTAssertTrue(page.items.isEmpty)
    }

    func testFetchStarredUsesStarsEndpoint() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/feed/stars?page=1&limit=20")
            let data = """{"items":[],"page":1,"total":0}""".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let page = try await api.fetchTimeline(filter: .starred, page: 1, pageSize: 20)

        XCTAssertEqual(page.total, 0)
    }

    func testMarkReadPostsFeedItemIDs() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/feed/timeline/mark-read")
            XCTAssertEqual(request.httpMethod, "POST")
            let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: [String]]
            XCTAssertEqual(json?["feed_item_ids"], ["item-1"])
            let data = """{"message":"ok"}""".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        try await api.markRead(itemIDs: ["item-1"])
    }

    func testToggleStarReturnsStarredState() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/feed/timeline/star")
            XCTAssertEqual(request.httpMethod, "POST")
            let data = """{"starred":true,"message":"Item starred"}""".data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let starred = try await api.toggleStar(feedItemID: "item-1")

        XCTAssertTrue(starred)
    }

    private func makeAPI(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> FeedAPI {
        URLProtocolStub.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(baseURL: URL(string: "https://example.com/api/v1")!, session: session)
        return FeedAPI(client: client, authSession: AuthSessionStore(token: "token-1"))
    }
}

final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter FeedAPITests
```

Expected: compile failure because `FeedAPI` does not exist and `APIClient` cannot build query items.

- [ ] **Step 3: Add query support to APIClient**

Modify `AtomanStudio/Infrastructure/API/APIClient.swift` so `request` accepts query items while preserving all existing call sites:

```swift
public func request(
    path: String,
    method: String = "GET",
    token: String? = nil,
    body: Data? = nil,
    contentType: String? = "application/json",
    queryItems: [URLQueryItem] = []
) async throws -> (Data, HTTPURLResponse) {
    let url = makeURL(path: path, queryItems: queryItems)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    if let token {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if let contentType {
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    return (data, http)
}

private func makeURL(path: String, queryItems: [URLQueryItem]) -> URL {
    let base = baseURL.appending(path: path)
    guard !queryItems.isEmpty, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
        return base
    }
    components.queryItems = queryItems.sorted { $0.name < $1.name }
    return components.url ?? base
}
```

Keep the existing imports and struct members.

- [ ] **Step 4: Implement FeedAPI**

Create `AtomanStudio/Infrastructure/API/FeedAPI.swift`:

```swift
import Foundation

public struct FeedAPI {
    public let client: APIClient
    public let authSession: AuthSessionStore

    public init(client: APIClient, authSession: AuthSessionStore) {
        self.client = client
        self.authSession = authSession
    }

    public func fetchTimeline(filter: FeedTimelineFilter, page: Int = 1, pageSize: Int = 20) async throws -> FeedTimelinePage {
        switch filter {
        case .starred:
            return try await fetchStarred(page: page, pageSize: pageSize)
        case .all, .unread:
            var queryItems = [
                URLQueryItem(name: "hide_duplicates", value: "true"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: String(pageSize)),
            ]
            if filter == .unread {
                queryItems.append(URLQueryItem(name: "is_read", value: "false"))
            }
            let (data, response) = try await client.request(path: "feed/timeline", token: authSession.token, queryItems: queryItems)
            guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
            return try JSONDecoder.feed.decode(FeedTimelinePage.self, from: data)
        }
    }

    public func markRead(itemIDs: [String]) async throws {
        let body = try JSONEncoder().encode(MarkReadRequest(feedItemIDs: itemIDs))
        let (_, response) = try await client.request(path: "feed/timeline/mark-read", method: "POST", token: authSession.token, body: body)
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    public func toggleStar(feedItemID: String) async throws -> Bool {
        let body = try JSONEncoder().encode(StarRequest(feedItemID: feedItemID))
        let (data, response) = try await client.request(path: "feed/timeline/star", method: "POST", token: authSession.token, body: body)
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(FeedStarToggleResponse.self, from: data).starred
    }

    private func fetchStarred(page: Int, pageSize: Int) async throws -> FeedTimelinePage {
        let queryItems = [
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        let (data, response) = try await client.request(path: "feed/stars", token: authSession.token, queryItems: queryItems)
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
```

- [ ] **Step 5: Run API tests and existing blog tests**

Run:

```bash
swift test --filter FeedAPITests
swift test --filter BlogAPITests
```

Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add AtomanStudio/Infrastructure/API/APIClient.swift AtomanStudio/Infrastructure/API/FeedAPI.swift AtomanStudioTests/FeedAPITests.swift
git commit -m "feat: add feed api client"
```

---

## Task 3: FeedTimelineViewModel

**Files:**
- Create: `AtomanStudio/Features/Feed/FeedTimelineViewModel.swift`
- Test: `AtomanStudioTests/FeedTimelineViewModelTests.swift`
- Modify: `AtomanStudio/Infrastructure/API/FeedAPI.swift`

- [ ] **Step 1: Introduce a protocol seam for testability**

Modify `AtomanStudio/Infrastructure/API/FeedAPI.swift` above `public struct FeedAPI`:

```swift
public protocol FeedServicing {
    func fetchTimeline(filter: FeedTimelineFilter, page: Int, pageSize: Int) async throws -> FeedTimelinePage
    func markRead(itemIDs: [String]) async throws
    func toggleStar(feedItemID: String) async throws -> Bool
}
```

Then make the struct conform:

```swift
public struct FeedAPI: FeedServicing {
```

- [ ] **Step 2: Write failing view model tests**

Create `AtomanStudioTests/FeedTimelineViewModelTests.swift`:

```swift
import XCTest
@testable import AtomanStudio

@MainActor
final class FeedTimelineViewModelTests: XCTestCase {
    func testLoadInitialTimelinePopulatesItems() async {
        let service = FeedServiceMock()
        service.pages[.all] = FeedTimelinePage(items: [Self.item(id: "item-1", title: "First")], total: 1, page: 1, limit: 20)
        let vm = FeedTimelineViewModel(feedService: service)

        await vm.loadInitial()

        XCTAssertEqual(vm.items.map(\.id), ["item-1"])
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func testChangingFilterReloadsFromFirstPage() async {
        let service = FeedServiceMock()
        service.pages[.unread] = FeedTimelinePage(items: [Self.item(id: "item-2", title: "Unread")], total: 1, page: 1, limit: 20)
        let vm = FeedTimelineViewModel(feedService: service)

        await vm.selectFilter(.unread)

        XCTAssertEqual(vm.selectedFilter, .unread)
        XCTAssertEqual(vm.items.map(\.id), ["item-2"])
        XCTAssertEqual(service.fetchCalls.last?.page, 1)
    }

    func testOpenItemMarksReadAfterSuccessfulRequest() async {
        let service = FeedServiceMock()
        let vm = FeedTimelineViewModel(feedService: service)
        vm.items = [Self.item(id: "item-1", title: "First", isRead: false)]

        await vm.markReadAfterOpening(itemID: "item-1")

        XCTAssertTrue(vm.items[0].isRead)
        XCTAssertEqual(service.markReadIDs, [["item-1"]])
    }

    func testOpenItemDoesNotMarkReadWhenRequestFails() async {
        let service = FeedServiceMock()
        service.markReadError = URLError(.badServerResponse)
        let vm = FeedTimelineViewModel(feedService: service)
        vm.items = [Self.item(id: "item-1", title: "First", isRead: false)]

        await vm.markReadAfterOpening(itemID: "item-1")

        XCTAssertFalse(vm.items[0].isRead)
        XCTAssertEqual(vm.errorMessage, "标记已读失败")
    }

    func testToggleStarUpdatesStateFromServerResponse() async {
        let service = FeedServiceMock()
        service.starredResult = true
        let vm = FeedTimelineViewModel(feedService: service)
        vm.items = [Self.item(id: "item-1", title: "First", isStarred: false)]

        await vm.toggleStar(itemID: "item-1")

        XCTAssertTrue(vm.items[0].isStarred)
        XCTAssertEqual(service.starIDs, ["item-1"])
    }

    private static func item(id: String, title: String, isRead: Bool = false, isStarred: Bool = false) -> FeedTimelineItem {
        FeedTimelineItem(
            feedItem: FeedItem(
                id: id,
                feedSourceID: "source-1",
                guid: id,
                title: title,
                link: "https://example.com/\(id)",
                summary: "Summary",
                author: "Author",
                publishedAt: Date(timeIntervalSince1970: 1_786_000_000),
                fetchedAt: nil,
                imageURL: nil,
                fullTextHTML: nil,
                feedSource: FeedSource(id: "source-1", sourceType: "external_rss", rssURL: "https://example.com/feed.xml", siteURL: nil, title: "Example", healthStatus: "healthy"),
                sourceTitleOverride: nil
            ),
            isRead: isRead,
            isStarred: isStarred,
            publishedAt: Date(timeIntervalSince1970: 1_786_000_000)
        )
    }
}

final class FeedServiceMock: FeedServicing {
    var pages: [FeedTimelineFilter: FeedTimelinePage] = [:]
    var fetchCalls: [(filter: FeedTimelineFilter, page: Int, pageSize: Int)] = []
    var markReadIDs: [[String]] = []
    var markReadError: Error?
    var starIDs: [String] = []
    var starredResult = false

    func fetchTimeline(filter: FeedTimelineFilter, page: Int, pageSize: Int) async throws -> FeedTimelinePage {
        fetchCalls.append((filter, page, pageSize))
        return pages[filter] ?? FeedTimelinePage(items: [], total: 0, page: page, limit: pageSize)
    }

    func markRead(itemIDs: [String]) async throws {
        if let markReadError { throw markReadError }
        markReadIDs.append(itemIDs)
    }

    func toggleStar(feedItemID: String) async throws -> Bool {
        starIDs.append(feedItemID)
        return starredResult
    }
}
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
swift test --filter FeedTimelineViewModelTests
```

Expected: compile failure because `FeedTimelineViewModel` does not exist.

- [ ] **Step 4: Implement view model**

Create `AtomanStudio/Features/Feed/FeedTimelineViewModel.swift`:

```swift
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
    public var currentPage = 1
    public var canLoadMore = true

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
```

- [ ] **Step 5: Run view model and API tests**

Run:

```bash
swift test --filter FeedTimelineViewModelTests
swift test --filter FeedAPITests
```

Expected: both pass.

- [ ] **Step 6: Commit**

```bash
git add AtomanStudio/Infrastructure/API/FeedAPI.swift AtomanStudio/Features/Feed/FeedTimelineViewModel.swift AtomanStudioTests/FeedTimelineViewModelTests.swift
git commit -m "feat: add feed timeline view model"
```

---

## Task 4: App environment and `/api/v1` integration

**Files:**
- Modify: `AtomanStudio/App/AppEnvironment.swift`
- Modify: `AtomanStudioTests/AppSmokeTests.swift`
- Modify: any existing test that constructs `AppEnvironment`

- [ ] **Step 1: Write/update smoke expectations**

Modify `AtomanStudioTests/AppSmokeTests.swift` environment setup to create `FeedAPI` wherever `AppEnvironment` is constructed:

```swift
let database = try AppDatabase.inMemory()
let authSession = AuthSessionStore(token: nil)
let apiClient = APIClient(baseURL: URL(string: "https://example.com/api/v1")!)
let blogAPI = BlogAPI(client: apiClient, authSession: authSession)
let feedAPI = FeedAPI(client: apiClient, authSession: authSession)
let env = AppEnvironment(apiClient: apiClient, blogAPI: blogAPI, feedAPI: feedAPI, authSession: authSession, database: database)
```

- [ ] **Step 2: Run smoke tests and verify failure**

Run:

```bash
swift test --filter AppSmokeTests
```

Expected: compile failure because `AppEnvironment` does not accept `feedAPI` yet.

- [ ] **Step 3: Update AppEnvironment**

Modify `AtomanStudio/App/AppEnvironment.swift`:

```swift
@Observable
public final class AppEnvironment {
    public let apiClient: APIClient
    public let blogAPI: BlogAPI
    public let feedAPI: FeedAPI
    public let authSession: AuthSessionStore
    public let database: AppDatabase

    public init(apiClient: APIClient, blogAPI: BlogAPI, feedAPI: FeedAPI, authSession: AuthSessionStore, database: AppDatabase) {
        self.apiClient = apiClient
        self.blogAPI = blogAPI
        self.feedAPI = feedAPI
        self.authSession = authSession
        self.database = database
    }

    public static func live() -> AppEnvironment {
        let apiClient = APIClient(baseURL: URL(string: "http://localhost:8080/api/v1")!)
        let authSession = AuthSessionStore()
        let database = try! AppDatabase.openDefault()
        let blogAPI = BlogAPI(client: apiClient, authSession: authSession)
        let feedAPI = FeedAPI(client: apiClient, authSession: authSession)
        return AppEnvironment(apiClient: apiClient, blogAPI: blogAPI, feedAPI: feedAPI, authSession: authSession, database: database)
    }
}
```

- [ ] **Step 4: Update remaining direct AppEnvironment initializers**

Search:

```bash
grep -RIn "AppEnvironment(apiClient" AtomanStudio AtomanStudioTests
```

For each result, pass `feedAPI: FeedAPI(client: apiClient, authSession: authSession)`.

- [ ] **Step 5: Run smoke and existing API tests**

Run:

```bash
swift test --filter AppSmokeTests
swift test --filter BlogAPITests
swift test --filter FeedAPITests
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add AtomanStudio/App/AppEnvironment.swift AtomanStudioTests/AppSmokeTests.swift
git commit -m "feat: wire feed api into app environment"
```

---

## Task 5: Feed timeline and detail UI

**Files:**
- Create: `AtomanStudio/Features/Feed/FeedTimelineView.swift`
- Create: `AtomanStudio/Features/Feed/FeedArticleDetailView.swift`
- Test: `AtomanStudioTests/AppSmokeTests.swift`

- [ ] **Step 1: Add view creation smoke tests**

Append to `AtomanStudioTests/AppSmokeTests.swift`:

```swift
@MainActor
func testFeedTimelineViewCanBeCreated() throws {
    let database = try AppDatabase.inMemory()
    let authSession = AuthSessionStore(token: "token")
    let apiClient = APIClient(baseURL: URL(string: "https://example.com/api/v1")!)
    let feedAPI = FeedAPI(client: apiClient, authSession: authSession)
    let viewModel = FeedTimelineViewModel(feedService: feedAPI)

    let view = FeedTimelineView(viewModel: viewModel)

    XCTAssertNotNil(view)
}

@MainActor
func testFeedArticleDetailViewCanBeCreated() throws {
    let item = FeedTimelineItem(
        feedItem: FeedItem(
            id: "item-1",
            feedSourceID: "source-1",
            guid: "item-1",
            title: "Readable article",
            link: "https://example.com/article",
            summary: "Summary",
            author: "Author",
            publishedAt: Date(timeIntervalSince1970: 1_786_000_000),
            fetchedAt: nil,
            imageURL: nil,
            fullTextHTML: nil,
            feedSource: FeedSource(id: "source-1", sourceType: "external_rss", rssURL: "https://example.com/feed.xml", siteURL: nil, title: "Example", healthStatus: "healthy"),
            sourceTitleOverride: nil
        ),
        isRead: false,
        publishedAt: Date(timeIntervalSince1970: 1_786_000_000)
    )

    let view = FeedArticleDetailView(item: item, onToggleStar: {}, onMarkRead: {})

    XCTAssertNotNil(view)
}
```

- [ ] **Step 2: Run smoke tests and verify failure**

Run:

```bash
swift test --filter AppSmokeTests/testFeed
```

Expected: compile failure because the feed views do not exist.

- [ ] **Step 3: Implement FeedTimelineView**

Create `AtomanStudio/Features/Feed/FeedTimelineView.swift`:

```swift
import SwiftUI

public struct FeedTimelineView: View {
    @Bindable public var viewModel: FeedTimelineViewModel

    public init(viewModel: FeedTimelineViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            FeedTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    filterBar
                    content
                }
                .padding(20)
            }
            .refreshable {
                await viewModel.loadInitial()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel.items.isEmpty {
                await viewModel.loadInitial()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now, format: .dateTime.month().day().weekday(.wide))
                .font(.caption)
                .foregroundStyle(FeedTheme.secondaryText)
            HStack(alignment: .firstTextBaseline) {
                Text("订阅")
                    .font(.system(size: 34, weight: .800, design: .rounded))
                    .foregroundStyle(FeedTheme.primaryText)
                Spacer()
                Text("未读 \(viewModel.items.filter { !$0.isRead }.count)")
                    .font(.caption.weight(.700))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(FeedTheme.accent, in: Capsule())
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(FeedTimelineFilter.allCases) { filter in
                Button {
                    Task { await viewModel.selectFilter(filter) }
                } label: {
                    Text(filter.title)
                        .font(.subheadline.weight(.700))
                        .foregroundStyle(viewModel.selectedFilter == filter ? .black : FeedTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(viewModel.selectedFilter == filter ? FeedTheme.accent : FeedTheme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 220)
                .tint(FeedTheme.accent)
        } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
            FeedStateCard(title: errorMessage, message: "检查网络或稍后重试。", actionTitle: "重试") {
                Task { await viewModel.loadInitial() }
            }
        } else if viewModel.items.isEmpty {
            FeedStateCard(title: "还没有订阅内容", message: "先在网页端添加 RSS 订阅源，新的内容会出现在这里。", actionTitle: nil, action: nil)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.items) { item in
                    NavigationLink {
                        FeedArticleDetailView(
                            item: item,
                            onToggleStar: { Task { await viewModel.toggleStar(itemID: item.id) } },
                            onMarkRead: { Task { await viewModel.markReadAfterOpening(itemID: item.id) } }
                        )
                    } label: {
                        FeedTimelineCard(item: item) {
                            Task { await viewModel.toggleStar(itemID: item.id) }
                        }
                    }
                    .buttonStyle(.plain)
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItemID: item.id)
                    }
                }
                if viewModel.isLoadingMore {
                    ProgressView().tint(FeedTheme.accent)
                }
            }
        }
    }
}

private struct FeedTimelineCard: View {
    let item: FeedTimelineItem
    let onToggleStar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.sourceTitle)
                    .font(.caption.weight(.700))
                    .foregroundStyle(item.isRead ? FeedTheme.secondaryText : FeedTheme.accent)
                Spacer()
                Button(action: onToggleStar) {
                    Image(systemName: item.isStarred ? "star.fill" : "star")
                        .foregroundStyle(item.isStarred ? FeedTheme.accent : FeedTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            Text(item.displayTitle)
                .font(.headline.weight(.760))
                .foregroundStyle(FeedTheme.primaryText)
                .lineLimit(2)
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(FeedTheme.secondaryText)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .background(FeedTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(item.isRead ? FeedTheme.border : FeedTheme.accent.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct FeedStateCard: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title3.weight(.800))
                .foregroundStyle(FeedTheme.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(FeedTheme.secondaryText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(FeedTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(20)
        .background(FeedTheme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

enum FeedTheme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.16)
    static let border = Color.white.opacity(0.08)
    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.62)
    static let accent = Color(red: 0.84, green: 1.0, blue: 0.39)
}
```

- [ ] **Step 4: Implement FeedArticleDetailView**

Create `AtomanStudio/Features/Feed/FeedArticleDetailView.swift`:

```swift
import SwiftUI

public struct FeedArticleDetailView: View {
    public let item: FeedTimelineItem
    public let onToggleStar: () -> Void
    public let onMarkRead: () -> Void

    public init(item: FeedTimelineItem, onToggleStar: @escaping () -> Void, onMarkRead: @escaping () -> Void) {
        self.item = item
        self.onToggleStar = onToggleStar
        self.onMarkRead = onMarkRead
    }

    public var body: some View {
        ZStack {
            FeedTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(item.sourceTitle)
                        .font(.caption.weight(.800))
                        .foregroundStyle(FeedTheme.accent)
                    Text(item.displayTitle)
                        .font(.system(size: 32, weight: .820, design: .rounded))
                        .foregroundStyle(FeedTheme.primaryText)
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.body)
                            .foregroundStyle(FeedTheme.secondaryText)
                            .lineSpacing(4)
                    }
                    if let url = URL(string: item.link) {
                        Link("打开原文", destination: url)
                            .font(.headline.weight(.700))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(FeedTheme.accent, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onToggleStar) {
                    Image(systemName: item.isStarred ? "star.fill" : "star")
                }
                .tint(FeedTheme.accent)
            }
        }
        .task {
            onMarkRead()
        }
    }
}
```

- [ ] **Step 5: Run smoke tests**

Run:

```bash
swift test --filter AppSmokeTests/testFeed
```

Expected: feed view smoke tests pass.

- [ ] **Step 6: Commit**

```bash
git add AtomanStudio/Features/Feed/FeedTimelineView.swift AtomanStudio/Features/Feed/FeedArticleDetailView.swift AtomanStudioTests/AppSmokeTests.swift
git commit -m "feat: add feed reader views"
```

---

## Task 6: Add the “订阅” tab to the app shell

**Files:**
- Modify: `AtomanStudio/App/RootAppView.swift`
- Test: `AtomanStudioTests/AppSmokeTests.swift`

- [ ] **Step 1: Update AppTab tests or smoke coverage**

Add to `AtomanStudioTests/AppSmokeTests.swift`:

```swift
func testAppTabIncludesFeed() {
    XCTAssertEqual(AppTab.feed.hashValue, AppTab.feed.hashValue)
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
swift test --filter AppSmokeTests/testAppTabIncludesFeed
```

Expected: compile failure because `AppTab.feed` does not exist.

- [ ] **Step 3: Update MainTabView**

Modify `AtomanStudio/App/RootAppView.swift`:

```swift
public struct MainTabView: View {
    @State private var selectedTab: AppTab = .writing
    @State private var editorViewModel: BlogEditorViewModel
    @State private var feedViewModel: FeedTimelineViewModel

    public init(environment: AppEnvironment) {
        self._editorViewModel = State(
            initialValue: BlogEditorViewModel(
                blogAPI: environment.blogAPI,
                database: environment.database
            )
        )
        self._feedViewModel = State(
            initialValue: FeedTimelineViewModel(feedService: environment.feedAPI)
        )
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                BlogEditorView(viewModel: editorViewModel)
                    .navigationTitle("写作")
            }
            .tabItem {
                Label("写作", systemImage: "square.and.pencil")
            }
            .tag(AppTab.writing)

            NavigationStack {
                FeedTimelineView(viewModel: feedViewModel)
                    .navigationTitle("订阅")
            }
            .tabItem {
                Label("订阅", systemImage: "dot.radiowaves.left.and.right")
            }
            .tag(AppTab.feed)

            NavigationStack {
                DraftListView(drafts: []) { draft in
                    editorViewModel.apply(draft)
                    selectedTab = .writing
                }
            }
            .tabItem {
                Label("草稿", systemImage: "doc.text")
            }
            .tag(AppTab.drafts)

            NavigationStack {
                AuthenticationGateView(
                    title: "登录后管理频道",
                    message: "频道和合集保存在云端。登录后可以查看和管理你的发布频道。"
                ) {
                    ChannelListView()
                }
            }
            .tabItem {
                Label("频道", systemImage: "rectangle.stack")
            }
            .tag(AppTab.channels)
        }
    }
}

public enum AppTab: Hashable {
    case writing
    case feed
    case drafts
    case channels
}
```

If the product decision is to require login before seeing RSS content, wrap `FeedTimelineView` in `AuthenticationGateView` inside the feed `NavigationStack`:

```swift
AuthenticationGateView(
    title: "登录后查看订阅",
    message: "RSS 订阅和阅读状态保存在云端。登录后可以查看你的订阅时间线。"
) {
    FeedTimelineView(viewModel: feedViewModel)
}
.navigationTitle("订阅")
```

Use this wrapper in the final code because the approved spec requires authentication gating.

- [ ] **Step 4: Run app smoke tests**

Run:

```bash
swift test --filter AppSmokeTests
```

Expected: all app smoke tests pass.

- [ ] **Step 5: Commit**

```bash
git add AtomanStudio/App/RootAppView.swift AtomanStudioTests/AppSmokeTests.swift
git commit -m "feat: add feed tab"
```

---

## Task 7: Full verification and iOS build

**Files:**
- No intentional source changes unless verification exposes a defect.

- [ ] **Step 1: Run focused feed tests**

Run:

```bash
swift test --filter FeedModelsTests
swift test --filter FeedAPITests
swift test --filter FeedTimelineViewModelTests
```

Expected: all pass.

- [ ] **Step 2: Run full Swift test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 3: Run Swift build**

Run:

```bash
swift build
```

Expected: build completes without errors.

- [ ] **Step 4: Run iOS app build**

Run:

```bash
xcodebuild -scheme AtomanStudioApp -project AtomanStudioApp.xcodeproj -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual UI verification in simulator**

Open the app with the `AtomanStudioApp` scheme. Verify:

- The “订阅” tab appears.
- Logged-out users see the RSS authentication gate.
- Logged-in users can load a timeline from a backend running at `http://localhost:8080/api/v1`.
- The timeline uses the Creator Studio dark card style.
- Filters appear as “全部 / 未读 / 星标”.
- Opening a card navigates to detail.
- Opening an unread card marks it read.
- Star toggling changes the visible star state.
- Empty and error states are legible and not default plain list screens.

- [ ] **Step 6: Commit any verification fixes**

If verification required fixes:

```bash
git add <specific files fixed>
git commit -m "fix: verify feed reader integration"
```

If no fixes were needed, do not create an empty commit.

---

## Self-review

### Spec coverage

- New “订阅” tab: Task 6.
- Authentication gate: Task 6.
- Timeline API and pagination: Tasks 2 and 3.
- Default query with `hide_duplicates=true`: Task 2.
- Filters all/unread/starred: Tasks 1, 2, 3, 5.
- Timeline cards: Task 5.
- Detail screen: Task 5.
- Mark read on open: Tasks 2, 3, 5.
- Toggle star: Tasks 2, 3, 5.
- `/api/v1` base URL: Task 4.
- No backend changes: all tasks are iOS-only.
- Empty/loading/error visual states: Task 5.
- Tests and verification: Tasks 1 through 7.

### Placeholder scan

This plan contains no TBD/TODO placeholders and no “implement later” steps. Each code-producing step names exact files and includes concrete code or exact edits.

### Type consistency

The plan consistently uses:

- `FeedServicing`
- `FeedAPI`
- `FeedTimelineFilter`
- `FeedTimelinePage`
- `FeedTimelineItem`
- `FeedItem`
- `FeedSource`
- `FeedTimelineViewModel`
- `FeedTimelineView`
- `FeedArticleDetailView`
