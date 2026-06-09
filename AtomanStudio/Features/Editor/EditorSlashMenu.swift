import SwiftUI

public struct EditorSlashMenu: View {
    public let onInsert: (String) -> Void

    public init(onInsert: @escaping (String) -> Void) {
        self.onInsert = onInsert
    }

    public var body: some View {
        List {
            Button("标题") { onInsert("## ") }
            Button("引用") { onInsert("> ") }
            Button("代码块") { onInsert("```\n\n```") }
        }
        .navigationTitle("插入")
    }
}
