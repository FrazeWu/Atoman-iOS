import SwiftUI

struct MusicSearchView: View {
    @Environment(MusicAppEnvironment.self) private var environment
    @State private var query = ""
    @State private var results: MusicSearchResults?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var currentPage = 1
    @State private var activeQuery = ""
    @State private var errorMessage: String?
    @State private var loadMoreError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else if let errorMessage {
                    ContentUnavailableView(errorMessage, systemImage: "exclamationmark.magnifyingglass")
                } else if let results {
                    resultSections(results)
                    if results.meta?.hasNextPage == true {
                        Button(isLoadingMore ? "加载中…" : "加载更多") {
                            Task { await loadMore() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoadingMore)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("music-search-load-more")
                    }
                    if let loadMoreError {
                        Text(loadMoreError).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView("搜索音乐", systemImage: "magnifyingglass")
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.musicBackground)
        .navigationTitle("搜索")
        .searchable(text: $query, prompt: "歌曲、专辑、艺人或歌单")
        .task(id: query) { await search() }
    }

    @ViewBuilder
    private func resultSections(_ results: MusicSearchResults) -> some View {
        if results.songs.isEmpty && results.albums.isEmpty && results.artists.isEmpty && results.playlists.isEmpty {
            ContentUnavailableView("没有找到结果", systemImage: "music.note")
                .padding(.top, 80)
        } else {
            if !results.songs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("歌曲").font(.title3.bold())
                    ForEach(results.songs) { song in
                        MusicTrackRow(song: song, queue: results.songs)
                    }
                }
            }
            if !results.albums.isEmpty {
                horizontalAlbums(results.albums)
            }
            if !results.artists.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("艺人").font(.title3.bold())
                    ForEach(results.artists) { artist in
                        NavigationLink(value: MusicDestination.artist(artist.id)) {
                            HStack(spacing: 12) {
                                MusicArtworkView(url: artist.imageURL, cornerRadius: 28)
                                    .frame(width: 56, height: 56)
                                    .clipShape(Circle())
                                Text(artist.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !results.playlists.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("歌单").font(.title3.bold())
                    ForEach(results.playlists) { playlist in
                        NavigationLink(value: MusicDestination.playlist(id: playlist.id, editable: false)) {
                            HStack(spacing: 12) {
                                MusicArtworkView(url: playlist.coverURL, cornerRadius: 5)
                                    .frame(width: 56, height: 56)
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
            }
        }
    }

    private func horizontalAlbums(_ albums: [MusicAlbum]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("专辑").font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink(value: MusicDestination.album(album.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                MusicArtworkView(url: album.coverURL).frame(width: 144, height: 144)
                                Text(album.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                Text(album.artists.map(\.name).joined(separator: "、"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(width: 144, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeQuery = trimmed
        results = nil
        errorMessage = nil
        loadMoreError = nil
        currentPage = 1
        isLoadingMore = false
        guard !trimmed.isEmpty else {
            isLoading = false
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled, activeQuery == trimmed else { return }
        isLoading = true
        do {
            let page = try await environment.api.search(query: trimmed, page: 1)
            guard !Task.isCancelled, activeQuery == trimmed else { return }
            results = page
            await environment.refreshFavorites()
        } catch {
            guard !Task.isCancelled, activeQuery == trimmed else { return }
            errorMessage = "搜索失败"
        }
        if activeQuery == trimmed { isLoading = false }
    }

    private func loadMore() async {
        let searched = activeQuery
        guard !searched.isEmpty,
              let existing = results,
              existing.meta?.hasNextPage == true,
              !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreError = nil
        let nextPage = currentPage + 1
        do {
            let next = try await environment.api.search(query: searched, page: nextPage)
            guard activeQuery == searched, !Task.isCancelled else { return }
            results = existing.appending(next)
            currentPage = nextPage
        } catch {
            if activeQuery == searched, !Task.isCancelled {
                loadMoreError = "加载更多失败，可重试"
            }
        }
        if activeQuery == searched { isLoadingMore = false }
    }
}
