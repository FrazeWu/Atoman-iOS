import Foundation
import Observation

public struct LoginRequest: Encodable {
    public let username: String
    public let password: String
}

public struct LoginResponse: Decodable {
    public let token: String
}

@MainActor
@Observable
public final class LoginViewModel {
    public var username = ""
    public var password = ""
    public var isLoading = false
    public var errorMessage: String?

    private let client: APIClient
    private let authSession: AuthSessionStore

    public init(client: APIClient, authSession: AuthSessionStore) {
        self.client = client
        self.authSession = authSession
    }

    public func login() async {
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "请输入用户名或邮箱"
            return
        }
        if password.isEmpty {
            errorMessage = "请输入密码"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let request = LoginRequest(username: username, password: password)
            let body = try JSONEncoder().encode(request)
            let (data, response) = try await client.request(path: "auth/login", method: "POST", body: body)
            guard response.statusCode == 200 else {
                errorMessage = "登录失败，请检查账号密码"
                return
            }
            let payload = try JSONDecoder().decode(LoginResponse.self, from: data)
            authSession.token = payload.token
            errorMessage = nil
        } catch {
            errorMessage = "登录失败，请稍后重试"
        }
    }
}
