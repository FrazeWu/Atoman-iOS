import AtomanCore
import Foundation
import Observation

@Observable
public final class AppEnvironment {
    public let apiClient: APIClient
    public let blogAPI: BlogAPI
    public let feedAPI: FeedAPI
    public let authSession: AuthSessionStore
    public let database: AppDatabase

    public init(apiClient: APIClient, blogAPI: BlogAPI, feedAPI: FeedAPI, authSession: AuthSessionStore, database: AppDatabase) {
        self.apiClient = apiClient
        self.blogAPI = blogAPI
        self.feedAPI = feedAPI
        self.authSession = authSession
        self.database = database
    }

    public static func live() -> AppEnvironment {
        let apiClient = APIClient(baseURL: URL(string: "http://localhost:8080/api/v1")!)
        let authSession = AuthSessionStore()
        let database = try! AppDatabase.openDefault()
        let blogAPI = BlogAPI(client: apiClient, authSession: authSession)
        let feedAPI = FeedAPI(client: apiClient, authSession: authSession)
        return AppEnvironment(apiClient: apiClient, blogAPI: blogAPI, feedAPI: feedAPI, authSession: authSession, database: database)
    }
}
