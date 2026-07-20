import SwiftUI

public struct FeedTimelineView: View {
    @Bindable public var viewModel: FeedTimelineViewModel

    public init(viewModel: FeedTimelineViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filterBar
                content
            }
            .padding()
        }
        .refreshable {
            await viewModel.loadInitial()
        }
        .task {
            if viewModel.items.isEmpty {
                await viewModel.loadInitial()
            }
        }
    }

    private var filterBar: some View {
        Picker("筛选", selection: Binding(
            get: { viewModel.selectedFilter },
            set: { filter in Task { await viewModel.selectFilter(filter) } }
        )) {
            ForEach(FeedTimelineFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("加载中…")
                .frame(maxWidth: .infinity, minHeight: 220)
        } else if viewModel.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(viewModel.errorMessage ?? "还没有订阅内容")
                    .font(.headline)
                Text(viewModel.errorMessage == nil ? "先添加 RSS 订阅源，新的内容会出现在这里。" : "检查网络后重试。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if viewModel.errorMessage != nil {
                    Button("重试") { Task { await viewModel.loadInitial() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.items) { item in
                    NavigationLink {
                        FeedArticleDetailView(
                            item: item,
                            onToggleStar: { Task { await viewModel.toggleStar(itemID: item.id) } },
                            onMarkRead: { Task { await viewModel.markReadAfterOpening(itemID: item.id) } }
                        )
                    } label: {
                        FeedTimelineCard(item: item) {
                            Task { await viewModel.toggleStar(itemID: item.id) }
                        }
                    }
                    .buttonStyle(.plain)
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItemID: item.id)
                    }
                }
                if viewModel.isLoadingMore {
                    ProgressView().padding(.vertical)
                }
            }
        }
    }
}

private struct FeedTimelineCard: View {
    let item: FeedTimelineItem
    let onToggleStar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.sourceTitle)
                    .font(.caption.weight(item.isRead ? .regular : .bold))
                    .foregroundStyle(item.isRead ? Color.secondary : Color.accentColor)
                Spacer()
                Button(action: onToggleStar) {
                    Image(systemName: item.isStarred ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isStarred ? "取消星标" : "添加星标")
            }
            Text(item.displayTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
