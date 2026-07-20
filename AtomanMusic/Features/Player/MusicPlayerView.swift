import SwiftUI

struct MusicPlayerView: View {
    @Environment(MusicAppEnvironment.self) private var environment

    var body: some View {
        @Bindable var player = environment.player

        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let song = player.currentSong {
                        MusicArtworkView(url: song.resolvedCoverURL)
                            .frame(maxWidth: 360)
                            .padding(.horizontal, 24)

                        if player.isBuffering {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("正在缓冲").foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }

                        if let errorMessage = player.errorMessage {
                            HStack(spacing: 10) {
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    player.retryCurrentSong()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("重试播放")
                            }
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title)
                                    .font(.title2.weight(.bold))
                                    .lineLimit(2)
                                Text(song.artistText)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                toggleFavorite(songID: song.id)
                            } label: {
                                Image(systemName: isFavorite ? "heart.fill" : "heart")
                                    .font(.title3)
                                    .foregroundStyle(isFavorite ? Color.musicAccent : .primary)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(isFavorite ? "取消收藏" : "收藏歌曲")
                        }

                        VStack(spacing: 6) {
                            Slider(
                                value: Binding(
                                    get: { player.currentTime },
                                    set: { player.seek(to: $0) }
                                ),
                                in: 0...max(player.duration, 1)
                            )
                            HStack {
                                Text(player.currentTime.musicTimestamp)
                                Spacer()
                                Text((max(player.duration - player.currentTime, 0)).musicTimestamp)
                                    .accessibilityLabel("剩余 \((max(player.duration - player.currentTime, 0)).musicTimestamp)")
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button { player.cyclePlaybackMode() } label: {
                                Image(systemName: player.playbackMode.systemImage)
                                    .foregroundStyle(player.playbackMode == .sequential ? .secondary : Color.musicAccent)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("切换播放模式")
                            Spacer()
                            Button { player.playPrevious() } label: {
                                Image(systemName: "backward.end.fill").font(.title2)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("上一首")
                            Spacer()
                            Button { player.togglePlayback() } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.musicBackground)
                                    .frame(width: 62, height: 62)
                                    .background(.primary, in: Circle())
                            }
                            Spacer()
                            Button { player.playNext() } label: {
                                Image(systemName: "forward.end.fill").font(.title2)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("下一首")
                            Spacer()
                            Button { player.isShowingQueue = true } label: {
                                Image(systemName: "list.bullet").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("播放队列")
                        }
                        .buttonStyle(.plain)

                        Button {
                            player.isShowingLyrics = true
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("歌词").font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.up")
                                }
                                let preview = MusicLyricsParser.parse(song.lyrics ?? "").prefix(2)
                                if preview.isEmpty {
                                    Text("暂无歌词").foregroundStyle(.secondary)
                                } else {
                                    ForEach(Array(preview)) { line in
                                        Text(line.text).lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color.musicSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color.musicBackground)
            .overlay(alignment: .top) {
                if let message = player.queueActionMessage {
                    MusicQueueActionBanner(message: message)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: player.queueActionMessage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        player.isShowingPlayer = false
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("收起播放器")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("正在播放").font(.caption2).foregroundStyle(.secondary)
                        Text(player.currentSong?.album?.title ?? "Atoman Music")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    MusicRoutePickerView()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("AirPlay")
                }
            }
            .sheet(isPresented: $player.isShowingLyrics) {
                MusicLyricsView()
                    .environment(environment)
            }
            .sheet(isPresented: $player.isShowingQueue) {
                MusicQueueView()
                    .environment(environment)
            }
            .sheet(isPresented: playerAuthenticationBinding, onDismiss: {
                environment.authentication.dismiss()
            }) {
                MusicAccountSheet()
                    .environment(environment)
            }
        }
    }

    private var playerAuthenticationBinding: Binding<Bool> {
        Binding(
            get: { environment.presentsAuthenticationInPlayer },
            set: { isPresented in
                if !isPresented {
                    environment.authentication.dismiss()
                }
            }
        )
    }

    private func toggleFavorite(songID: String) {
        let nextValue = !isFavorite
        Task {
            await environment.requestFavoriteSong(id: songID, isFavorite: nextValue)
        }
    }

    private var isFavorite: Bool {
        guard let songID = environment.player.currentSong?.id else { return false }
        return environment.favoriteSongIDs.contains(songID)
    }
}

private extension MusicPlaybackMode {
    var systemImage: String {
        switch self {
        case .sequential: "arrow.right"
        case .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        case .shuffle: "shuffle"
        }
    }
}

extension TimeInterval {
    var musicTimestamp: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let totalSeconds = Int(self)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
