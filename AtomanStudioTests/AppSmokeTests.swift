import SwiftUI
import XCTest
@testable import AtomanStudio

final class AppSmokeTests: XCTestCase {
    func testEnvironmentCanBootInMemory() throws {
        let database = try AppDatabase.inMemory()
        let authSession = AuthSessionStore(token: nil)
        let apiClient = APIClient(baseURL: URL(string: "https://example.com/api")!)
        let blogAPI = BlogAPI(client: apiClient, authSession: authSession)
        let env = AppEnvironment(apiClient: apiClient, blogAPI: blogAPI, authSession: authSession, database: database)

        XCTAssertNotNil(env)
    }

    @MainActor
    func testRootAppViewCanBeCreated() throws {
        let view = RootAppView()

        XCTAssertNotNil(view)
    }

    @MainActor
    func testMainTabViewCanBeCreatedWithEnvironment() throws {
        let database = try AppDatabase.inMemory()
        let authSession = AuthSessionStore(token: nil)
        let apiClient = APIClient(baseURL: URL(string: "https://example.com/api")!)
        let blogAPI = BlogAPI(client: apiClient, authSession: authSession)
        let env = AppEnvironment(apiClient: apiClient, blogAPI: blogAPI, authSession: authSession, database: database)
        let view = MainTabView(environment: env)

        XCTAssertNotNil(view)
    }
}
