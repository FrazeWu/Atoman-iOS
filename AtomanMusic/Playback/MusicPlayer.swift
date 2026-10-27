import Foundation
import Observation
#if os(iOS)
import MediaPlayer
#endif

@MainActor
@Observable
public final class MusicPlayer {
    public private(set) var currentSong: MusicSong?
    public private(set) var songs: [MusicSong] = []
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var errorMessage: String?
    public private(set) var queueActionMessage: String?
    public var isShowingPlayer = false
    public var isShowingLyrics = false
    public var isShowingQueue = false
    public var playbackMode: MusicPlaybackMode = .sequential {
        didSet {
            queue.mode = playbackMode
            synchronizeQueueState()
            persistPlaybackState()
        }
    }

    @ObservationIgnored private let engine: MusicPlaybackEngine
    @ObservationIgnored private let recordPlay: ((String) async -> Void)?
    @ObservationIgnored private let stateStore: MusicPlaybackStateStore?
    @ObservationIgnored private let legacySyncPlayback: ((MusicPlaybackSnapshot) async -> Void)?
    @ObservationIgnored private let nowPlayingPublisher: MusicNowPlayingPublishing?
    @ObservationIgnored private var queue = MusicPlaybackQueue()
    @ObservationIgnored private var recordPolicy = MusicPlaybackRecordPolicy()
    @ObservationIgnored private var wasPlayingBeforeInterruption = false
    @ObservationIgnored private var isCurrentSongLoaded = false
    @ObservationIgnored private var lastPersistedTime: TimeInterval = 0
    @ObservationIgnored private var queueMessageTask: Task<Void, Never>?
    @ObservationIgnored private var remoteSessionSave: ((MusicPlaybackSnapshot, Date) async -> Void)?
    @ObservationIgnored private var remoteProgressSave: ((String, Double, Double, Bool, Date) async -> Void)?
    @ObservationIgnored private var didInteractLocally = false
    @ObservationIgnored private var suppressSignedOutSnapshot = false
    @ObservationIgnored private var applyingRemoteSession = false
    @ObservationIgnored private var lastRemoteSessionSave = Date.distantPast
    @ObservationIgnored private var lastRemoteProgressSave = Date.distantPast

    public var upcomingSongs: [MusicSong] {
        guard let currentSong,
              let currentIndex = songs.firstIndex(where: { $0.id == currentSong.id }),
              currentIndex + 1 < songs.count else {
            return []
        }
        return Array(songs[(currentIndex + 1)...])
    }

    public convenience init(recordPlay: ((String) async -> Void)? = nil, syncPlayback: ((MusicPlaybackSnapshot) async -> Void)? = nil) {
        self.init(
            engine: AVMusicPlaybackEngine(),
            recordPlay: recordPlay,
            syncPlayback: syncPlayback,
            stateStore: UserDefaultsMusicPlaybackStateStore(),
            nowPlayingPublisher: SystemMusicNowPlayingPublisher()
        )
    }

    public init(
        engine: MusicPlaybackEngine,
        recordPlay: ((String) async -> Void)? = nil,
        syncPlayback: ((MusicPlaybackSnapshot) async -> Void)? = nil,
        stateStore: MusicPlaybackStateStore? = nil,
        nowPlayingPublisher: MusicNowPlayingPublishing? = nil
    ) {
        self.engine = engine
        self.recordPlay = recordPlay
        self.legacySyncPlayback = syncPlayback
        self.stateStore = stateStore
        self.nowPlayingPublisher = nowPlayingPublisher
        engine.onTimeUpdate = { [weak self] currentTime, duration in
            self?.handleTimeUpdate(currentTime: currentTime, duration: duration)
        }
        engine.onPlaybackEnded = { [weak self] in
            self?.saveRemoteProgress(completed: true, force: true)
            self?.playNext()
        }
        engine.onBufferingChanged = { [weak self] isBuffering in
            self?.isBuffering = isBuffering
        }
        engine.onPlaybackFailed = { [weak self] message in
            self?.isPlaying = false
            self?.isBuffering = false
            self?.errorMessage = message
            self?.updateNowPlayingInfo()
        }
        engine.onInterruptionBegan = { [weak self] in
            guard let self else { return }
            wasPlayingBeforeInterruption = isPlaying
            isPlaying = false
            updateNowPlayingInfo()
        }
        engine.onInterruptionEnded = { [weak self] shouldResume in
            guard let self else { return }
            if shouldResume && wasPlayingBeforeInterruption {
                engine.play()
                isPlaying = true
            }
            wasPlayingBeforeInterruption = false
            updateNowPlayingInfo()
        }
        engine.onOutputDisconnected = { [weak self] in
            guard let self else { return }
            engine.pause()
            isPlaying = false
            updateNowPlayingInfo()
        }
#if os(iOS)
        configureRemoteCommands()
#endif
        restorePlaybackState()
    }

