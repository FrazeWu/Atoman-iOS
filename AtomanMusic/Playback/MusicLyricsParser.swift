import Foundation

public struct MusicLyricLine: Hashable, Identifiable, Sendable {
    public let index: Int
    public let time: TimeInterval?
    public let text: String

    public var id: Int { index }
}

public enum MusicLyricsParser {
    public static func parse(_ lyrics: String) -> [MusicLyricLine] {
        lyrics
            .components(separatedBy: .newlines)
            .compactMap { rawLine -> (TimeInterval?, String)? in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }
                guard line.hasPrefix("["), let closingBracket = line.firstIndex(of: "]") else {
                    return (nil, line)
                }
                let timestamp = String(line[line.index(after: line.startIndex)..<closingBracket])
                let text = String(line[line.index(after: closingBracket)...]).trimmingCharacters(in: .whitespaces)
                let parts = timestamp.split(separator: ":", maxSplits: 1).compactMap { Double($0) }
                guard parts.count == 2, !text.isEmpty else {
                    return (nil, line)
                }
                return (parts[0] * 60 + parts[1], text)
            }
            .enumerated()
            .map { MusicLyricLine(index: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    public static func activeLineIndex(in lines: [MusicLyricLine], at time: TimeInterval) -> Int? {
        lines.last { line in
            guard let lineTime = line.time else { return false }
            return lineTime <= time
        }?.index
    }
}
