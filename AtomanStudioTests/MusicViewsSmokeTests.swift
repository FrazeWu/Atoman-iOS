import AtomanCore
import Foundation
import XCTest
@testable import AtomanMusic

@MainActor
final class MusicViewsSmokeTests: XCTestCase {
    func testMusicRootViewCanBeCreated() {
        let authSession = AuthSessionStore(token: nil)
        let api = MusicAPI(
            client: APIClient(baseURL: URL(string: "https://example.com/api/v1")!),
            authSession: authSession
        )
        let environment = MusicAppEnvironment(
            api: api,
            authSession: authSession,
            player: MusicPlayer(engine: SmokePlaybackEngine())
        )

        _ = MusicRootView(environment: environment)
    }

    func testMusicAccountViewsCanBeCreated() {
        _ = MusicAccountButton()
        _ = MusicAccountSheet()
    }

    func testQueueActionBannerCanBeCreated() {
        _ = MusicQueueActionBanner(message: "已加入队列")
    }

    func testRoutePickerCanBeCreated() {
        _ = MusicRoutePickerView()
    }
}

@MainActor
private final class SmokePlaybackEngine: MusicPlaybackEngine {
    var onTimeUpdate: ((TimeInterval, TimeInterval) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onBufferingChanged: ((Bool) -> Void)?
    var onPlaybackFailed: ((String) -> Void)?
    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?
    var onOutputDisconnected: (() -> Void)?

    func load(url: URL) {}
    func play() {}
    func pause() {}
    func seek(to time: TimeInterval) {}
}
