import Foundation
import Observation
#if canImport(Security)
import Security
#endif

public protocol AuthTokenStoring: AnyObject {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
    func removeToken() throws
}

public protocol AuthUserCaching: AnyObject {
    func loadUser() -> AuthUser?
    func saveUser(_ user: AuthUser)
    func removeUser()
}

public enum AuthSessionPhase: Equatable, Sendable {
    case guest
    case restoring(AuthUser?)
    case authenticated(AuthUser)
    case offline(AuthUser?)
}

public enum AuthTokenStorageError: Error, Equatable {
    case unexpectedStatus(Int32)
    case unavailable
}

public final class KeychainAuthTokenStorage: AuthTokenStoring {
    private let service: String
    private let account: String
    private let accessGroup: String?

    public init(
        service: String = "com.atoman.auth",
        account: String = "access-token",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    public func loadToken() throws -> String? {
#if canImport(Security)
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AuthTokenStorageError.unexpectedStatus(status)
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
#else
        throw AuthTokenStorageError.unavailable
#endif
    }

    public func saveToken(_ token: String) throws {
#if canImport(Security)
        let data = Data(token.utf8)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AuthTokenStorageError.unexpectedStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw AuthTokenStorageError.unexpectedStatus(status)
        }
#else
        throw AuthTokenStorageError.unavailable
#endif
    }

    public func removeToken() throws {
#if canImport(Security)
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthTokenStorageError.unexpectedStatus(status)
        }
#else
        throw AuthTokenStorageError.unavailable
#endif
    }

#if canImport(Security)
    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
#endif
}

public final class UserDefaultsAuthUserCache: AuthUserCaching {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "atoman.auth.user") {
        self.defaults = defaults
        self.key = key
    }

    public func loadUser() -> AuthUser? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    public func saveUser(_ user: AuthUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        defaults.set(data, forKey: key)
    }

    public func removeUser() {
        defaults.removeObject(forKey: key)
    }
}

@Observable
public final class AuthSessionStore {
    private enum Keys {
        static let token = "atoman.auth.token"
    }

    private let storage: AuthTokenStoring?
    private let userCache: AuthUserCaching?

    public private(set) var token: String?
    public private(set) var user: AuthUser?
    public private(set) var phase: AuthSessionPhase
    public private(set) var storageError: AuthTokenStorageError?

    public convenience init() {
        let accessGroup = Bundle.main.object(forInfoDictionaryKey: "AtomanKeychainAccessGroup") as? String
        let storage = KeychainAuthTokenStorage(accessGroup: accessGroup)
        self.init(storage: storage, userCache: UserDefaultsAuthUserCache())
        if token == nil,
           storageError == nil,
           let legacyToken = UserDefaults.standard.string(forKey: Keys.token) {
            do {
                try setToken(legacyToken)
                UserDefaults.standard.removeObject(forKey: Keys.token)
            } catch {
                // setToken records the storage failure for the login UI.
            }
        }
    }

    public init(token: String?) {
        self.token = token
        self.user = nil
        self.phase = token?.isEmpty == false ? .restoring(nil) : .guest
        self.storage = nil
        self.userCache = nil
        self.storageError = nil
    }

    public init(storage: AuthTokenStoring, userCache: AuthUserCaching? = nil) {
        self.storage = storage
        self.userCache = userCache
        do {
            let token = try storage.loadToken()
            let user = userCache?.loadUser()
            self.token = token
            self.user = user
            self.phase = token?.isEmpty == false ? .restoring(user) : .guest
            self.storageError = nil
        } catch {
            self.token = nil
            self.user = nil
            self.phase = .guest
            self.storageError = Self.authStorageError(from: error)
        }
    }

    public var isAuthenticated: Bool {
        token?.isEmpty == false
    }

    public func setToken(_ token: String) throws {
        do {
            try storage?.saveToken(token)
            self.token = token
            phase = .restoring(user)
            storageError = nil
        } catch {
            storageError = Self.authStorageError(from: error)
            throw error
        }
    }

    public func authenticate(_ payload: AuthSessionPayload) throws {
        try storage?.saveToken(payload.token)
        token = payload.token
        user = payload.user
        userCache?.saveUser(payload.user)
        phase = .authenticated(payload.user)
        storageError = nil
    }

    public func restore(fetchUser: (String) async throws -> AuthUser) async {
        guard let token, !token.isEmpty else {
            phase = .guest
            return
        }
        phase = .restoring(user)
        do {
            let refreshedUser = try await fetchUser(token)
            user = refreshedUser
            userCache?.saveUser(refreshedUser)
            phase = .authenticated(refreshedUser)
        } catch AuthAPIError.server(let statusCode, _, _) where statusCode == 401 {
            clear()
        } catch {
            phase = .offline(user)
        }
    }

    public func invalidate() {
        clear()
    }

    public func clear() {
        token = nil
        user = nil
        phase = .guest
        userCache?.removeUser()
        do {
            try storage?.removeToken()
            storageError = nil
        } catch {
            storageError = Self.authStorageError(from: error)
        }
    }

    private static func authStorageError(from error: Error) -> AuthTokenStorageError {
        error as? AuthTokenStorageError ?? .unavailable
    }
}
