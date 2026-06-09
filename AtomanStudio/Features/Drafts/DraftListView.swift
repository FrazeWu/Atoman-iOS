import SwiftUI

public struct DraftListView: View {
    public let drafts: [EditorDraftPayload]
    public let onSelect: (EditorDraftPayload) -> Void

    public init(drafts: [EditorDraftPayload], onSelect: @escaping (EditorDraftPayload) -> Void) {
        self.drafts = drafts
        self.onSelect = onSelect
    }

    public var body: some View {
        List(drafts, id: \.contextKey) { draft in
            Button {
                onSelect(draft)
            } label: {
                VStack(alignment: .leading) {
                    Text(draft.title.isEmpty ? "未命名草稿" : draft.title)
                    Text(draft.summary.isEmpty ? draft.content : draft.summary)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("草稿")
    }
}
