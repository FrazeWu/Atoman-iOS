import SwiftUI

struct MusicHomeView: View {
    @Environment(MusicAppEnvironment.self) private var environment
    @State private var feed = MusicHomeFeed()
    @State private var history: [MusicHistoryItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else if let errorMessage, feed.recommended.isEmpty && feed.latest.isEmpty {
                    ContentUnavailableView {
                        Label(errorMessage, systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("重试") { Task { await load() } }
                    }
                } else {
                    if !historySongs.isEmpty {
                        recentSection
                    }
                    discoverSection(title: "为你推荐", items: feed.recommended)
                    discoverSection(title: "新鲜发现", items: feed.latest)
                    discoverSection(title: "发现艺人", items: feed.artists)
                    discoverSection(title: "精选歌单", items: feed.playlists)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.musicBackground)
        .navigationTitle(greeting)
        .task(id: environment.authSession.token) { await load() }
        .refreshable { await load() }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近播放").font(.title3.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(historySongs.prefix(6))) { song in
                    Button {
                        environment.player.play(songs: historySongs, startingAt: song.id)
                    } label: {
                        HStack(spacing: 8) {
                            MusicArtworkView(url: song.resolvedCoverURL, cornerRadius: 4)
                                .frame(width: 48, height: 48)
                            Text(song.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(4)
                        .background(Color.musicSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func discoverSection(title: String, items: [MusicDiscoverItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title3.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { item in
                            NavigationLink(value: item.destination) {
                                VStack(alignment: .leading, spacing: 7) {
                                    MusicArtworkView(url: item.imageURL)
                                        .frame(width: 154, height: 154)
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if let subtitle = item.displaySubtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 154, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var historySongs: [MusicSong] {
        history.compactMap(\.song)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "早上好"
        case 12..<18: "下午好"
        default: "晚上好"
        }
    }

    private func load() async {
        let accountToken = environment.authSession.token
        isLoading = true
        do {
            let nextFeed = try await environment.api.homeFeed()
            guard !Task.isCancelled, environment.authSession.token == accountToken else { return }
            let nextHistory = environment.authSession.isAuthenticated
                ? ((try? await environment.api.history(pageSize: 12)) ?? [])
                : []
            guard !Task.isCancelled, environment.authSession.token == accountToken else { return }
            feed = nextFeed
            history = nextHistory
            await environment.refreshFavorites()
            errorMessage = nil
        } catch {
            if !Task.isCancelled, environment.authSession.token == accountToken {
                errorMessage = "内容加载失败"
            }
        }
        if environment.authSession.token == accountToken { isLoading = false }
    }
}
