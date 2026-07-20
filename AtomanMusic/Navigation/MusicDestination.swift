import SwiftUI

public enum MusicDestination: Hashable {
    case album(String)
    case artist(String)
    case playlist(id: String, editable: Bool)
}

struct MusicDestinationView: View {
    let destination: MusicDestination

    var body: some View {
        switch destination {
        case .album(let id):
            MusicAlbumDetailView(albumID: id)
        case .artist(let id):
            MusicArtistDetailView(artistID: id)
        case .playlist(let id, let editable):
            MusicPlaylistDetailView(playlistID: id, allowsEditing: editable)
        }
    }
}

extension MusicDiscoverItem {
    var destination: MusicDestination {
        switch type {
        case .album: .album(id)
        case .artist: .artist(id)
        case .playlist: .playlist(id: id, editable: false)
        }
    }
}
