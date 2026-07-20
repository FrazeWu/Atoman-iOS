import XCTest
@testable import AtomanMusic

final class MusicLyricsParserTests: XCTestCase {
    func testParsesLRCAndFindsActiveLine() {
        let lines = MusicLyricsParser.parse("[00:01.00]第一行\n[00:05.50]第二行")

        XCTAssertEqual(lines.map(\.text), ["第一行", "第二行"])
        XCTAssertEqual(lines.map(\.time), [1.0, 5.5])
        XCTAssertEqual(MusicLyricsParser.activeLineIndex(in: lines, at: 6.0), 1)
    }

    func testPlainLyricsRemainReadable() {
        let lines = MusicLyricsParser.parse("第一行\n第二行")

        XCTAssertEqual(lines.map(\.text), ["第一行", "第二行"])
        XCTAssertTrue(lines.allSatisfy { $0.time == nil })
    }
}
