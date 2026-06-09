import SwiftUI

public struct ChannelEditorView: View {
    public let channel: BlogChannel
    @State private var name: String
    @State private var slug: String
    @State private var description: String

    public init(channel: BlogChannel) {
        self.channel = channel
        self._name = State(initialValue: channel.name)
        self._slug = State(initialValue: channel.slug)
        self._description = State(initialValue: channel.description ?? "")
    }

    public var body: some View {
        Form {
            TextField("频道名", text: $name)
            TextField("Slug", text: $slug)
            TextField("描述", text: $description, axis: .vertical)
            NavigationLink("合集") {
                CollectionEditorView(channel: channel)
            }
        }
        .navigationTitle("频道设置")
    }
}
