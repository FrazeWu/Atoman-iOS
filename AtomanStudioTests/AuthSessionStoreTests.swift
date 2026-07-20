import AtomanCore
import XCTest
@testable import AtomanStudio

final class AuthSessionStoreTests: XCTestCase {
    func testStoredTokenAndUserBeginInRestoringState() {
        let user = makeUser(name: "Cached Alice")
        let session = AuthSessionStore(
            storage: TokenStorageSpy(token: "stored-token"),
            userCache: UserCacheSpy(user: user)
        )

        XCTAssertEqual(session.phase, .restoring(user))
        XCTAssertEqual(session.user, user)
    }

    func testAuthenticatePersistsTokenAndUser() throws {
        let storage = TokenStorageSpy(token: nil)
        let cache = UserCacheSpy(user: nil)
        let session = AuthSessionStore(storage: storage, userCache: cache)
        let user = makeUser(name: "Alice")

        try session.authenticate(AuthSessionPayload(token: "new-token", user: user))

        XCTAssertEqual(storage.savedToken, "new-token")
        XCTAssertEqual(cache.savedUser, user)
        XCTAssertEqual(session.phase, .authenticated(user))
    }

    func testRestoreUpdatesAuthenticatedUser() async {
        let cached = makeUser(name: "Cached Alice")
        let fresh = makeUser(name: "Fresh Alice")
        let cache = UserCacheSpy(user: cached)
        let session = AuthSessionStore(
            storage: TokenStorageSpy(token: "stored-token"),
            userCache: cache
        )

        await session.restore { token in
            XCTAssertEqual(token, "stored-token")
            return fresh
        }

        XCTAssertEqual(session.phase, .authenticated(fresh))
        XCTAssertEqual(cache.savedUser, fresh)
    }

    func testRestoreUnauthorizedClearsSession() async {
        let storage = TokenStorageSpy(token: "expired-token")
        let cache = UserCacheSpy(user: makeUser(name: "Cached Alice"))
        let session = AuthSessionStore(storage: storage, userCache: cache)

        await session.restore { _ in
            throw AuthAPIError.server(statusCode: 401, code: "auth.invalid_token", message: "登录状态已失效")
        }

        XCTAssertEqual(session.phase, .guest)
        XCTAssertNil(session.token)
        XCTAssertTrue(storage.didRemoveToken)
        XCTAssertTrue(cache.didRemoveUser)
    }

    func testRestoreNetworkFailureKeepsOfflineSession() async {
        let cached = makeUser(name: "Cached Alice")
        let storage = TokenStorageSpy(token: "stored-token")
        let session = AuthSessionStore(
            storage: storage,
            userCache: UserCacheSpy(user: cached)
        )

        await session.restore { _ in throw URLError(.notConnectedToInternet) }

        XCTAssertEqual(session.phase, .offline(cached))
        XCTAssertEqual(session.token, "stored-token")
        XCTAssertFalse(storage.didRemoveToken)
    }

    func testLoadsTokenFromStorage() {
        let storage = TokenStorageSpy(token: "stored-token")

        let session = AuthSessionStore(storage: storage)

        XCTAssertEqual(session.token, "stored-token")
    }

    func testPersistsTokenChanges() {
        let storage = TokenStorageSpy(token: nil)
        let session = AuthSessionStore(storage: storage)

        XCTAssertNoThrow(try session.setToken("new-token"))

        XCTAssertEqual(storage.savedToken, "new-token")
    }

    func testSetTokenSurfacesStorageFailure() {
        let storage = TokenStorageSpy(token: nil)
        storage.saveError = .unexpectedStatus(-34018)
        let session = AuthSessionStore(storage: storage)

        XCTAssertThrowsError(try session.setToken("new-token")) { error in
            XCTAssertEqual(error as? AuthTokenStorageError, .unexpectedStatus(-34018))
        }
        XCTAssertNil(session.token)
        XCTAssertEqual(session.storageError, .unexpectedStatus(-34018))
    }

    func testClearRemovesStoredToken() {
        let storage = TokenStorageSpy(token: "stored-token")
        let cache = UserCacheSpy(user: makeUser(name: "Alice"))
        let session = AuthSessionStore(storage: storage, userCache: cache)

        session.clear()

        XCTAssertTrue(storage.didRemoveToken)
        XCTAssertTrue(cache.didRemoveUser)
        XCTAssertNil(session.token)
        XCTAssertEqual(session.phase, .guest)
    }

    private func makeUser(name: String) -> AuthUser {
        AuthUser(
            id: 7,
            uuid: "user-1",
            username: "alice",
            email: "alice@example.com",
            role: "user",
            displayName: name
        )
    }
}

private final class TokenStorageSpy: AuthTokenStoring {
    var token: String?
    var savedToken: String?
    var didRemoveToken = false
    var saveError: AuthTokenStorageError?

    init(token: String?) {
        self.token = token
    }

    func loadToken() throws -> String? {
        token
    }

    func saveToken(_ token: String) throws {
        if let saveError {
            throw saveError
        }
        savedToken = token
        self.token = token
    }

    func removeToken() throws {
        didRemoveToken = true
        token = nil
    }
}

private final class UserCacheSpy: AuthUserCaching {
    var user: AuthUser?
    var savedUser: AuthUser?
    var didRemoveUser = false

    init(user: AuthUser?) {
        self.user = user
    }

    func loadUser() -> AuthUser? {
        user
    }

    func saveUser(_ user: AuthUser) {
        savedUser = user
        self.user = user
    }

    func removeUser() {
        didRemoveUser = true
        user = nil
    }
}
