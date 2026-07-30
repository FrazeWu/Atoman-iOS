import SwiftUI

struct MusicQueueView: View {
    @Environment(MusicAppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @State private var isConfirmingClear = false

    var body: some View {
        NavigationStack {
            List {
                if let currentSong = environment.player.currentSong {
                    Section("正在播放") {
                        queueRow(currentSong, isCurrent: true)
                    }
                }

                Section("接下来") {
                    if environment.player.upcomingSongs.isEmpty {
                        Label("没有待播歌曲", systemImage: "music.note")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
                    } else {
                        ForEach(environment.player.upcomingSongs) { song in
                            Button {
                                environment.player.playQueuedSong(id: song.id)
                            } label: {
                                queueRow(song)
                            }
                            .buttonStyle(.plain)
                        }
                        .onMove(perform: moveUpcoming)
                        .onDelete(perform: removeUpcoming)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.musicBackground)
            .navigationTitle("播放队列")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("关闭播放队列")
                }
                ToolbarItemGroup(placement: .primaryAction) {
#if os(iOS)
                    if environment.player.upcomingSongs.count > 1 {
                        Button {
                            withAnimation {
                                editMode?.wrappedValue = isEditing ? .inactive : .active
                            }
                        } label: {
                            Image(systemName: isEditing ? "checkmark" : "arrow.up.arrow.down")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(isEditing ? "完成排序" : "调整顺序")
                    }
#endif
                    if !environment.player.upcomingSongs.isEmpty {
                        Button {
                            isConfirmingClear = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("清空待播")
                    }
                }
            }
            .confirmationDialog("清空所有待播歌曲？", isPresented: $isConfirmingClear) {
                Button("清空待播", role: .destructive) {
                    environment.player.clearUpcoming()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func queueRow(_ song: MusicSong, isCurrent: Bool = false) -> some View {
        HStack(spacing: 12) {
            MusicArtworkView(url: song.resolvedCoverURL, cornerRadius: 4)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).lineLimit(1)
                Text(song.artistText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.musicAccent)
                    .accessibilityLabel("正在播放")
            }
        }
        .contentShape(Rectangle())
    }

    private func moveUpcoming(from offsets: IndexSet, to destination: Int) {
        guard let source = offsets.first else { return }
        let target = destination > source ? destination - 1 : destination
        environment.player.moveUpcoming(from: source, to: target)
    }

    private func removeUpcoming(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            environment.player.removeUpcoming(at: index)
        }
    }

#if os(iOS)
    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }
#endif
}
