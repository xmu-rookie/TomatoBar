import XCTest
@testable import TomatoBar

@MainActor
final class TodoistOutboxProcessorTests: XCTestCase {
    func testProcessesPendingCommandAndPassesPersistentUUID() async {
        let command = makeCommand()
        let repository = OutboxRepositoryStub(commands: [command])
        let client = CommandClientStub(
            result: .success(
                TodoistSyncCommandResponse(
                    syncStatus: [
                        command.id.uuidString.lowercased(): .ok,
                    ]
                )
            )
        )
        let processor = TodoistOutboxProcessor(
            credentialStore: OutboxCredentialStoreStub(token: "token"),
            client: client,
            repository: repository
        )

        await processor.process()

        XCTAssertEqual(client.received.first?.first?.uuid, command.request.uuid)
        XCTAssertEqual(repository.appliedCommands, [command])
        XCTAssertEqual(processor.state, .synced)
    }

    func testNetworkFailureLeavesCommandPendingForLaterRetry() async {
        let command = makeCommand()
        let repository = OutboxRepositoryStub(commands: [command])
        let processor = TodoistOutboxProcessor(
            credentialStore: OutboxCredentialStoreStub(token: "token"),
            client: CommandClientStub(result: .failure(.network)),
            repository: repository
        )

        await processor.process()

        XCTAssertEqual(repository.transportFailureIDs, [command.id])
        XCTAssertEqual(
            processor.state,
            .pending(.init(pending: 1, failed: 0))
        )
    }

    func testMissingTokenDoesNotRemovePendingCommand() async {
        let command = makeCommand()
        let repository = OutboxRepositoryStub(commands: [command])
        let client = CommandClientStub(
            result: .failure(.network)
        )
        let processor = TodoistOutboxProcessor(
            credentialStore: OutboxCredentialStoreStub(token: nil),
            client: client,
            repository: repository
        )

        await processor.process()

        XCTAssertTrue(client.received.isEmpty)
        XCTAssertEqual(
            processor.state,
            .notConnected(.init(pending: 1, failed: 0))
        )
    }

    private func makeCommand() -> TodoistCommandEnvelope {
        TodoistCommandEnvelope(
            id: UUID(),
            kind: .taskClose,
            taskID: "task-1",
            sessionID: nil,
            temporaryID: nil,
            arguments: ["id": "task-1"]
        )
    }
}

private final class OutboxCredentialStoreStub: CredentialStore {
    var token: String?

    init(token: String?) {
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

private final class CommandClientStub: TodoistCommandExecuting {
    let result: Result<TodoistSyncCommandResponse, TodoistClientError>
    private(set) var received: [[TodoistSyncCommandRequest]] = []

    init(result: Result<TodoistSyncCommandResponse, TodoistClientError>) {
        self.result = result
    }

    func execute(
        token _: String,
        commands: [TodoistSyncCommandRequest]
    ) async throws -> TodoistSyncCommandResponse {
        received.append(commands)
        return try result.get()
    }
}

private final class OutboxRepositoryStub: TodoistOutboxRepository {
    var commands: [TodoistCommandEnvelope]
    var failedCount = 0
    private(set) var appliedCommands: [TodoistCommandEnvelope] = []
    private(set) var transportFailureIDs: [UUID] = []

    init(commands: [TodoistCommandEnvelope]) {
        self.commands = commands
    }

    func fetchPending(limit: Int) throws -> [TodoistCommandEnvelope] {
        Array(commands.prefix(limit))
    }

    func counts() throws -> TodoistOutboxCounts {
        .init(pending: commands.count, failed: failedCount)
    }

    func recordTransportFailure(
        commandIDs: [UUID],
        at _: Date
    ) throws {
        transportFailureIDs = commandIDs
    }

    func apply(
        response _: TodoistSyncCommandResponse,
        commands: [TodoistCommandEnvelope],
        at _: Date
    ) throws -> TodoistOutboxApplyResult {
        appliedCommands.append(contentsOf: commands)
        let ids = Set(commands.map(\.id))
        self.commands.removeAll { ids.contains($0.id) }
        return .init(
            succeeded: commands.count,
            failed: 0,
            taskCacheChanged: commands.contains {
                $0.kind == .taskClose || $0.kind == .taskUncomplete
            }
        )
    }

    func retryFailed(at _: Date) throws {
        failedCount = 0
    }

    func enqueueTaskClose(
        selection _: TodoistTaskSelection,
        at _: Date
    ) throws {}

    func enqueueTaskUncomplete(
        selection _: TodoistTaskSelection,
        at _: Date
    ) throws {}
}
