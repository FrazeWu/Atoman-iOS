import Foundation
import Observation

@Observable
public final class AuthSessionStore {
    private enum Keys {
        static let token = "atoman.auth.token"
    }

    public var token: String? {
        didSet {
            if let token {
                UserDefaults.standard.set(token, forKey: Keys.token)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.token)
            }
        }
    }

    public convenience init() {
        self.init(token: UserDefaults.standard.string(forKey: Keys.token))
    }

    public init(token: String?) {
        self.token = token
    }

    public var isAuthenticated: Bool {
        token?.isEmpty == false
    }

    public func clear() {
        token = nil
    }
}
