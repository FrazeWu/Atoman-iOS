import AtomanCore
import Foundation
import XCTest

final class AuthAPITests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testLoginSendsCredentialsAndDecodesSession() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/auth/login")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try Self.bodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(json, ["username": "alice@example.com", "password": "secret123"])
            return Self.response(request, body: """
            {"token":"token-1","user":{"id":7,"uuid":"user-1","username":"alice","email":"alice@example.com","role":"user","display_name":"Alice","avatar_url":"https://cdn.example.com/alice.jpg","is_active":true}}
            """)
        }

        let session = try await api.login(identifier: "alice@example.com", password: "secret123")

        XCTAssertEqual(session.token, "token-1")
        XCTAssertEqual(session.user.username, "alice")
        XCTAssertEqual(session.user.displayName, "Alice")
    }

    func testCurrentUserUsesBearerTokenAndDecodesEnvelope() async throws {
        let api = makeAPI { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/users/me")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            return Self.response(request, body: """
            {"data":{"id":7,"uuid":"user-1","username":"alice","email":"alice@example.com","role":"user","display_name":"Alice","avatar_url":"","is_active":true},"message":"ok"}
            """)
        }

        let user = try await api.currentUser(token: "token-1")

        XCTAssertEqual(user.id, 7)
        XCTAssertEqual(user.email, "alice@example.com")
    }

    func testLoginPreservesServerAuthenticationErrorCode() async throws {
        let api = makeAPI { request in
            Self.response(
                request,
                statusCode: 401,
                body: #"{"code":"auth.password_mismatch","error":"密码不正确"}"#
            )
        }

        do {
            _ = try await api.login(identifier: "alice", password: "wrong")
            XCTFail("expected login to fail")
        } catch let error as AuthAPIError {
            XCTAssertEqual(error, .server(statusCode: 401, code: "auth.password_mismatch", message: "密码不正确"))
        }
    }

    private func makeAPI(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> AuthAPI {
        URLProtocolStub.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return AuthAPI(client: APIClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            session: URLSession(configuration: configuration)
        ))
    }

    private static func response(
        _ request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
