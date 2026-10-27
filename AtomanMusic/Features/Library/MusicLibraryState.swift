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
    private(set) var moreSections: Set<MusicLibrarySection> = []
    private(set) var loadingMoreSections: Set<MusicLibrarySection> = []
    private var pageNumbers: [MusicLibrarySection: Int] = [:]
    private var loadGeneration = 0

    var hasContent: Bool {
        !playlists.isEmpty || !favoriteAlbums.isEmpty || !favoriteArtists.isEmpty || !history.isEmpty
    }

    func load(api: MusicAPI) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        failedSections = []
        moreSections = []
        loadingMoreSections = []
        pageNumbers = [:]

        async let playlistsResult = capture { try await api.playlistPage() }
        async let albumsResult = capture { try await api.favoriteAlbumPage() }
        async let artistsResult = capture { try await api.favoriteArtistPage() }
        async let historyResult = capture { try await api.historyPage() }

        let (loadedPlaylists, loadedAlbums, loadedArtists, loadedHistory) = await (
            playlistsResult, albumsResult, artistsResult, historyResult
        )
        guard generation == loadGeneration, !Task.isCancelled else { return }
        applyPage(loadedAlbums, to: \.favoriteAlbums, section: .albums)
        applyPage(loadedArtists, to: \.favoriteArtists, section: .artists)
        applyPage(loadedHistory, to: \.history, section: .history)

        switch loadedPlaylists {
        case let .success(page):
            playlists = page.data
            setPage(page, section: .playlists, index: 1)
            if let favorite = page.data.first(where: \.isFavorite) {
                do {
                    let details = try await api.playlist(id: favorite.id)
                    guard generation == loadGeneration else { return }
                    favoritePlaylist = details
                } catch {
                    guard generation == loadGeneration else { return }
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

    func loadMore(_ section: MusicLibrarySection, api: MusicAPI) async {
        guard !isLoading, moreSections.contains(section), !loadingMoreSections.contains(section) else { return }
        let generation = loadGeneration
        loadingMoreSections.insert(section)
        let next = (pageNumbers[section] ?? 1) + 1
        do {
            switch section {
            case .playlists:
                let page = try await api.playlistPage(page: next)
                guard generation == loadGeneration, !Task.isCancelled else { return }
                playlists = appendUnique(playlists, page.data)
                setPage(page, section: section, index: next)
            case .albums:
                let page = try await api.favoriteAlbumPage(page: next)
                guard generation == loadGeneration, !Task.isCancelled else { return }
                favoriteAlbums = appendUnique(favoriteAlbums, page.data)
                setPage(page, section: section, index: next)
            case .artists:
                let page = try await api.favoriteArtistPage(page: next)
                guard generation == loadGeneration, !Task.isCancelled else { return }
                favoriteArtists = appendUnique(favoriteArtists, page.data)
                setPage(page, section: section, index: next)
            case .history:
                let page = try await api.historyPage(page: next)
                guard generation == loadGeneration, !Task.isCancelled else { return }
                history = appendUnique(history, page.data)
                setPage(page, section: section, index: next)
            }
            failedSections.remove(section)
        } catch {
            failedSections.insert(section)
        }
        loadingMoreSections.remove(section)
    }

    private func appendUnique<Item: Identifiable>(_ existing: [Item], _ incoming: [Item]) -> [Item] where Item.ID: Hashable {
        var seen = Set(existing.map(\.id))
        return existing + incoming.filter { seen.insert($0.id).inserted }
    }

    private func setPage<Item: Decodable>(_ page: MusicPage<Item>, section: MusicLibrarySection, index: Int) {
        pageNumbers[section] = index
        if page.hasMore { moreSections.insert(section) }
        else { moreSections.remove(section) }
    }

    private func applyPage<Item: Decodable>(
        _ result: Result<MusicPage<Item>, Error>,
        to keyPath: ReferenceWritableKeyPath<MusicLibraryState, [Item]>,
        section: MusicLibrarySection
    ) {
        switch result {
        case let .success(page):
            self[keyPath: keyPath] = page.data
            setPage(page, section: section, index: 1)
        case .failure:
            failedSections.insert(section)
        }
    }

    private func capture<Value>(_ operation: () async throws -> Value) async -> Result<Value, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

}
