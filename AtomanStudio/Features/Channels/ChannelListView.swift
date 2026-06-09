import SwiftUI

public struct ChannelListView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var channels: [BlogChannel] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            List(channels) { channel in
                NavigationLink(channel.name) {
                    ChannelEditorView(channel: channel)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    Text(errorMessage)
                }
            }
            .navigationTitle("频道")
            .task {
                await loadChannels()
            }
        }
    }

    private func loadChannels() async {
        isLoading = true
        defer { isLoading = false }
        do {
            channels = try await environment.blogAPI.fetchChannels()
            errorMessage = nil
        } catch {
            errorMessage = "加载频道失败"
        }
    }
}
