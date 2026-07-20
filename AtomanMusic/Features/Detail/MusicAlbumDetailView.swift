import SwiftUI

struct MusicAlbumDetailView: View {
    @Environment(MusicAppEnvironment.self) private var environment
    let albumID: String
    @State private var album: MusicAlbum?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView().padding(.top, 100)
                } else if let errorMessage {
                    ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
                } else if let album {
                    MusicArtworkView(url: album.resolvedCoverURL)
                        .frame(maxWidth: 280)
                    VStack(spacing: 6) {
                        Text(album.title).font(.title2.bold()).multilineTextAlignment(.center)
                        HStack(spacing: 4) {
                            ForEach(album.artists) { artist in
                                NavigationLink(value: MusicDestination.artist(artist.id)) {
                                    Text(artist.name).font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                        .foregroundStyle(.secondary)
                        if let year = album.year, year > 0 {
                            Text(String(year)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 18) {
                        Button {
                            environment.player.play(songs: album.songs, startingAt: album.songs.first?.id)
                        } label: {
                            Label("播放", systemImage: "play.fill")
                                .fontWeight(.semibold)
                                .frame(minWidth: 100, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(album.songs.isEmpty)

                        Button { toggleFavorite() } label: {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .frame(width: 44, height: 44)
                        }
                        .foregroundStyle(isFavorite ? Color.musicAccent : .primary)
                        .accessibilityLabel(isFavorite ? "取消收藏" : "收藏专辑")
                    }
                    LazyVStack(spacing: 2) {
                        ForEach(Array(album.songs.enumerated()), id: \.element.id) { index, song in
                            MusicTrackRow(song: song, queue: album.songs, number: index + 1)
                                .padding(.vertical, 3)
                        }
                    }
                }
            }
            .padding(20)
            .padding(.bottom, environment.player.currentSong == nil ? 24 : 112)
        }
        .background(Color.musicBackground)
        .navigationTitle("专辑")
        .musicInlineNavigationTitle()
        .task { await load() }
    }

    private func load() async {
        do {
            album = try await environment.api.album(id: albumID)
            await environment.refreshFavorites()
            errorMessage = nil
        } catch {
            errorMessage = "专辑加载失败"
        }
        isLoading = false
    }

    private func toggleFavorite() {
        let nextValue = !isFavorite
        Task {
            await environment.requestFavoriteAlbum(id: albumID, isFavorite: nextValue)
        }
    }

    private var isFavorite: Bool {
        environment.favoriteAlbumIDs.contains(albumID)
    }
}
