import Foundation
import Observation

@Observable
public final class AppEnvironment {
    public let apiClient: APIClient
    public let blogAPI: BlogAPI
    public let authSession: AuthSessionStore
    public let database: AppDatabase

    public init(apiClient: APIClient, blogAPI: BlogAPI, authSession: AuthSessionStore, database: AppDatabase) {
        self.apiClient = apiClient
        self.blogAPI = blogAPI
        self.authSession = authSession
        self.database = database
    }

    public static func live() -> AppEnvironment {
        let apiClient = APIClient(baseURL: URL(string: "http://localhost:8080/api")!)
        let authSession = AuthSessionStore()
        let database = try! AppDatabase.openDefault()
        let blogAPI = BlogAPI(client: apiClient, authSession: authSession)
        return AppEnvironment(apiClient: apiClient, blogAPI: blogAPI, authSession: authSession, database: database)
    }
}
