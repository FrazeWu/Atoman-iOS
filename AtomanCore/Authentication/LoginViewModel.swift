import Foundation
import Observation

@MainActor
@Observable
public final class LoginViewModel {
    public var username = ""
    public var password = ""
    public var isLoading = false
    public var errorMessage: String?

    private let api: AuthAPI
    private let authSession: AuthSessionStore

    public init(client: APIClient, authSession: AuthSessionStore) {
        self.api = AuthAPI(client: client)
        self.authSession = authSession
    }

    @discardableResult
    public func login() async -> Bool {
        let identifier = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if identifier.isEmpty {
            errorMessage = "请输入用户名或邮箱"
            return false
        }
        if password.isEmpty {
            errorMessage = "请输入密码"
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let payload = try await api.login(identifier: identifier, password: password)
            try authSession.authenticate(payload)
            errorMessage = nil
            return true
        } catch is AuthTokenStorageError {
            errorMessage = "无法保存登录状态，请重试"
            return false
        } catch let error as AuthAPIError {
            errorMessage = Self.message(for: error)
            return false
        } catch is URLError {
            errorMessage = "无法连接服务器，请稍后重试"
            return false
        } catch {
            errorMessage = "登录失败，请稍后重试"
            return false
        }
    }

    private static func message(for error: AuthAPIError) -> String {
        switch error {
        case .server(_, let code, _):
            switch code {
            case "auth.account_not_found":
                return "账号不存在"
            case "auth.password_mismatch":
                return "密码不正确"
            default:
                return "登录失败，请稍后重试"
            }
        case .invalidResponse:
            return "登录失败，请稍后重试"
        }
    }
}
