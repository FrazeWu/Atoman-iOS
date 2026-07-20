import SwiftUI

struct MusicTrackRow: View {
    @Environment(MusicAppEnvironment.self) private var environment
    let song: MusicSong
    let queue: [MusicSong]
    let number: Int?
    @State private var showPlaylistPicker = false

    init(song: MusicSong, queue: [MusicSong], number: Int? = nil) {
        self.song = song
        self.queue = queue
        self.number = number
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                environment.player.play(songs: queue, startingAt: song.id)
            } label: {
                HStack(spacing: 12) {
                    if let number {
                        Text(String(number))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                    } else {
                        MusicArtworkView(url: song.resolvedCoverURL, cornerRadius: 4)
                            .frame(width: 44, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title).lineLimit(1)
                        Text(song.artistText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    environment.player.playNext(song)
                } label: {
                    Label("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .disabled(isCurrentSong)

                Button {
                    environment.player.enqueue(song)
                } label: {
                    Label("加入队列", systemImage: "text.badge.plus")
                }
                .disabled(isCurrentSong)

                Divider()

                Button {
                    toggleFavorite()
                } label: {
                    Label(isFavorite ? "取消收藏" : "收藏歌曲", systemImage: isFavorite ? "heart.slash" : "heart")
                }
                if environment.authSession.isAuthenticated {
                    Button {
                        showPlaylistPicker = true
                    } label: {
                        Label("添加到歌单", systemImage: "text.badge.plus")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("更多操作")
        }
        .sheet(isPresented: $showPlaylistPicker) {
            AddToPlaylistView(songID: song.id)
                .environment(environment)
        }
    }

    private var isFavorite: Bool {
        environment.favoriteSongIDs.contains(song.id)
    }

    private var isCurrentSong: Bool {
        environment.player.currentSong?.id == song.id
    }

    private func toggleFavorite() {
        let nextValue = !isFavorite
        Task {
            await environment.requestFavoriteSong(id: song.id, isFavorite: nextValue)
        }
    }
}

private struct AddToPlaylistView: View {
    @Environment(MusicAppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let songID: String
    @State private var playlists: [MusicPlaylist] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
                } else if playlists.isEmpty {
                    ContentUnavailableView("暂无歌单", systemImage: "music.note.list")
                } else {
                    List(playlists) { playlist in
                        Button {
                            add(to: playlist)
                        } label: {
                            HStack(spacing: 12) {
                                MusicArtworkView(url: playlist.coverURL, cornerRadius: 4)
                                    .frame(width: 44, height: 44)
                                Text(playlist.name)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("添加到歌单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            playlists = try await environment.api.playlists()
            errorMessage = nil
        } catch {
            errorMessage = "歌单加载失败"
        }
        isLoading = false
    }

    private func add(to playlist: MusicPlaylist) {
        Task {
            do {
                try await environment.api.addSong(id: songID, toPlaylist: playlist.id)
                dismiss()
            } catch {
                errorMessage = "添加失败"
            }
        }
    }
}
