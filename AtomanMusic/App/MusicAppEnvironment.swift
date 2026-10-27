import AtomanCore
import Foundation
import Observation

@MainActor
@Observable
public final class MusicAppEnvironment {
    public let api: MusicAPI
    public let authAPI: AuthAPI
    public let authSession: AuthSessionStore
    public let authentication: MusicAuthenticationCoordinator
    public let player: MusicPlayer
    public private(set) var actionErrorMessage: String?
    public private(set) var favoritePlaylistID: String?
    public private(set) var favoriteSongIDs: Set<String> = []
    public private(set) var favoriteAlbumIDs: Set<String> = []
    public private(set) var favoriteArtistIDs: Set<String> = []

    var presentsAuthenticationInRoot: Bool {
        authentication.isPresented && !player.isShowingPlayer
    }

    var presentsAuthenticationInPlayer: Bool {
        authentication.isPresented && player.isShowingPlayer
    }

    public init(
        api: MusicAPI,
        authSession: AuthSessionStore,
        player: MusicPlayer,
        authentication: MusicAuthenticationCoordinator? = nil
    ) {
        self.api = api
        self.authAPI = AuthAPI(client: api.client)
        self.authSession = authSession
        self.player = player
        self.authentication = authentication ?? MusicAuthenticationCoordinator()
    }

    public func restoreAuthentication() async {
        await authSession.restore { [authAPI] token in
            try await authAPI.currentUser(token: token)
        }
        if authSession.isAuthenticated {
            await refreshFavorites()
            await restoreRemotePlayback()
        } else {
            clearUserState()
        }
    }

    public func restoreRemotePlayback() async {
        guard authSession.isAuthenticated, !player.isPlaying else { return }
        let tokenBeforeFetch = authSession.token
        if let snapshot = try? await api.playbackSession() {
            guard authSession.isAuthenticated, authSession.token == tokenBeforeFetch else { return }
            player.restoreRemotePlayback(snapshot)
        }
    }

    public func refreshFavorites() async {
        guard authSession.isAuthenticated else {
            favoritePlaylistID = nil
            favoriteSongIDs = []
            favoriteAlbumIDs = []
            favoriteArtistIDs = []
            return
        }
        do {
            let favorite = try await api.favoritePlaylist()
            let albums = try await api.favoriteAlbums(pageSize: 100)
            let artists = try await api.favoriteArtists(pageSize: 100)
            synchronizeFavorites(favorite: favorite, albums: albums, artists: artists)
        } catch {
            // Keep the last known favorites when a refresh cannot complete.
        }
    }

    public func setFavoriteSong(id: String, isFavorite: Bool) async throws {
        if favoritePlaylistID == nil {
            let favorite = try await api.favoritePlaylist()
            favoritePlaylistID = favorite?.id
            favoriteSongIDs = Set(favorite?.songs.map(\.id) ?? [])
        }
        guard let favoritePlaylistID else {
            throw URLError(.resourceUnavailable)
        }
        if isFavorite {
            try await api.addSong(id: id, toPlaylist: favoritePlaylistID)
        } else {
            try await api.removeSong(id: id, fromPlaylist: favoritePlaylistID)
        }
        update(&favoriteSongIDs, id: id, isFavorite: isFavorite)
    }

    public func setFavoriteAlbum(id: String, isFavorite: Bool) async throws {
        try await api.setFavoriteAlbum(id: id, isFavorite: isFavorite)
        update(&favoriteAlbumIDs, id: id, isFavorite: isFavorite)
    }

    public func setFavoriteArtist(id: String, isFavorite: Bool) async throws {
        try await api.setFavoriteArtist(id: id, isFavorite: isFavorite)
        update(&favoriteArtistIDs, id: id, isFavorite: isFavorite)
    }

    public func requestFavoriteSong(id: String, isFavorite: Bool) async {
        await requestAuthentication(for: .favoriteSong(id: id, isFavorite: isFavorite))
    }

    public func requestFavoriteAlbum(id: String, isFavorite: Bool) async {
        await requestAuthentication(for: .favoriteAlbum(id: id, isFavorite: isFavorite))
    }

    public func requestFavoriteArtist(id: String, isFavorite: Bool) async {
        await requestAuthentication(for: .favoriteArtist(id: id, isFavorite: isFavorite))
    }

    public func completeAuthentication() async {
        guard authSession.isAuthenticated, authentication.isPresented else { return }
        await refreshFavorites()
        await restoreRemotePlayback()
        guard let action = authentication.takePendingAction() else {
            authentication.dismiss(clearPendingAction: false)
            return
        }
        do {
            try await perform(action)
            authentication.dismiss(clearPendingAction: false)
        } catch {
            if authSession.isAuthenticated {
                actionErrorMessage = "收藏失败，请重试"
                authentication.dismiss(clearPendingAction: false)
            } else {
                authentication.present(for: action)
            }
        }
    }

    public func logout() {
        authSession.clear()
        clearUserState()
        authentication.dismiss()
    }

    func synchronizeFavorites(
        favorite: MusicPlaylistDetail?,
        albums: [MusicAlbumBookmark],
        artists: [MusicArtistBookmark]
    ) {
        favoritePlaylistID = favorite?.id
        favoriteSongIDs = Set(favorite?.songs.map(\.id) ?? [])
        favoriteAlbumIDs = Set(albums.map(\.albumID))
        favoriteArtistIDs = Set(artists.map(\.artistID))
    }

    private func update(_ ids: inout Set<String>, id: String, isFavorite: Bool) {
        if isFavorite {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
    }

    private func requestAuthentication(for action: MusicPendingAuthAction) async {
        actionErrorMessage = nil
        guard authSession.isAuthenticated else {
            authentication.present(for: action)
            return
        }
        do {
            try await perform(action)
        } catch {
            if authSession.isAuthenticated {
                actionErrorMessage = "收藏失败，请重试"
            } else {
                authentication.present(for: action)
            }
        }
    }

    private func perform(_ action: MusicPendingAuthAction) async throws {
        switch action {
        case .favoriteSong(let id, let isFavorite):
            try await setFavoriteSong(id: id, isFavorite: isFavorite)
        case .favoriteAlbum(let id, let isFavorite):
            try await setFavoriteAlbum(id: id, isFavorite: isFavorite)
        case .favoriteArtist(let id, let isFavorite):
            try await setFavoriteArtist(id: id, isFavorite: isFavorite)
        }
    }

    private func clearUserState() {
        favoritePlaylistID = nil
        favoriteSongIDs = []
        favoriteAlbumIDs = []
        favoriteArtistIDs = []
    }

    public static func live() -> MusicAppEnvironment {
        let baseURL = MusicAPIConfiguration.baseURL(infoDictionary: Bundle.main.infoDictionary ?? [:])
        let authSession = AuthSessionStore()
        let client = APIClient(baseURL: baseURL) {
            authSession.invalidate()
        }
        let api = MusicAPI(client: client, authSession: authSession)
        let player = MusicPlayer(
            recordPlay: { songID in try? await api.recordPlay(songID: songID) },
            syncPlayback: { snapshot in
                guard authSession.isAuthenticated else { return }
                try? await api.savePlaybackSnapshot(snapshot)
            }
        )
        return MusicAppEnvironment(api: api, authSession: authSession, player: player)
    }
}
