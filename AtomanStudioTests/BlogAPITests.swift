import XCTest
@testable import AtomanStudio

final class BlogAPITests: XCTestCase {
    func testVisibilityDecodesFromEnvelope() throws {
        let json = """
        {"data":{"id":"post-1","user_id":"user-1","channel_id":"ch-1","title":"Hello","content":"Body","status":"draft","visibility":"followers","allow_comments":true}}
        """.data(using: .utf8)!
        let post = try JSONDecoder().decode(APIEnvelope<BlogPost>.self, from: json).data
        XCTAssertEqual(post.visibility, .followers)
    }
}
