import AtomanCore
import XCTest
@testable import AtomanStudio

@MainActor
final class BlogEditorViewModelTests: XCTestCase {
    func testDraftPayloadCarriesVisibilityAndCollections() throws {
        let vm = BlogEditorViewModel(
            blogAPI: BlogAPI(client: APIClient(baseURL: URL(string: "https://example.com/api")!), authSession: AuthSessionStore(token: nil)),
            database: try AppDatabase.inMemory()
        )
        vm.title = "Hello"
        vm.content = "Body"
        vm.visibility = .followers
        vm.channelID = "channel-1"
        vm.collectionIDs = ["c1", "c2"]

        let payload = vm.makeDraftPayload(contextKey: "blog:new", sourcePostID: nil)

        XCTAssertEqual(payload.visibility, .followers)
        XCTAssertEqual(payload.collectionIDs, ["c1", "c2"])
    }
}
