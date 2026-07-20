import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct APIClient {
    public let baseURL: URL
    public var session: URLSession
    private let onUnauthorized: (@Sendable () async -> Void)?

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        onUnauthorized: (@Sendable () async -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.onUnauthorized = onUnauthorized
    }

    public func request(
        path: String,
        method: String = "GET",
        token: String? = nil,
        body: Data? = nil,
        contentType: String? = "application/json",
        queryItems: [URLQueryItem] = []
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: makeURL(path: path, queryItems: queryItems))
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
        if http.statusCode == 401, token?.isEmpty == false {
            await onUnauthorized?()
        }
        return (data, http)
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) -> URL {
        let url = baseURL.appending(path: path)
        guard !queryItems.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = queryItems.sorted { $0.name < $1.name }
        return components.url ?? url
    }
}
