import AtomanCore
import Foundation
import XCTest

final class APIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testUnauthorizedTokenRequestInvokesInvalidation() async throws {
        URLProtocolStub.requestHandler = { request in
            Self.response(request, statusCode: 401)
        }
        let spy = UnauthorizedHandlerSpy()
        let client = makeClient {
            await spy.recordCall()
        }

        _ = try await client.request(path: "users/me", token: "expired-token")

        let callCount = await spy.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testUnauthorizedLoginWithoutTokenDoesNotInvokeInvalidation() async throws {
        URLProtocolStub.requestHandler = { request in
            Self.response(request, statusCode: 401)
        }
        let spy = UnauthorizedHandlerSpy()
        let client = makeClient {
            await spy.recordCall()
        }

        _ = try await client.request(path: "auth/login", method: "POST")

        let callCount = await spy.callCount
        XCTAssertEqual(callCount, 0)
    }

    private func makeClient(onUnauthorized: @escaping @Sendable () async -> Void) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return APIClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            session: URLSession(configuration: configuration),
            onUnauthorized: onUnauthorized
        )
    }

    private static func response(_ request: URLRequest, statusCode: Int) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!,
            Data()
        )
    }
}

private actor UnauthorizedHandlerSpy {
    private(set) var callCount = 0

    func recordCall() {
        callCount += 1
    }
}
