import SwiftUI

struct MusicLyricsView: View {
    @Environment(MusicAppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let player = environment.player
        let lines = MusicLyricsParser.parse(player.currentSong?.lyrics ?? "")
        let activeIndex = MusicLyricsParser.activeLineIndex(in: lines, at: player.currentTime)

        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if lines.isEmpty {
                            ContentUnavailableView("暂无歌词", systemImage: "text.quote")
                        } else {
                            ForEach(lines) { line in
                                Text(line.text)
                                    .font(.title3.weight(line.index == activeIndex ? .bold : .semibold))
                                    .foregroundStyle(line.index == activeIndex ? .primary : .secondary)
                                    .id(line.index)
                                    .onTapGesture {
                                        if let time = line.time { player.seek(to: time) }
                                    }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
                .onChange(of: activeIndex) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .background(Color.musicBackground)
            .navigationTitle("歌词")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("关闭歌词")
                }
            }
        }
    }
}
