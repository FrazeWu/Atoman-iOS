import SwiftUI

public struct MusicArtworkView: View {
    private let url: String?
    private let cornerRadius: CGFloat

    public init(url: String?, cornerRadius: CGFloat = 6) {
        self.url = url
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            if let imageURL = url.flatMap(URL.init(string:)) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        artworkPlaceholder {
                            ProgressView().controlSize(.small)
                        }
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        artworkFallback
                    @unknown default:
                        artworkFallback
                    }
                }
            } else {
                artworkFallback
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var artworkFallback: some View {
        artworkPlaceholder {
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private func artworkPlaceholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.musicSurface
            content()
        }
    }
}
