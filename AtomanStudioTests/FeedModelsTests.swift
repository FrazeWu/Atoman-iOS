import XCTest
@testable import AtomanStudio

final class FeedModelsTests: XCTestCase {
    func testTimelineDecodesFeedItemEnvelope() throws {
        let json = """
        {
          "data": [{
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
          }],
          "total": 1,
          "page": 1,
          "limit": 20,
          "message": "ok"
        }
        """.data(using: .utf8)!

        let page = try JSONDecoder.feed.decode(FeedTimelinePage.self, from: json)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].id, "item-1")
        XCTAssertEqual(page.items[0].displayTitle, "A modern RSS reader")
        XCTAssertEqual(page.items[0].sourceTitle, "Example Feed")
        XCTAssertFalse(page.items[0].isRead)
    }

    func testTimelineSkipsUnsupportedPostItems() throws {
        let json = """
        {
          "data": [{
            "type": "post",
            "published_at": "2026-06-15T08:30:00Z",
            "is_read": false,
            "post": {"id":"post-1","user_id":"user-1","title":"Blog","content":"Body","status":"published","visibility":"public","allow_comments":true}
          }],
          "total": 1,
          "page": 1,
          "limit": 20
        }
        """.data(using: .utf8)!

        let page = try JSONDecoder.feed.decode(FeedTimelinePage.self, from: json)

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.total, 1)
    }

    func testStarredItemsDecodeLegacyShape() throws {
        let json = """
        {
          "items": [{
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
          }],
          "page": 1,
          "total": 1
        }
        """.data(using: .utf8)!

        let page = try JSONDecoder.feed.decode(FeedStarredPage.self, from: json)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].sourceTitle, "Saved Feed")
    }
}
