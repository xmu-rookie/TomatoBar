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

    func testSyncBuildsFormRequestAndDecodesResources() async throws {
        let transport = HTTPTransportStub(
            statusCode: 200,
            data: Data(
                #"""
                {
                  "sync_token": "next-token",
                  "full_sync": true,
                  "projects": [{
                    "id": "project-1",
                    "name": "Work",
                    "color": "blue",
                    "child_order": 2,
                    "is_deleted": false,
                    "is_archived": false
                  }],
                  "items": [{
                    "id": "task-1",
                    "project_id": "project-1",
                    "content": "Write report",
                    "description": "Quarterly report",
                    "priority": 4,
                    "due": {
                      "date": "2026-07-30T12:00:00",
                      "string": "today at noon",
                      "is_recurring": false
                    },
                    "checked": false,
                    "is_deleted": false
                  }]
                }
                """#.utf8
            )
        )
        let client = TodoistClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            transport: transport
        )

        let response = try await client.syncResources(
            token: " test-token ",
            syncToken: "previous-token"
        )

        XCTAssertTrue(response.fullSync)
        XCTAssertEqual(response.syncToken, "next-token")
        XCTAssertEqual(response.projects.first?.name, "Work")
        XCTAssertEqual(response.tasks.first?.content, "Write report")
        XCTAssertEqual(response.tasks.first?.due?.date, "2026-07-30T12:00:00")

        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/api/v1/sync")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-token"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded"
        )
        let form = try XCTUnwrap(
            URLComponents(
                string: "?\(String(decoding: request.httpBody ?? Data(), as: UTF8.self))"
            )
        )
        let values = Dictionary(
            uniqueKeysWithValues: (form.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        XCTAssertEqual(values["sync_token"], "previous-token")
        XCTAssertEqual(values["resource_types"], #"["projects","items"]"#)
    }

    func testIncrementalSyncAllowsMissingResourceArrays() async throws {
        let transport = HTTPTransportStub(
            statusCode: 200,
            data: Data(#"{"sync_token":"next","full_sync":false}"#.utf8)
        )

        let response = try await TodoistClient(transport: transport)
            .syncResources(token: "token", syncToken: "previous")

        XCTAssertFalse(response.fullSync)
        XCTAssertEqual(response.projects, [])
        XCTAssertEqual(response.tasks, [])
    }

    func testBadRequestIsClassifiedForSyncTokenRecovery() async {
        let transport = HTTPTransportStub(statusCode: 400)
        let client = TodoistClient(transport: transport)

        await assertError(.badRequest) {
            _ = try await client.syncResources(
                token: "token",
                syncToken: "expired"
            )
        }
    }

    func testExecuteCommandsPreservesUUIDAndDecodesMappings() async throws {
        let commandID = UUID(
            uuidString: "E1005F08-ACD6-4172-BAB1-4338F8616E49"
        )!
        let transport = HTTPTransportStub(
            statusCode: 200,
            data: Data(
                #"""
                {
                  "sync_status": {
                    "e1005f08-acd6-4172-bab1-4338f8616e49": "ok"
                  },
                  "temp_id_mapping": {
                    "temporary-comment": "remote-comment"
                  }
                }
                """#.utf8
            )
        )
        let client = TodoistClient(
            baseURL: URL(string: "https://example.com/api/v1")!,
            transport: transport
        )
        let request = TodoistCommandEnvelope(
            id: commandID,
            kind: .sessionCommentAdd,
            taskID: "task-1",
            sessionID: UUID(),
            temporaryID: "temporary-comment",
            arguments: [
                "item_id": "task-1",
                "content": "🍅 Focus",
            ]
        ).request

        let response = try await client.execute(
            token: " token ",
            commands: [request]
        )

        XCTAssertEqual(
            response.syncStatus[commandID.uuidString.lowercased()],
            .ok
        )
        XCTAssertEqual(
            response.tempIDMapping["temporary-comment"],
            "remote-comment"
        )
        let urlRequest = try XCTUnwrap(transport.lastRequest)
        let requestBody = String(
            decoding: urlRequest.httpBody ?? Data(),
            as: UTF8.self
        )
        let form = try XCTUnwrap(
            URLComponents(string: "?\(requestBody)")
        )
        let commandsJSON = try XCTUnwrap(
            form.queryItems?.first { $0.name == "commands" }?.value
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(commandsJSON.utf8)
            ) as? [[String: Any]]
        )
        XCTAssertEqual(json.first?["uuid"] as? String, commandID.uuidString.lowercased())
        XCTAssertEqual(json.first?["type"] as? String, "note_add")
        XCTAssertEqual(json.first?["temp_id"] as? String, "temporary-comment")
        XCTAssertEqual(
            (json.first?["args"] as? [String: String])?["item_id"],
            "task-1"
        )
    }

    func testCommandLevelFailureIsDecodedWithoutServerMessage() async throws {
        let transport = HTTPTransportStub(
            statusCode: 200,
            data: Data(
                #"""
                {
                  "sync_status": {
                    "command-id": {
                      "error": "sensitive server detail",
                      "error_code": 15,
                      "http_code": 400
                    }
                  }
                }
                """#.utf8
            )
        )

        let response = try await TodoistClient(transport: transport).execute(
            token: "token",
            commands: [
                TodoistSyncCommandRequest(
                    type: "item_close",
                    uuid: "command-id",
                    tempID: nil,
                    arguments: ["id": "task-1"]
                ),
            ]
        )

        XCTAssertEqual(
            response.syncStatus["command-id"],
            .failure(httpCode: 400, errorCode: 15)
        )
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
