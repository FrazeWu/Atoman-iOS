import Observation

public enum MusicPendingAuthAction: Equatable, Sendable {
    case favoriteSong(id: String, isFavorite: Bool)
    case favoriteAlbum(id: String, isFavorite: Bool)
    case favoriteArtist(id: String, isFavorite: Bool)
}

@MainActor
@Observable
public final class MusicAuthenticationCoordinator {
    public var isPresented = false
    public private(set) var pendingAction: MusicPendingAuthAction?

    public init() {}

    public func present(for action: MusicPendingAuthAction? = nil) {
        pendingAction = action
        isPresented = true
    }

    public func takePendingAction() -> MusicPendingAuthAction? {
        defer { pendingAction = nil }
        return pendingAction
    }

    public func dismiss(clearPendingAction: Bool = true) {
        isPresented = false
        if clearPendingAction {
            pendingAction = nil
        }
    }
}
