import Foundation

public struct AuthAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func login(identifier: String, password: String) async throws -> AuthSessionPayload {
        let body = try JSONEncoder().encode(LoginBody(username: identifier, password: password))
        let (data, response) = try await client.request(path: "auth/login", method: "POST", body: body)
        try validate(data: data, response: response)
        guard let payload = try? JSONDecoder().decode(AuthSessionPayload.self, from: data) else {
            throw AuthAPIError.invalidResponse
        }
        return payload
    }

    public func currentUser(token: String) async throws -> AuthUser {
        let (data, response) = try await client.request(path: "users/me", token: token)
        try validate(data: data, response: response)
        guard let envelope = try? JSONDecoder().decode(CurrentUserEnvelope.self, from: data) else {
            throw AuthAPIError.invalidResponse
        }
        return envelope.data
    }

    private func validate(data: Data, response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            let payload = try? JSONDecoder().decode(AuthErrorEnvelope.self, from: data)
            throw AuthAPIError.server(
                statusCode: response.statusCode,
                code: payload?.code,
                message: payload?.error ?? "请求失败"
            )
        }
    }
}

private struct LoginBody: Encodable {
    let username: String
    let password: String
}

private struct CurrentUserEnvelope: Decodable {
    let data: AuthUser
}

private struct AuthErrorEnvelope: Decodable {
    let code: String?
    let error: String?
}
