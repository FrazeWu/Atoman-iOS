import AtomanCore
import XCTest
@testable import AtomanStudio

@MainActor
final class LoginViewModelTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testEmptyUsernameIsRejectedBeforeNetwork() async {
        let vm = LoginViewModel(
            client: APIClient(baseURL: URL(string: "https://example.com/api")!),
            authSession: AuthSessionStore(token: nil)
        )
        vm.username = ""
        vm.password = "secret"

        await vm.login()

        XCTAssertEqual(vm.errorMessage, "请输入用户名或邮箱")
    }

    func testLoginCanSubmitOnlyWithCompleteCredentials() {
        let vm = LoginViewModel(
            client: APIClient(baseURL: URL(string: "https://example.com/api")!),
            authSession: AuthSessionStore(token: nil)
        )

        XCTAssertFalse(vm.canSubmit)

        vm.username = "  "
        vm.password = "secret"
        XCTAssertFalse(vm.canSubmit)

        vm.username = "alice"
        XCTAssertTrue(vm.canSubmit)

        vm.isLoading = true
        XCTAssertFalse(vm.canSubmit)
    }

    func testSuccessfulLoginStoresAuthenticatedUser() async {
        URLProtocolStub.requestHandler = { request in
            Self.response(request, body: Self.sessionBody)
        }
        let storage = TokenStorageForLoginTests()
        let session = AuthSessionStore(storage: storage)
        let vm = LoginViewModel(client: makeClient(), authSession: session)
        vm.username = " Alice@Example.com "
        vm.password = "secret123"

        let succeeded = await vm.login()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(storage.savedToken, "server-token")
        XCTAssertEqual(session.user?.username, "alice")
        XCTAssertEqual(session.phase, .authenticated(session.user!))
    }

    func testPasswordMismatchUsesServerMessage() async {
        URLProtocolStub.requestHandler = { request in
            Self.response(
                request,
                statusCode: 401,
                body: #"{"code":"auth.password_mismatch","error":"密码不正确"}"#
            )
        }
        let vm = LoginViewModel(client: makeClient(), authSession: AuthSessionStore(token: nil))
        vm.username = "alice"
        vm.password = "wrong"

        let succeeded = await vm.login()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(vm.errorMessage, "密码不正确")
    }

    func testNetworkFailureUsesConnectionMessage() async {
        URLProtocolStub.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let vm = LoginViewModel(client: makeClient(), authSession: AuthSessionStore(token: nil))
        vm.username = "alice"
        vm.password = "secret123"

        let succeeded = await vm.login()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(vm.errorMessage, "无法连接服务器，请稍后重试")
    }

    func testKeychainFailureExplainsThatLoginCannotBeSaved() async {
        URLProtocolStub.requestHandler = { request in
            Self.response(request, body: Self.sessionBody)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let storage = FailingAuthTokenStorage()
        let vm = LoginViewModel(
            client: APIClient(
                baseURL: URL(string: "https://example.com/api")!,
                session: URLSession(configuration: configuration)
            ),
            authSession: AuthSessionStore(storage: storage)
        )
        vm.username = "alice"
        vm.password = "secret"

        let succeeded = await vm.login()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(vm.errorMessage, "无法保存登录状态，请重试")
    }

    private static let sessionBody = """
    {"token":"server-token","user":{"id":7,"uuid":"user-1","username":"alice","email":"alice@example.com","role":"user","display_name":"Alice","avatar_url":"","is_active":true}}
    """

    private static func response(
        _ request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }

    private func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return APIClient(
            baseURL: URL(string: "https://example.com/api")!,
            session: URLSession(configuration: configuration)
        )
    }
}

private final class FailingAuthTokenStorage: AuthTokenStoring {
    func loadToken() throws -> String? { nil }
    func saveToken(_ token: String) throws { throw AuthTokenStorageError.unexpectedStatus(-34018) }
    func removeToken() throws {}
}

private final class TokenStorageForLoginTests: AuthTokenStoring {
    var savedToken: String?

    func loadToken() throws -> String? { nil }
    func saveToken(_ token: String) throws { savedToken = token }
    func removeToken() throws {}
}
