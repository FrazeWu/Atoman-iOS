import XCTest
@testable import AtomanStudio

final class AppSmokeTests: XCTestCase {
    func testEnvironmentCanBootInMemory() throws {
        let database = try AppDatabase.inMemory()
        let authSession = AuthSessionStore()
        let apiClient = APIClient(baseURL: URL(string: "https://example.com/api")!)
        let blogAPI = BlogAPI(client: apiClient, authSession: authSession)
        let env = AppEnvironment(apiClient: apiClient, blogAPI: blogAPI, authSession: authSession, database: database)

        XCTAssertNotNil(env)
    }
}
