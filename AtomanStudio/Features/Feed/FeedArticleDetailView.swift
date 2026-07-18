import SwiftUI

public struct FeedArticleDetailView: View {
    public let item: FeedTimelineItem
    public let onToggleStar: () -> Void
    public let onMarkRead: () -> Void

    public init(item: FeedTimelineItem, onToggleStar: @escaping () -> Void, onMarkRead: @escaping () -> Void) {
        self.item = item
        self.onToggleStar = onToggleStar
        self.onMarkRead = onMarkRead
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.sourceTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(item.displayTitle)
                    .font(.title.bold())
                Text(item.publishedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.body)
                        .lineSpacing(4)
                }
                if let url = URL(string: item.link) {
                    Link(destination: url) {
                        Label("打开原文", systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onToggleStar) {
                    Image(systemName: item.isStarred ? "star.fill" : "star")
                }
                .accessibilityLabel(item.isStarred ? "取消星标" : "添加星标")
            }
        }
        .task {
            onMarkRead()
        }
    }
}
