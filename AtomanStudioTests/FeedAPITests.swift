import Foundation
import XCTest
@testable import AtomanStudio

final class FeedAPITests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testFetchUnreadTimelineBuildsRequest() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/feed/timeline?hide_duplicates=true&is_read=false&page=2&page_size=10")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            return Self.response(request, body: "{\"data\":[],\"total\":0,\"page\":2,\"limit\":10}")
        }

        let page = try await api.fetchTimeline(filter: .unread, page: 2, pageSize: 10)

        XCTAssertEqual(page.page, 2)
        XCTAssertTrue(page.items.isEmpty)
    }

    func testFetchStarredUsesStarsEndpoint() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/feed/stars?limit=20&page=1")
            return Self.response(request, body: "{\"items\":[],\"page\":1,\"total\":0}")
        }

        let page = try await api.fetchTimeline(filter: .starred)

        XCTAssertEqual(page.total, 0)
    }

    func testMarkReadPostsFeedItemIDs() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/feed/timeline/mark-read")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: [String]]
            XCTAssertEqual(body?["feed_item_ids"], ["item-1"])
            return Self.response(request, body: "{\"message\":\"ok\"}")
        }

        try await api.markRead(itemIDs: ["item-1"])
    }

    func testToggleStarReturnsStarredState() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/feed/timeline/star")
            XCTAssertEqual(request.httpMethod, "POST")
            return Self.response(request, body: "{\"starred\":true,\"message\":\"Item starred\"}")
        }

        XCTAssertTrue(try await api.toggleStar(feedItemID: "item-1"))
    }

    private func makeAPI(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> FeedAPI {
        URLProtocolStub.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(baseURL: URL(string: "https://example.com/api/v1")!, session: session)
        return FeedAPI(client: client, authSession: AuthSessionStore(token: "token-1"))
    }

    private static func response(_ request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
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