    // Install sync only for an authenticated account. The local snapshot stays
    // available offline and server restores never autoplay audio.
    public func enableRemoteSync(
        session: @escaping (MusicPlaybackSnapshot, Date) async -> Void,
        progress: @escaping (String, Double, Double, Bool, Date) async -> Void
    ) {
        remoteSessionSave = session
        remoteProgressSave = progress
        suppressSignedOutSnapshot = false
        lastRemoteSessionSave = .distantPast
        lastRemoteProgressSave = .distantPast
        if didInteractLocally {
            persistPlaybackState(forceRemote: true)
            saveRemoteProgress(force: true)
        }
    }

    public func disableRemoteSync() {
        remoteSessionSave = nil
        remoteProgressSave = nil
    }

    public func handleLogout() {
        disableRemoteSync()
        // Preserve the in-memory queue and uninterrupted playback, as on web;
        // prevent the signed-out account's persisted queue from reappearing
        // when someone else launches the app later.
        stateStore?.clear()
        suppressSignedOutSnapshot = true
        didInteractLocally = false
    }

    @discardableResult
    public func restoreRemoteSession(_ session: MusicRemotePlaybackSession) -> Bool {
        guard !didInteractLocally, !isPlaying, !isCurrentSongLoaded else { return false }
        let available = session.queue.filter { $0.audioURL?.isEmpty == false }
        guard !available.isEmpty,
              available.contains(where: { $0.id == session.currentSongID }) else { return false }
        applyingRemoteSession = true
        switch session.playbackMode {
        case "single": playbackMode = .repeatOne
        case "random": playbackMode = .shuffle
        default: playbackMode = .repeatAll
        }
        queue.mode = playbackMode
        queue.load(available, startingAt: session.currentSongID, preservingOrder: true)
        synchronizeQueueState()
        currentTime = max(0, session.positionSeconds)
        lastPersistedTime = currentTime
        duration = currentSong.map { Double($0.durationSeconds ?? 0) } ?? 0
        isPlaying = false
        isCurrentSongLoaded = false
        persistPlaybackState()
        updateNowPlayingInfo()
        applyingRemoteSession = false
        return true
    }

    // Backward-compatible snapshot restore, with the same no-autoplay and
    // no-overwrite guarantees as the current wire-format session restore.
    public func restoreRemotePlayback(_ snapshot: MusicPlaybackSnapshot) {
        guard !didInteractLocally, !isPlaying, !isCurrentSongLoaded,
              !snapshot.songs.isEmpty,
              snapshot.songs.contains(where: { $0.id == snapshot.currentSongID }) else { return }
        applyingRemoteSession = true
        defer { applyingRemoteSession = false }
        playbackMode = snapshot.playbackMode
        queue.mode = snapshot.playbackMode
        queue.load(snapshot.songs, startingAt: snapshot.currentSongID, preservingOrder: true)
        synchronizeQueueState()
        currentTime = max(0, snapshot.currentTime)
        lastPersistedTime = currentTime
        isPlaying = false
        isCurrentSongLoaded = false
        persistPlaybackState()
        updateNowPlayingInfo()
    }

