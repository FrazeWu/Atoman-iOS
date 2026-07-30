import SwiftUI

struct MusicArtistDetailView: View {
    @Environment(MusicAppEnvironment.self) private var environment
    let artistID: String
    @State private var artist: MusicArtistDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if isLoading {
                    ProgressView().padding(.top, 100)
                } else if let errorMessage {
                    ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
                } else if let artist {
                    MusicArtworkView(
                        url: artist.resolvedImageURL,
                        fallbackURL: artist.fallbackImageURL,
                        cornerRadius: 140
                    )
                        .frame(maxWidth: 240)
                        .clipShape(Circle())
                    HStack(spacing: 12) {
                        Text(artist.name)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Button { toggleFavorite() } label: {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .frame(width: 44, height: 44)
                        }
                        .foregroundStyle(isFavorite ? Color.musicAccent : .primary)
                        .accessibilityLabel(isFavorite ? "取消收藏" : "收藏艺人")
                    }
                    if let bio = artist.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 620, alignment: .leading)
                    }
                    if !artist.albums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("专辑").font(.title3.bold())
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 18) {
                                ForEach(artist.albums) { album in
                                    NavigationLink(value: MusicDestination.album(album.id)) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            MusicArtworkView(url: album.coverURL)
                                            Text(album.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 24)
        }
        .background(Color.musicBackground)
        .navigationTitle("艺人")
        .musicInlineNavigationTitle()
        .task { await load() }
    }

    private func load() async {
        do {
            artist = try await environment.api.artist(id: artistID)
            await environment.refreshFavorites()
            errorMessage = nil
        } catch {
            errorMessage = "艺人加载失败"
        }
        isLoading = false
    }

    private func toggleFavorite() {
        let nextValue = !isFavorite
        Task {
            await environment.requestFavoriteArtist(id: artistID, isFavorite: nextValue)
        }
    }

    private var isFavorite: Bool {
        environment.favoriteArtistIDs.contains(artistID)
    }
}
