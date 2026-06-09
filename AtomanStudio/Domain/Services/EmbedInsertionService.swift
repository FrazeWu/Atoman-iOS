import Foundation

public enum EmbedInsertionService {
    public static func post(id: String) -> String {
        ":::post{id=\"\(id)\"}\n:::"
    }

    public static func music(id: String) -> String {
        ":::music{id=\"\(id)\"}\n:::"
    }

    public static func video(id: String) -> String {
        ":::video{id=\"\(id)\"}\n:::"
    }
}
