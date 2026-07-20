import Foundation

public struct AuthUser: Codable, Equatable, Sendable {
    public let id: Int
    public let uuid: String
    public let username: String
    public let email: String
    public let role: String
    public let displayName: String?
    public let avatarURL: String?
    public let isActive: Bool
    public let onboardingCompletedAt: String?

    public init(
        id: Int,
        uuid: String,
        username: String,
        email: String,
        role: String,
        displayName: String? = nil,
        avatarURL: String? = nil,
        isActive: Bool = true,
        onboardingCompletedAt: String? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.username = username
        self.email = email
        self.role = role
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.isActive = isActive
        self.onboardingCompletedAt = onboardingCompletedAt
    }

    public var resolvedDisplayName: String {
        guard let displayName, !displayName.isEmpty else { return username }
        return displayName
    }

    enum CodingKeys: String, CodingKey {
        case id, uuid, username, email, role
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case isActive = "is_active"
        case onboardingCompletedAt = "onboarding_completed_at"
    }
}

public struct AuthSessionPayload: Codable, Equatable, Sendable {
    public let token: String
    public let user: AuthUser

    public init(token: String, user: AuthUser) {
        self.token = token
        self.user = user
    }
}

public enum AuthAPIError: Error, Equatable, Sendable {
    case server(statusCode: Int, code: String?, message: String)
    case invalidResponse
}
