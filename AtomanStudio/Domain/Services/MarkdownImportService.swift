import Foundation

public struct MarkdownImportResult: Equatable {
    public let title: String
    public let body: String
}

public enum MarkdownImportService {
    public static func parse(text: String, fallbackFilename: String) -> MarkdownImportResult {
        let lines = text.components(separatedBy: .newlines)
        if let headingLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") }) {
            let title = headingLine.replacingOccurrences(of: "# ", with: "").trimmingCharacters(in: .whitespaces)
            if let index = lines.firstIndex(of: headingLine) {
                let body = lines.dropFirst(index + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return MarkdownImportResult(title: title, body: body)
            }
        }
        let fallbackTitle = fallbackFilename.replacingOccurrences(of: #"\.(md|markdown|txt)$"#, with: "", options: .regularExpression)
        return MarkdownImportResult(title: fallbackTitle, body: text)
    }
}
