import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct APIClient {
    public let baseURL: URL
    public var session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func request(
        path: String,
        method: String = "GET",
        token: String? = nil,
        body: Data? = nil,
        contentType: String? = "application/json"
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
