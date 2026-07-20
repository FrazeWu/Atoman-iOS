import SwiftUI

struct MiniMusicPlayerView: View {
    @Environment(MusicAppEnvironment.self) private var environment

    var body: some View {
        let player = environment.player
        if let song = player.currentSong {
            HStack(spacing: 10) {
                Button {
                    player.isShowingPlayer = true
                } label: {
                    HStack(spacing: 10) {
                        MusicArtworkView(url: song.resolvedCoverURL, cornerRadius: 4)
                            .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(song.artistText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            }
            .padding(5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.musicAccent)
                        .frame(width: proxy.size.width * progress, height: 2)
                }
                .frame(height: 2)
            }
        }
    }

    private var progress: CGFloat {
        let player = environment.player
        guard player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }
}
