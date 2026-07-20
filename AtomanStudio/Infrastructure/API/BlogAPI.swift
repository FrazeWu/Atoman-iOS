import AtomanCore
import Foundation

public struct BlogAPI {
    public let client: APIClient
    public let authSession: AuthSessionStore

    public init(client: APIClient, authSession: AuthSessionStore) {
        self.client = client
        self.authSession = authSession
    }

    public func fetchChannels() async throws -> [BlogChannel] {
        let (data, response) = try await client.request(path: "blog/channels", token: authSession.token)
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(APIEnvelope<[BlogChannel]>.self, from: data).data
    }

    public func putDraft(_ payload: EditorDraftPayload) async throws {
        let body = try JSONEncoder().encode(payload)
        let (_, response) = try await client.request(path: "blog/drafts", method: "PUT", token: authSession.token, body: body)
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
    }

    public func createPost(_ payload: CreateBlogPostRequest) async throws -> BlogPost {
        let body = try JSONEncoder().encode(payload)
        let (data, response) = try await client.request(path: "blog/posts", method: "POST", token: authSession.token, body: body)
        guard response.statusCode == 201 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(APIEnvelope<BlogPost>.self, from: data).data
    }
}
