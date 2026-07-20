import AVFoundation
import Foundation

@MainActor
public protocol MusicPlaybackEngine: AnyObject {
    var onTimeUpdate: ((TimeInterval, TimeInterval) -> Void)? { get set }
    var onPlaybackEnded: (() -> Void)? { get set }
    var onBufferingChanged: ((Bool) -> Void)? { get set }
    var onPlaybackFailed: ((String) -> Void)? { get set }
    var onInterruptionBegan: (() -> Void)? { get set }
    var onInterruptionEnded: ((Bool) -> Void)? { get set }
    var onOutputDisconnected: (() -> Void)? { get set }

    func load(url: URL)
    func play()
    func pause()
    func seek(to time: TimeInterval)
}

@MainActor
public final class AVMusicPlaybackEngine: MusicPlaybackEngine {
    public var onTimeUpdate: ((TimeInterval, TimeInterval) -> Void)?
    public var onPlaybackEnded: (() -> Void)?
    public var onBufferingChanged: ((Bool) -> Void)?
    public var onPlaybackFailed: ((String) -> Void)?
    public var onInterruptionBegan: (() -> Void)?
    public var onInterruptionEnded: ((Bool) -> Void)?
    public var onOutputDisconnected: (() -> Void)?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
#if os(iOS)
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
#endif

    public init() {
#if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        observeAudioSession()
#endif
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                self?.onBufferingChanged?(player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let duration = self.player.currentItem.map { CMTimeGetSeconds($0.duration) } ?? 0
                self.onTimeUpdate?(CMTimeGetSeconds(time), duration.isFinite ? duration : 0)
            }
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
        }
#if os(iOS)
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
#endif
    }

    public func load(url: URL) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                self?.onPlaybackFailed?(item.error?.localizedDescription ?? "音频加载失败")
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onPlaybackEnded?()
            }
        }
        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in
                self?.onPlaybackFailed?(error?.localizedDescription ?? "音频播放失败")
            }
        }
    }

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func seek(to time: TimeInterval) {
        player.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600))
    }

#if os(iOS)
    private func observeAudioSession() {
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            Task { @MainActor [weak self] in
                switch type {
                case .began:
                    self?.onInterruptionBegan?()
                case .ended:
                    let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                    self?.onInterruptionEnded?(options.contains(.shouldResume))
                @unknown default:
                    break
                }
            }
        }
        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable else { return }
            Task { @MainActor [weak self] in
                self?.onOutputDisconnected?()
            }
        }
    }
#endif
}
