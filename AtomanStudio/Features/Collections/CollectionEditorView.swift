import SwiftUI

public struct CollectionEditorView: View {
    public let channel: BlogChannel
    @State private var name = ""
    @State private var description = ""

    public init(channel: BlogChannel) {
        self.channel = channel
    }

    public var body: some View {
        Form {
            Section("频道") {
                Text(channel.name)
            }
            Section("合集") {
                TextField("合集名", text: $name)
                TextField("描述", text: $description, axis: .vertical)
            }
        }
        .navigationTitle("合集设置")
    }
}
