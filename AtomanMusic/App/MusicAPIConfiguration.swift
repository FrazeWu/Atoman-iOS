import Foundation

public enum MusicAPIConfiguration {
    public static func baseURL(infoDictionary: [String: Any]) -> URL {
        if let rawValue = infoDictionary["AtomanAPIBaseURL"] as? String,
           let configuredURL = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
           configuredURL.scheme != nil {
            return configuredURL
        }
        return URL(string: "https://api.atoman.org/api/v1")!
    }
}
