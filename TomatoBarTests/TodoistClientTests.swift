import XCTest
@testable import TomatoBar

final class TodoistClientTests: XCTestCase {
    func testSuccessfulConnectionBuildsAuthenticatedRequestAndDecodesUser() async throws {
        let transport = HTTPTransportStub(
            statusCode: 200,
            data: Data(#"{"id":12345,"full_name":"Test User","email":"test@example.com"}"#.utf8)
        )
        let client = TodoistClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            transport: transport
        )

        let user = try await client.testConnection(token: " test-token ")

        XCTAssertEqual(
            user,
            TodoistUser(
                id: "12345",
                fullName: "Test User",
                email: "test@example.com"
            )
        )
        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/user")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-token"
        )
    }

    func testStringUserIDIsAccepted() async throws {
        let transport = HTTPTransportStub(
            statusCode: 200,
            data: Data(#"{"id":"abc","full_name":"Test User"}"#.utf8)
        )
        let client = TodoistClient(transport: transport)

        let user = try await client.testConnection(token: "token")

        XCTAssertEqual(user.id, "abc")
        XCTAssertNil(user.email)
    }

    func testUnauthorizedResponseIsClassifiedWithoutResponseBody() async {
        let transport = HTTPTransportStub(
            statusCode: 401,
            data: Data("secret-looking response".utf8)
        )
        let client = TodoistClient(transport: transport)

        await assertError(.unauthorized) {
            _ = try await client.testConnection(token: "token")
        }
    }

    func testRateLimitIncludesRetryDelay() async {
        let transport = HTTPTransportStub(
            statusCode: 429,
            headers: ["Retry-After": "42"]
        )
        let client = TodoistClient(transport: transport)

        await assertError(.rateLimited(retryAfterSeconds: 42)) {
            _ = try await client.testConnection(token: "token")
        }
    }

    func testMalformedSuccessResponseIsRejected() async {
        let transport = HTTPTransportStub(statusCode: 200, data: Data("{}".utf8))
        let client = TodoistClient(transport: transport)

        await assertError(.invalidResponse) {
            _ = try await client.testConnection(token: "token")
        }
    }

    func testTransportFailureIsClassifiedAsNetworkError() async {
        let transport = HTTPTransportStub(error: URLError(.notConnectedToInternet))
        let client = TodoistClient(transport: transport)

        await assertError(.network) {
            _ = try await client.testConnection(token: "token")
        }
    }

    private func assertError(
        _ expected: TodoistClientError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? TodoistClientError, expected)
        }
    }
}

private final class HTTPTransportStub: HTTPTransport {
    private let statusCode: Int
    private let data: Data
    private let headers: [String: String]
    private let error: Error?

    private(set) var lastRequest: URLRequest?

    init(
        statusCode: Int = 200,
        data: Data = Data(),
        headers: [String: String] = [:],
        error: Error? = nil
    ) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        if let error {
            throw error
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        return (data, response)
    }
}
