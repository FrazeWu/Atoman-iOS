import AtomanCore
import Foundation

public enum AuthenticationGateState: Equatable {
    case authenticated
    case requiresLogin

    public static func resolve(isAuthenticated: Bool) -> AuthenticationGateState {
        isAuthenticated ? .authenticated : .requiresLogin
    }

    public static func resolve(session: AuthSessionStore) -> AuthenticationGateState {
        resolve(isAuthenticated: session.isAuthenticated)
    }
}