    public func flushRemotePlayback() {
        persistPlaybackState(forceRemote: true)
        saveRemoteProgress(force: true)
    }

    public func play(songs: [MusicSong], startingAt songID: String? = nil) {
        didInteractLocally = true
        suppressSignedOutSnapshot = false
        queue.mode = playbackMode
        queue.load(songs, startingAt: songID)
        synchronizeQueueState()
        loadCurrentSong()
    }

    public func playNext(_ song: MusicSong) {
        didInteractLocally = true
        guard currentSong != nil else {
            play(songs: [song], startingAt: song.id)
            return
        }
        guard queue.prioritize(song) else { return }
        synchronizeQueueState()
        persistPlaybackState()
        showQueueActionMessage("已设为下一首")
    }

    public func enqueue(_ song: MusicSong) {
        didInteractLocally = true
        guard currentSong != nil else {
            play(songs: [song], startingAt: song.id)
            return
        }
        guard queue.enqueue(song) else { return }
        synchronizeQueueState()
        persistPlaybackState()
        showQueueActionMessage("已加入队列")
    }

    public func moveUpcoming(from sourceIndex: Int, to destinationIndex: Int) {
        didInteractLocally = true
        guard queue.moveUpcoming(from: sourceIndex, to: destinationIndex) else { return }
        synchronizeQueueState()
        persistPlaybackState()
    }

    public func removeUpcoming(at index: Int) {
        didInteractLocally = true
        guard queue.removeUpcoming(at: index) else { return }
        synchronizeQueueState()
        persistPlaybackState()
    }

    public func clearUpcoming() {
        didInteractLocally = true
        guard queue.clearUpcoming() else { return }
        synchronizeQueueState()
        persistPlaybackState()
    }

    public func playQueuedSong(id: String) {
        didInteractLocally = true
        guard queue.select(songID: id) != nil else { return }
        synchronizeQueueState()
        loadCurrentSong()
    }

    public func togglePlayback() {
        didInteractLocally = true
        guard currentSong != nil else { return }
        if !isCurrentSongLoaded {
            loadCurrentSong(resumeAt: currentTime)
            return
        }
        if isPlaying {
            engine.pause()
            isPlaying = false
        } else {
            engine.play()
            isPlaying = true
        }
        persistPlaybackState(forceRemote: true)
        saveRemoteProgress(force: true)
        updateNowPlayingInfo()
    }

    public func playNext() {
        didInteractLocally = true
        guard let next = queue.moveNext() else {
            engine.pause()
            isPlaying = false
            updateNowPlayingInfo()
            return
        }
        currentSong = next
        loadCurrentSong()
    }

    public func playPrevious() {
        didInteractLocally = true
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let previous = queue.movePrevious() else {
            seek(to: 0)
            return
        }
        currentSong = previous
        loadCurrentSong()
    }

    public func seek(to time: TimeInterval) {
        didInteractLocally = true
        let target = min(max(0, time), duration > 0 ? duration : time)
        engine.seek(to: target)
        currentTime = target
        persistPlaybackState(forceRemote: true)
        saveRemoteProgress(force: true)
        updateNowPlayingInfo()
    }

    public func cyclePlaybackMode() {
        didInteractLocally = true
        let modes = MusicPlaybackMode.allCases
        guard let index = modes.firstIndex(of: playbackMode) else { return }
        playbackMode = modes[(index + 1) % modes.count]
        persistPlaybackState(forceRemote: true)
    }

    public func retryCurrentSong() {
        didInteractLocally = true
        guard currentSong != nil else { return }
        loadCurrentSong(resumeAt: currentTime)
    }

