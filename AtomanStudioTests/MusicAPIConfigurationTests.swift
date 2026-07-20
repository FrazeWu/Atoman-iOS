import Foundation
import XCTest
@testable import AtomanMusic

final class MusicAPIConfigurationTests: XCTestCase {
    func testUsesConfiguredAPIBaseURL() {
        let url = MusicAPIConfiguration.baseURL(
            infoDictionary: ["AtomanAPIBaseURL": "http://localhost:8080/api/v1"]
        )

        XCTAssertEqual(url.absoluteString, "http://localhost:8080/api/v1")
    }

    func testMissingConfigurationFallsBackToProductionAPI() {
        let url = MusicAPIConfiguration.baseURL(infoDictionary: [:])

        XCTAssertEqual(url.absoluteString, "https://api.atoman.org/api/v1")
    }
}
