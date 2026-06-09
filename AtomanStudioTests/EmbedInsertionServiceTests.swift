import XCTest
@testable import AtomanStudio

final class EmbedInsertionServiceTests: XCTestCase {
    func testPostEmbedUsesExistingDirectiveSyntax() {
        XCTAssertEqual(EmbedInsertionService.post(id: "post-1"), ":::post{id=\"post-1\"}\n:::")
    }

    func testMusicEmbedUsesExistingDirectiveSyntax() {
        XCTAssertEqual(EmbedInsertionService.music(id: "music-1"), ":::music{id=\"music-1\"}\n:::")
    }

    func testVideoEmbedUsesExistingDirectiveSyntax() {
        XCTAssertEqual(EmbedInsertionService.video(id: "video-1"), ":::video{id=\"video-1\"}\n:::")
    }
}
