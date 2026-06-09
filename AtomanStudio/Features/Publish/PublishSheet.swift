import SwiftUI

public struct PublishSheet: View {
    @Binding public var visibility: BlogVisibility
    @Binding public var allowComments: Bool
    public let onSaveDraft: () -> Void
    public let onPublish: () -> Void

    public init(
        visibility: Binding<BlogVisibility>,
        allowComments: Binding<Bool>,
        onSaveDraft: @escaping () -> Void,
        onPublish: @escaping () -> Void
    ) {
        self._visibility = visibility
        self._allowComments = allowComments
        self.onSaveDraft = onSaveDraft
        self.onPublish = onPublish
    }

    public var body: some View {
        NavigationStack {
            Form {
                Picker("可见范围", selection: $visibility) {
                    Text("公开").tag(BlogVisibility.public)
                    Text("仅关注者").tag(BlogVisibility.followers)
                    Text("私密").tag(BlogVisibility.private)
                }
                Toggle("允许评论", isOn: $allowComments)
                Section {
                    Button("存草稿", action: onSaveDraft)
                    Button("发布文章", action: onPublish)
                }
            }
            .navigationTitle("发布设置")
        }
    }
}
