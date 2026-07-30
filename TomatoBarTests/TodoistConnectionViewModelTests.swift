import XCTest
@testable import TomatoBar

@MainActor
final class TodoistConnectionViewModelTests: XCTestCase {
    func testSuccessfulConnectionSavesTrimmedTokenAndClearsInput() async {
        let store = CredentialStoreStub()
        let client = TodoistConnectorStub(result: .success(.fixture))
        let viewModel = TodoistConnectionViewModel(
            credentialStore: store,
            client: client
        )
        viewModel.tokenInput = " test-token \n"

        await viewModel.connect()

        XCTAssertEqual(store.token, "test-token")
        XCTAssertEqual(client.receivedTokens, ["test-token"])
        XCTAssertEqual(viewModel.tokenInput, "")
        XCTAssertTrue(viewModel.hasStoredToken)
        XCTAssertEqual(viewModel.state, .connected(displayName: "Test User"))
    }

    func testFailedConnectionDoesNotPersistToken() async {
        let store = CredentialStoreStub()
        let client = TodoistConnectorStub(result: .failure(.unauthorized))
        let viewModel = TodoistConnectionViewModel(
            credentialStore: store,
            client: client
        )
        viewModel.tokenInput = "invalid-token"

        await viewModel.connect()

        XCTAssertNil(store.token)
        XCTAssertFalse(viewModel.hasStoredToken)
        guard case let .failed(message) = viewModel.state else {
            return XCTFail("Expected failed state")
        }
        XCTAssertFalse(message.contains("invalid-token"))
    }

    func testStoredTokenIsTestedWithoutBeingExposedInInput() async {
        let store = CredentialStoreStub(token: "stored-token")
        let client = TodoistConnectorStub(result: .success(.fixture))
        let viewModel = TodoistConnectionViewModel(
            credentialStore: store,
            client: client
        )

        await viewModel.testSavedConnection()

        XCTAssertEqual(client.receivedTokens, ["stored-token"])
        XCTAssertEqual(viewModel.tokenInput, "")
        XCTAssertTrue(viewModel.hasStoredToken)
        XCTAssertEqual(viewModel.state, .connected(displayName: "Test User"))
    }

    func testDisconnectDeletesStoredToken() {
        let store = CredentialStoreStub(token: "stored-token")
        let viewModel = TodoistConnectionViewModel(
            credentialStore: store,
            client: TodoistConnectorStub(result: .success(.fixture))
        )

        viewModel.disconnect()

        XCTAssertNil(store.token)
        XCTAssertFalse(viewModel.hasStoredToken)
        XCTAssertEqual(viewModel.state, .disconnected)
    }
}

private final class CredentialStoreStub: CredentialStore {
    var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func loadToken() throws -> String? {
        token
    }

    func saveToken(_ token: String) throws {
        self.token = token
    }

    func deleteToken() throws {
        token = nil
    }
}

private final class TodoistConnectorStub: TodoistConnecting {
    let result: Result<TodoistUser, TodoistClientError>
    private(set) var receivedTokens: [String] = []

    init(result: Result<TodoistUser, TodoistClientError>) {
        self.result = result
    }

    func testConnection(token: String) async throws -> TodoistUser {
        receivedTokens.append(token)
        return try result.get()
    }
}

private extension TodoistUser {
    static var fixture: TodoistUser {
        TodoistUser(id: "123", fullName: "Test User")
    }
}
