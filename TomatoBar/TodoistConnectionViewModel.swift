import Combine
import Foundation

@MainActor
final class TodoistConnectionViewModel: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case testing
        case connected(displayName: String)
        case failed(message: String)
    }

    @Published var tokenInput = ""
    @Published private(set) var state = ConnectionState.disconnected
    @Published private(set) var hasStoredToken = false

    private let credentialStore: CredentialStore
    private let client: TodoistConnecting

    init(
        credentialStore: CredentialStore = KeychainCredentialStore(),
        client: TodoistConnecting = TodoistClient()
    ) {
        self.credentialStore = credentialStore
        self.client = client
    }

    var canConnect: Bool {
        !tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && state != .testing
    }

    func connect() async {
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            state = .failed(
                message: TodoistClientError.emptyToken.localizedDescription
            )
            return
        }

        state = .testing
        do {
            let user = try await client.testConnection(token: token)
            try credentialStore.saveToken(token)
            tokenInput = ""
            hasStoredToken = true
            state = .connected(displayName: user.fullName)
        } catch {
            state = .failed(message: safeMessage(for: error))
        }
    }

    func testSavedConnection() async {
        do {
            guard let token = try credentialStore.loadToken() else {
                hasStoredToken = false
                state = .disconnected
                return
            }
            hasStoredToken = true
            state = .testing
            let user = try await client.testConnection(token: token)
            state = .connected(displayName: user.fullName)
        } catch {
            state = .failed(message: safeMessage(for: error))
        }
    }

    func disconnect() {
        do {
            try credentialStore.deleteToken()
            tokenInput = ""
            hasStoredToken = false
            state = .disconnected
        } catch {
            state = .failed(message: safeMessage(for: error))
        }
    }

    private func safeMessage(for error: Error) -> String {
        if let error = error as? TodoistClientError {
            return error.localizedDescription
        }
        if let error = error as? CredentialStoreError {
            return error.localizedDescription
        }
        return NSLocalizedString(
            "TodoistConnection.unknownError",
            comment: "Unknown Todoist connection error"
        )
    }
}
