import SwiftUI

public struct RootAppView: View {
    @Environment(AppEnvironment.self) private var environment

    public init() {}

    public var body: some View {
        MainTabView(environment: environment)
    }
}

public struct MainTabView: View {
    @State private var selectedTab: AppTab = .writing
    @State private var editorViewModel: BlogEditorViewModel
    @State private var feedViewModel: FeedTimelineViewModel

    public init(environment: AppEnvironment) {
        self._editorViewModel = State(
            initialValue: BlogEditorViewModel(
                blogAPI: environment.blogAPI,
                database: environment.database
            )
        )
        self._feedViewModel = State(
            initialValue: FeedTimelineViewModel(feedService: environment.feedAPI)
        )
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                BlogEditorView(viewModel: editorViewModel)
                    .navigationTitle("写作")
            }
            .tabItem {
                Label("写作", systemImage: "square.and.pencil")
            }
            .tag(AppTab.writing)

            NavigationStack {
                AuthenticationGateView(
                    title: "登录后查看订阅",
                    message: "RSS 订阅和阅读状态保存在云端。登录后可以查看你的订阅时间线。"
                ) {
                    FeedTimelineView(viewModel: feedViewModel)
                }
                .navigationTitle("订阅")
            }
            .tabItem {
                Label("订阅", systemImage: "dot.radiowaves.left.and.right")
            }
            .tag(AppTab.feed)

            NavigationStack {
                DraftListView(drafts: []) { draft in
                    editorViewModel.apply(draft)
                    selectedTab = .writing
                }
            }
            .tabItem {
                Label("草稿", systemImage: "doc.text")
            }
            .tag(AppTab.drafts)

            NavigationStack {
                AuthenticationGateView(
                    title: "登录后管理频道",
                    message: "频道和合集保存在云端。登录后可以查看和管理你的发布频道。"
                ) {
                    ChannelListView()
                }
            }
            .tabItem {
                Label("频道", systemImage: "rectangle.stack")
            }
            .tag(AppTab.channels)
        }
    }
}

public enum AppTab: Hashable {
    case writing
    case feed
    case drafts
    case channels
}
