import SwiftUI

struct MusicPlaylistDetailView: View {
    @Environment(MusicAppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let playlistID: String
    let allowsEditing: Bool
    @State private var playlist: MusicPlaylistDetail?
    @State private var songs: [MusicSong] = []
    @State private var isLoading = true
    @State private var isEditing = false
    @State private var showMetadataEditor = false
    @State private var editName = ""
    @State private var editDescription = ""
    @State private var editIsPublic = false
    @State private var isSavingMetadata = false
    @State private var metadataErrorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
            } else if let playlist {
                List {
                    Section {
                        VStack(spacing: 14) {
                            MusicArtworkView(url: playlist.coverURL)
                                .frame(maxWidth: 260)
                            Text(playlist.name).font(.title2.bold()).multilineTextAlignment(.center)
                            if let description = playlist.description, !description.isEmpty {
                                Text(description).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            Button {
                                environment.player.play(songs: songs, startingAt: songs.first?.id)
                            } label: {
                                Label("播放", systemImage: "play.fill")
                                    .frame(minWidth: 100, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(songs.isEmpty)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        ForEach(songs) { song in
                            MusicTrackRow(song: song, queue: songs)
                        }
                        .onMove(perform: allowsEditing ? moveSongs : nil)
                        .onDelete(perform: allowsEditing ? removeSongs : nil)
                    }
                }
                .scrollContentBackground(.hidden)
                .musicEditMode(isEditing)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: environment.player.currentSong == nil ? 0 : 60)
                }
            }
        }
        .background(Color.musicBackground)
        .navigationTitle("歌单")
        .musicInlineNavigationTitle()
        .toolbar {
            if allowsEditing {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            presentMetadataEditor()
                        } label: {
                            Label("编辑信息", systemImage: "pencil")
                        }
                        Button {
                            isEditing.toggle()
                        } label: {
                            Label(isEditing ? "完成调整" : "调整顺序", systemImage: "arrow.up.arrow.down")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("删除歌单", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("歌单操作")
                }
            }
        }
        .confirmationDialog("删除这个歌单？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除歌单", role: .destructive) { deletePlaylist() }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showMetadataEditor) {
            NavigationStack {
                Form {
                    Section("信息") {
                        TextField("歌单名称", text: $editName)
                        TextField("描述", text: $editDescription, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    Section {
                        Toggle("公开歌单", isOn: $editIsPublic)
                    }
                    if let metadataErrorMessage {
                        Section {
                            Label(metadataErrorMessage, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("编辑歌单")
                .musicInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showMetadataEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { saveMetadata() }
                            .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingMetadata)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let detail = try await environment.api.playlist(id: playlistID)
            playlist = detail
            songs = detail.songs
            await environment.refreshFavorites()
            errorMessage = nil
        } catch {
            errorMessage = "歌单加载失败"
        }
        isLoading = false
    }

    private func moveSongs(from source: IndexSet, to destination: Int) {
        songs.move(fromOffsets: source, toOffset: destination)
        Task {
            do {
                try await environment.api.reorderPlaylist(id: playlistID, songIDs: songs.map(\.id))
            } catch {
                await load()
            }
        }
    }

    private func removeSongs(at offsets: IndexSet) {
        let removed = offsets.compactMap { songs.indices.contains($0) ? songs[$0] : nil }
        songs.remove(atOffsets: offsets)
        Task {
            do {
                for song in removed {
                    try await environment.api.removeSong(id: song.id, fromPlaylist: playlistID)
                }
            } catch {
                await load()
            }
        }
    }

    private func deletePlaylist() {
        Task {
            do {
                try await environment.api.deletePlaylist(id: playlistID)
                dismiss()
            } catch {
                errorMessage = "歌单删除失败"
            }
        }
    }

    private func presentMetadataEditor() {
        guard let playlist else { return }
        editName = playlist.playlist.name
        editDescription = playlist.playlist.description ?? ""
        editIsPublic = playlist.playlist.isPublic
        metadataErrorMessage = nil
        showMetadataEditor = true
    }

    private func saveMetadata() {
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSavingMetadata = true
        Task {
            do {
                let updated = try await environment.api.updatePlaylist(
                    id: playlistID,
                    name: name,
                    description: editDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    isPublic: editIsPublic
                )
                playlist = MusicPlaylistDetail(playlist: updated, songs: songs)
                showMetadataEditor = false
                metadataErrorMessage = nil
            } catch {
                metadataErrorMessage = "歌单保存失败"
            }
            isSavingMetadata = false
        }
    }
}

private extension View {
    @ViewBuilder
    func musicEditMode(_ isEditing: Bool) -> some View {
        #if os(iOS)
        environment(\.editMode, .constant(isEditing ? .active : .inactive))
        #else
        self
        #endif
    }
}
