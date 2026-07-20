import AtomanMusic
import SwiftUI

@main
struct AtomanMusicApp: App {
    @State private var environment = MusicAppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            MusicRootView(environment: environment)
        }
    }
}
