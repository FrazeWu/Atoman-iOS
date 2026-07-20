import XCTest
@testable import AtomanMusic

final class MusicWebConfigurationTests: XCTestCase {
    func testBuildsRegistrationAndPasswordResetURLsFromConfiguredSite() {
        let info = ["AtomanWebBaseURL": "http://localhost:5173/"]

        XCTAssertEqual(
            MusicWebConfiguration.registrationURL(infoDictionary: info).absoluteString,
            "http://localhost:5173/register"
        )
        XCTAssertEqual(
            MusicWebConfiguration.passwordResetURL(infoDictionary: info).absoluteString,
            "http://localhost:5173/forgot-password"
        )
    }

    func testMissingSiteConfigurationFallsBackToProduction() {
        XCTAssertEqual(
            MusicWebConfiguration.registrationURL(infoDictionary: [:]).absoluteString,
            "https://atoman.org/register"
        )
    }
}
