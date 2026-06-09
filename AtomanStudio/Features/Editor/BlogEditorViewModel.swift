import Foundation
import Observation

@MainActor
@Observable
public final class BlogEditorViewModel {
    public var title = ""
    public var content = ""
    public var summary = ""
    public var coverURL = ""
    public var visibility: BlogVisibility = .public
    public var allowComments = true
    public var channelID: String?
    public var collectionIDs: [String] = []
    public var serverDraftState: DraftSyncState = .idle
    public var isSlashMenuPresented = false
    public var errorMessage: String?

    private let blogAPI: BlogAPI
    private let database: AppDatabase

    public init(blogAPI: BlogAPI, database: AppDatabase) {
        self.blogAPI = blogAPI
        self.database = database
    }

    public func makeDraftPayload(contextKey: String, sourcePostID: String?) -> EditorDraftPayload {
        EditorDraftPayload(
            contextKey: contextKey,
            sourcePostID: sourcePostID,
            title: title,
            content: content,
            summary: summary,
            coverURL: coverURL,
            visibility: visibility,
            allowComments: allowComments,
            channelID: channelID,
            collectionIDs: collectionIDs
        )
    }

    public func apply(_ payload: EditorDraftPayload) {
        title = payload.title
        content = payload.content
        summary = payload.summary
        coverURL = payload.coverURL
        visibility = payload.visibility
        allowComments = payload.allowComments
        channelID = payload.channelID
        collectionIDs = payload.collectionIDs
    }

    public func saveAsDraft() async {
        do {
            let payload = makeDraftPayload(contextKey: "blog:new", sourcePostID: nil)
            try await blogAPI.putDraft(payload)
            serverDraftState = .synced
        } catch {
            serverDraftState = .error
            errorMessage = "保存草稿失败"
        }
    }

    public func publish() async {
        do {
            _ = try await blogAPI.createPost(makePostRequest(status: "published"))
            errorMessage = nil
        } catch {
            errorMessage = "发布失败"
        }
    }

    public func makePostRequest(status: String) -> CreateBlogPostRequest {
        CreateBlogPostRequest(
            title: title,
            content: content,
            summary: summary,
            coverURL: coverURL,
            visibility: visibility,
            allowComments: allowComments,
            status: status,
            channelID: channelID,
            collectionIDs: collectionIDs
        )
    }
}
