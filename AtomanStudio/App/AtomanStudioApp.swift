#if !DEBUG
import SwiftUI

@main
struct AtomanStudioApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootAppView()
                .environment(environment)
        }
    }
}
#endif
