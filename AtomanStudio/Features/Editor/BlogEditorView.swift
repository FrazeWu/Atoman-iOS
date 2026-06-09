import SwiftUI

public struct BlogEditorView: View {
    @Bindable public var viewModel: BlogEditorViewModel
    @State private var showPublishSheet = false

    public init(viewModel: BlogEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("标题", text: $viewModel.title)
                .font(.title2)
                .textFieldStyle(.roundedBorder)
                .padding()

            MarkdownTextView(text: $viewModel.content) {
                viewModel.isSlashMenuPresented = true
            }
            .padding(.horizontal)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("发布") {
                    showPublishSheet = true
                }
            }
        }
        .sheet(isPresented: $showPublishSheet) {
            PublishSheet(
                visibility: $viewModel.visibility,
                allowComments: $viewModel.allowComments,
                onSaveDraft: { Task { await viewModel.saveAsDraft() } },
                onPublish: { Task { await viewModel.publish() } }
            )
        }
    }
}
