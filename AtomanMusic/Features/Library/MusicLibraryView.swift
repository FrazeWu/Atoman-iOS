import SwiftUI

struct MusicLibraryView: View {
    @Environment(MusicAppEnvironment.self) private var environment
    @State private var library = MusicLibraryState()
    @State private var actionErrorMessage: String?
    @State private var showCreatePlaylist = false
    @State private var playlistName = ""

    var body: some View {
        Group {
            if environment.authSession.isAuthenticated {
                libraryContent
            } else {
                ContentUnavailableView {
                    Label("登录查看资料库", systemImage: "books.vertical")
                } description: {
                    Text("查看收藏、歌单和播放历史")
                } actions: {
                    Button("登录") {
                        environment.authentication.present()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color.musicBackground)
        .navigationTitle("资料库")
        .alert("新建歌单", isPresented: $showCreatePlaylist) {
            TextField("歌单名称", text: $playlistName)
            Button("取消", role: .cancel) {}
            Button("创建") { createPlaylist() }
                .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .task(id: environment.authSession.token) {
            if environment.authSession.isAuthenticated {
                await load()
            } else {
                await environment.refreshFavorites()
            }
        }
    }

    private var libraryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if library.isLoading && !library.hasContent {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else {
                    if let actionErrorMessage {
                        Label(actionErrorMessage, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    playlistSection
                    favoriteAlbumSection
                    favoriteArtistSection
                    historySection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("歌单").font(.title3.bold())
                Spacer()
                Button {
                    playlistName = ""
                    showCreatePlaylist = true
                } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }
                .accessibilityLabel("新建歌单")
            }
            if library.playlists.isEmpty {
                Text("暂无歌单").foregroundStyle(.secondary)
            } else {
                ForEach(library.playlists) { playlist in
                    NavigationLink(value: MusicDestination.playlist(id: playlist.id, editable: !playlist.isFavorite)) {
                        HStack(spacing: 12) {
                            MusicArtworkView(url: playlist.coverURL, cornerRadius: 5).frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(playlist.name).foregroundStyle(.primary)
                                Text("\(playlist.songCount) 首").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            sectionFailure(.playlists, message: "歌单加载失败")
            loadMoreControl(.playlists)
        }
    }

    @ViewBuilder
    private var favoriteAlbumSection: some View {
        let albums = library.favoriteAlbums.compactMap(\.album).filter { environment.favoriteAlbumIDs.contains($0.id) }
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("收藏的专辑").font(.title3.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(albums) { album in
                            NavigationLink(value: MusicDestination.album(album.id)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    MusicArtworkView(url: album.coverURL).frame(width: 144, height: 144)
                                    Text(album.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                }
                                .frame(width: 144, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        sectionFailure(.albums, message: "专辑收藏加载失败")
            loadMoreControl(.albums)
    }

    @ViewBuilder
    private var favoriteArtistSection: some View {
        let artists = library.favoriteArtists.compactMap(\.artist).filter { environment.favoriteArtistIDs.contains($0.id) }
        if !artists.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("收藏的艺人").font(.title3.bold())
                ForEach(artists) { artist in
                    NavigationLink(value: MusicDestination.artist(artist.id)) {
                        HStack(spacing: 12) {
                            MusicArtworkView(url: artist.imageURL, cornerRadius: 28)
                                .frame(width: 56, height: 56).clipShape(Circle())
                            Text(artist.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        sectionFailure(.artists, message: "艺人收藏加载失败")
            loadMoreControl(.artists)
    }

    @ViewBuilder
    private var historySection: some View {
        let songs = library.history.compactMap(\.song)
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("播放历史").font(.title3.bold())
                ForEach(songs) { song in
                    MusicTrackRow(song: song, queue: songs)
                }
            }
        }
        sectionFailure(.history, message: "播放历史加载失败")
            loadMoreControl(.history)
    }

    private func load() async {
        let accountToken = environment.authSession.token
        await library.load(api: environment.api)
        guard environment.authSession.token == accountToken else { return }
        environment.synchronizeFavorites(
            favorite: library.favoritePlaylist,
            albums: library.favoriteAlbums,
            artists: library.favoriteArtists
        )
    }

    private func createPlaylist() {
        let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            do {
                let playlist = try await environment.api.createPlaylist(name: name)
                library.playlists.insert(playlist, at: 0)
            } catch {
                actionErrorMessage = "歌单创建失败"
            }
        }
    }

    @ViewBuilder
    private func loadMoreControl(_ section: MusicLibrarySection) -> some View {
        if library.moreSections.contains(section) {
            Button(library.loadingMoreSections.contains(section) ? "加载中…" : "加载更多") {
                Task {
                    await library.loadMore(section, api: environment.api)
                    environment.synchronizeFavorites(
                        favorite: library.favoritePlaylist,
                        albums: library.favoriteAlbums,
                        artists: library.favoriteArtists
                    )
                }
            }
            .buttonStyle(.bordered)
            .disabled(library.loadingMoreSections.contains(section))
        }
    }

    @ViewBuilder
    private func sectionFailure(_ section: MusicLibrarySection, message: String) -> some View {
        if library.failedSections.contains(section) {
            HStack {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("重试")
            }
        }
    }
}
