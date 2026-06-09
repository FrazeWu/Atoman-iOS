import XCTest
@testable import AtomanStudio

final class MarkdownImportServiceTests: XCTestCase {
    func testImportSplitsTitleAndBodyFromFirstHeading() {
        let input = "# Hello\nFirst line\nSecond line"
        let result = MarkdownImportService.parse(text: input, fallbackFilename: "draft.md")

        XCTAssertEqual(result.title, "Hello")
        XCTAssertEqual(result.body, "First line\nSecond line")
    }

    func testImportFallsBackToFilenameWhenNoHeading() {
        let input = "Paragraph only"
        let result = MarkdownImportService.parse(text: input, fallbackFilename: "my-note.md")

        XCTAssertEqual(result.title, "my-note")
        XCTAssertEqual(result.body, "Paragraph only")
    }
}