    private func loadCurrentSong(resumeAt: TimeInterval = 0) {
        currentTime = max(0, resumeAt)
        duration = 0
        isBuffering = false
        errorMessage = nil
        recordPolicy = MusicPlaybackRecordPolicy()
        guard let currentSong,
              let rawURL = currentSong.audioURL,
              let url = URL(string: rawURL) else {
            isPlaying = false
            errorMessage = "这首歌暂时无法播放"
            return
        }
        engine.load(url: url)
        isCurrentSongLoaded = true
        if currentTime > 0 {
            engine.seek(to: currentTime)
        }
        engine.play()
        isPlaying = true
        persistPlaybackState(forceRemote: true)
        updateNowPlayingInfo()
    }

    private func handleTimeUpdate(currentTime: TimeInterval, duration: TimeInterval) {
        self.currentTime = max(0, currentTime)
        self.duration = max(0, duration)
        if abs(self.currentTime - lastPersistedTime) >= 5 {
            lastPersistedTime = self.currentTime
            persistPlaybackState()
        }
        saveRemoteProgress()
        guard let songID = currentSong?.id,
              recordPolicy.shouldRecord(songID: songID, elapsed: currentTime),
              let recordPlay else {
            updateNowPlayingInfo()
            return
        }
        Task { await recordPlay(songID) }
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard let currentSong else {
            nowPlayingPublisher?.clear()
            return
        }
        nowPlayingPublisher?.update(MusicNowPlayingMetadata(
            title: currentSong.title,
            artist: currentSong.artistText,
            album: currentSong.album?.title,
            artworkURL: currentSong.resolvedCoverURL.flatMap(URL.init(string:)),
            duration: duration,
            currentTime: currentTime,
            isPlaying: isPlaying
        ))
    }

    private func synchronizeQueueState() {
        songs = queue.songs
        currentSong = queue.currentSong
    }

    private func showQueueActionMessage(_ message: String) {
        queueMessageTask?.cancel()
        queueActionMessage = message
        queueMessageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.queueActionMessage = nil
        }
    }

    private func restorePlaybackState() {
        guard let snapshot = stateStore?.load(),
              !snapshot.songs.isEmpty else { return }
        playbackMode = snapshot.playbackMode
        queue.mode = snapshot.playbackMode
        queue.load(snapshot.songs, startingAt: snapshot.currentSongID, preservingOrder: true)
        synchronizeQueueState()
        currentTime = max(0, snapshot.currentTime)
        lastPersistedTime = currentTime
        isPlaying = false
        isCurrentSongLoaded = false
        updateNowPlayingInfo()
    }

    private func persistPlaybackState(forceRemote: Bool = false) {
        guard let currentSong else { return }
        let snapshot = MusicPlaybackSnapshot(
            songs: songs,
            currentSongID: currentSong.id,
            currentTime: currentTime,
            playbackMode: playbackMode
        )
        if !suppressSignedOutSnapshot { stateStore?.save(snapshot) }
        if didInteractLocally, !applyingRemoteSession, let legacySyncPlayback {
            Task { await legacySyncPlayback(snapshot) }
        }
        guard didInteractLocally, !applyingRemoteSession,
              let remoteSessionSave else { return }
        let now = Date()
        guard forceRemote || now.timeIntervalSince(lastRemoteSessionSave) >= 12 else { return }
        lastRemoteSessionSave = now
        Task { await remoteSessionSave(snapshot, now) }
    }

    private func saveRemoteProgress(completed: Bool = false, force: Bool = false) {
        guard didInteractLocally, !applyingRemoteSession,
              let songID = currentSong?.id,
              let remoteProgressSave else { return }
        let now = Date()
        guard force || (isPlaying && now.timeIntervalSince(lastRemoteProgressSave) >= 12) else { return }
        lastRemoteProgressSave = now
        let position = currentTime
        let length = duration
        Task { await remoteProgressSave(songID, position, length, completed, now) }
    }

#if os(iOS)
    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if self?.isPlaying == false { self?.togglePlayback() }
            }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if self?.isPlaying == true { self?.togglePlayback() }
            }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: positionEvent.positionTime) }
            return .success
        }
    }
#endif
}
