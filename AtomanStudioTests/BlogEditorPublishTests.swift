import XCTest
@testable import AtomanStudio

final class BlogEditorPublishTests: XCTestCase {
    func testCreateBlogPostRequestCarriesFollowersVisibility() throws {
        let request = CreateBlogPostRequest(
            title: "Hello",
            content: "Body",
            summary: "",
            coverURL: "",
            visibility: .followers,
            allowComments: true,
            status: "published",
            channelID: "channel-1",
            collectionIDs: ["default-1"]
        )

        let data = try JSONEncoder().encode(request)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"visibility\":\"followers\""))
    }

    func testMarkdownImageSnippetUsesMarkdownImageSyntax() {
        let service = MarkdownImageUploadService(
            blogAPI: BlogAPI(client: APIClient(baseURL: URL(string: "https://example.com/api")!), authSession: AuthSessionStore(token: nil))
        )

        XCTAssertEqual(service.markdownSnippet(forRemoteURL: "https://example.com/image.png", alt: "cover"), "![cover](https://example.com/image.png)")
    }
}
