import SwiftUI

public struct MusicRootView: View {
    @State private var environment: MusicAppEnvironment

    public init(environment: MusicAppEnvironment) {
        self._environment = State(initialValue: environment)
    }

    public var body: some View {
        MusicMainTabView()
            .environment(environment)
            .tint(.musicAccent)
            .preferredColorScheme(.dark)
            .task { await environment.restoreAuthentication() }
    }
}

private struct MusicMainTabView: View {
    @Environment(MusicAppEnvironment.self) private var environment

    var body: some View {
        @Bindable var player = environment.player

        TabView {
            musicNavigationStack {
                MusicHomeView()
            }
            .tabItem { Label("首页", systemImage: "house.fill") }

            musicNavigationStack {
                MusicSearchView()
            }
            .tabItem { Label("搜索", systemImage: "magnifyingglass") }

            musicNavigationStack {
                MusicLibraryView()
            }
            .tabItem { Label("资料库", systemImage: "books.vertical.fill") }
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
        .sheet(isPresented: $player.isShowingPlayer) {
            MusicPlayerView()
                .environment(environment)
        }
        .sheet(isPresented: rootAuthenticationBinding, onDismiss: {
            environment.authentication.dismiss()
        }) {
            MusicAccountSheet()
                .environment(environment)
        }
    }

    private var rootAuthenticationBinding: Binding<Bool> {
        Binding(
            get: { environment.presentsAuthenticationInRoot },
            set: { isPresented in
                if !isPresented {
                    environment.authentication.dismiss()
                }
            }
        )
    }

    private func musicNavigationStack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: MusicDestination.self) { destination in
                    MusicDestinationView(destination: destination)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        MusicAccountButton()
                    }
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if environment.player.currentSong != nil {
                MiniMusicPlayerView()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.musicBackground)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
