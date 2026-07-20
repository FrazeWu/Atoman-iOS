import Foundation

public enum MusicWebConfiguration {
    private static let fallbackBaseURL = URL(string: "https://atoman.org")!

    public static func registrationURL(infoDictionary: [String: Any]) -> URL {
        baseURL(infoDictionary: infoDictionary).appending(path: "register")
    }

    public static func passwordResetURL(infoDictionary: [String: Any]) -> URL {
        baseURL(infoDictionary: infoDictionary).appending(path: "forgot-password")
    }

    private static func baseURL(infoDictionary: [String: Any]) -> URL {
        guard let rawValue = infoDictionary["AtomanWebBaseURL"] as? String,
              let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else {
            return fallbackBaseURL
        }
        return url
    }
}
