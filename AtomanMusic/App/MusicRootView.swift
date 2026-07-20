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
        .overlay(alignment: .bottom) {
            if player.currentSong != nil {
                MiniMusicPlayerView()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 49)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
    }
}
