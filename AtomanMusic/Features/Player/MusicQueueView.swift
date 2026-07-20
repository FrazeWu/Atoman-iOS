import SwiftUI

struct MusicQueueView: View {
    @Environment(MusicAppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            List(environment.player.songs) { song in
                Button {
                    environment.player.play(songs: environment.player.songs, startingAt: song.id)
                } label: {
                    HStack(spacing: 12) {
                        MusicArtworkView(url: song.resolvedCoverURL, cornerRadius: 4)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).lineLimit(1)
                            Text(song.artistText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if song.id == environment.player.currentSong?.id {
                            Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.musicAccent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .background(Color.musicBackground)
            .navigationTitle("播放队列")
        }
    }
}
