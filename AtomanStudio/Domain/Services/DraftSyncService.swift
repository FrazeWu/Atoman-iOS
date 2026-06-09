import Foundation

public enum DraftSource {
    case local
    case remote
}

public struct DraftSyncCandidate {
    public let source: DraftSource
    public let payload: EditorDraftPayload
    public let savedAt: Date

    public init(source: DraftSource, payload: EditorDraftPayload, savedAt: Date) {
        self.source = source
        self.payload = payload
        self.savedAt = savedAt
    }
}

public enum DraftSyncState: Equatable {
    case idle
    case syncing
    case synced
    case error
}

public struct DraftSyncService {
    public var clock: () -> Date

    public init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    public func pickRecoveryCandidate(local: DraftSyncCandidate?, remote: DraftSyncCandidate?) -> DraftSyncCandidate? {
        switch (local, remote) {
        case let (l?, r?):
            return l.savedAt >= r.savedAt ? l : r
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        default:
            return nil
        }
    }
}
