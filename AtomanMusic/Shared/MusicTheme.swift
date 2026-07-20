import SwiftUI

extension Color {
    static let musicAccent = Color(red: 0.55, green: 0.87, blue: 0.40)
    static let musicBackground = Color(red: 0.035, green: 0.04, blue: 0.045)
    static let musicSurface = Color(red: 0.10, green: 0.11, blue: 0.12)
}

extension View {
    @ViewBuilder
    func musicInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func musicHiddenNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
