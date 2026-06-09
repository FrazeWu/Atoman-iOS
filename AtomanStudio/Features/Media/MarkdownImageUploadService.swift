import Foundation

public struct MarkdownImageUploadService {
    public let blogAPI: BlogAPI

    public init(blogAPI: BlogAPI) {
        self.blogAPI = blogAPI
    }

    public func markdownSnippet(forRemoteURL url: String, alt: String = "image") -> String {
        "![\(alt)](\(url))"
    }
}
