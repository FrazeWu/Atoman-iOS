import Foundation
import Observation

enum MusicLibrarySection: Hashable, Sendable {
    case playlists
    case albums
    case artists
    case history
}

@MainActor
@Observable
final class MusicLibraryState {
    var favoriteAlbums: [MusicAlbumBookmark] = []
    var favoriteArtists: [MusicArtistBookmark] = []
    var playlists: [MusicPlaylist] = []
    var history: [MusicHistoryItem] = []
    private(set) var favoritePlaylist: MusicPlaylistDetail?
    private(set) var failedSections: Set<MusicLibrarySection> = []
    private(set) var isLoading = false

    var hasContent: Bool {
        !playlists.isEmpty || !favoriteAlbums.isEmpty || !favoriteArtists.isEmpty || !history.isEmpty
    }

    func load(api: MusicAPI) async {
        isLoading = true
        failedSections = []

        async let playlistsResult = capture { try await api.playlists() }
        async let albumsResult = capture { try await api.favoriteAlbums() }
        async let artistsResult = capture { try await api.favoriteArtists() }
        async let historyResult = capture { try await api.history() }

        let (loadedPlaylists, loadedAlbums, loadedArtists, loadedHistory) = await (
            playlistsResult,
            albumsResult,
            artistsResult,
            historyResult
        )
        apply(loadedAlbums, to: \.favoriteAlbums, section: .albums)
        apply(loadedArtists, to: \.favoriteArtists, section: .artists)
        apply(loadedHistory, to: \.history, section: .history)

        switch loadedPlaylists {
        case let .success(items):
            playlists = items
            if let favorite = items.first(where: \.isFavorite) {
                do {
                    favoritePlaylist = try await api.playlist(id: favorite.id)
                } catch {
                    favoritePlaylist = nil
                    failedSections.insert(.playlists)
                }
            } else {
                favoritePlaylist = nil
            }
        case .failure:
            failedSections.insert(.playlists)
        }
        isLoading = false
    }

    private func capture<Value>(_ operation: () async throws -> Value) async -> Result<Value, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func apply<Value>(
        _ result: Result<Value, Error>,
        to keyPath: ReferenceWritableKeyPath<MusicLibraryState, Value>,
        section: MusicLibrarySection
    ) {
        switch result {
        case let .success(value):
            self[keyPath: keyPath] = value
        case .failure:
            failedSections.insert(section)
        }
    }
}
