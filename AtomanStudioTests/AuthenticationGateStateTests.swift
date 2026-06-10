import XCTest
@testable import AtomanStudio

final class AuthenticationGateStateTests: XCTestCase {
    func testGuestStateRequiresLogin() {
        let state = AuthenticationGateState.resolve(isAuthenticated: false)

        XCTAssertEqual(state, .requiresLogin)
    }

    func testAuthenticatedStateAllowsContent() {
        let state = AuthenticationGateState.resolve(isAuthenticated: true)

        XCTAssertEqual(state, .authenticated)
    }

    func testStateCanResolveFromAuthSessionStore() {
        let guestSession = AuthSessionStore(token: nil)
        let authenticatedSession = AuthSessionStore(token: "token")

        XCTAssertEqual(AuthenticationGateState.resolve(session: guestSession), .requiresLogin)
        XCTAssertEqual(AuthenticationGateState.resolve(session: authenticatedSession), .authenticated)
    }
}
