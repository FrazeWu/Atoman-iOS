import Foundation
#if os(iOS)
import MediaPlayer
import UIKit
#endif

public struct MusicNowPlayingMetadata: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let duration: TimeInterval
    public let currentTime: TimeInterval
    public let isPlaying: Bool
}

@MainActor
public protocol MusicNowPlayingPublishing: AnyObject {
    func update(_ metadata: MusicNowPlayingMetadata)
    func clear()
}

@MainActor
public final class SystemMusicNowPlayingPublisher: MusicNowPlayingPublishing {
#if os(iOS)
    private var metadata: MusicNowPlayingMetadata?
    private var artwork: UIImage?
    private var artworkURL: URL?
    private var artworkTask: Task<Void, Never>?
#endif

    public init() {}

    public func update(_ metadata: MusicNowPlayingMetadata) {
#if os(iOS)
        self.metadata = metadata
        publish()
        guard metadata.artworkURL != artworkURL else { return }
        artworkURL = metadata.artworkURL
        artwork = nil
        artworkTask?.cancel()
        guard let url = metadata.artworkURL else {
            publish()
            return
        }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let image = UIImage(data: data),
                  self?.artworkURL == url else { return }
            self?.artwork = image
            self?.publish()
        }
#endif
    }

    public func clear() {
#if os(iOS)
        artworkTask?.cancel()
        metadata = nil
        artwork = nil
        artworkURL = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
#endif
    }

#if os(iOS)
    private func publish() {
        guard let metadata else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.title,
            MPMediaItemPropertyArtist: metadata.artist,
            MPMediaItemPropertyPlaybackDuration: metadata.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: metadata.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: metadata.isPlaying ? 1.0 : 0.0,
        ]
        if let album = metadata.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
#endif
}
