import XCTest
@testable import AtomanStudio

@MainActor
final class LoginViewModelTests: XCTestCase {
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
}
