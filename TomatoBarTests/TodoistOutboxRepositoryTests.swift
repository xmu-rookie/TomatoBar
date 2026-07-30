import SwiftData
import XCTest
@testable import TomatoBar

final class TodoistOutboxRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repository: SwiftDataTodoistOutboxRepository!

    override func setUpWithError() throws {
        container = try makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        repository = SwiftDataTodoistOutboxRepository(context: context)
    }

    override func tearDown() {
        repository = nil
        context = nil
        container = nil
    }

    func testSuccessfulCommentBatchStoresRemoteIDsAndClearsOutbox() throws {
        let sessionRepository = SwiftDataSessionRepository(context: context)
        let sessionID = try sessionRepository.save(makeDraft())
        let commands = try repository.fetchPending(limit: 100)
        let status = Dictionary(
            uniqueKeysWithValues: commands.map {
                ($0.id.uuidString.lowercased(), TodoistSyncCommandResult.ok)
            }
        )
        let mappings = Dictionary(
            uniqueKeysWithValues: commands.compactMap { command in
                command.temporaryID.map { ($0, "remote-\($0)") }
            }
        )

        let result = try repository.apply(
            response: TodoistSyncCommandResponse(
                syncStatus: status,
                tempIDMapping: mappings
            ),
            commands: commands,
            at: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(result.succeeded, 2)
        XCTAssertEqual(try repository.counts(), .init(pending: 0, failed: 0))
        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<FocusSession>())
                .first { $0.id == sessionID }
        )
        XCTAssertEqual(session.syncState, .synced)
        XCTAssertNotNil(session.todoistCommentID)
        XCTAssertNotNil(
            try context.fetch(FetchDescriptor<TodoistTaskSummary>())
                .first?.remoteCommentID
        )
    }

    func testCommandFailureIsDurableAndCanBeRetriedWithSameUUID() throws {
        try SwiftDataSessionRepository(context: context).save(makeDraft())
        let command = try XCTUnwrap(repository.fetchPending(limit: 1).first)

        _ = try repository.apply(
            response: TodoistSyncCommandResponse(
                syncStatus: [
                    command.id.uuidString.lowercased():
                        .failure(httpCode: 400, errorCode: 15),
                ]
            ),
            commands: [command],
            at: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(try repository.counts().failed, 1)
        try repository.retryFailed(at: Date(timeIntervalSince1970: 3_000))
        let retried = try XCTUnwrap(repository.fetchPending(limit: 1).first)
        XCTAssertEqual(retried.id, command.id)
        XCTAssertEqual(retried.request.uuid, command.request.uuid)
    }

    func testSuccessfulAddWithoutIDMappingRemainsPending() throws {
        try SwiftDataSessionRepository(context: context).save(makeDraft())
        let command = try XCTUnwrap(
            repository.fetchPending(limit: 100)
                .first { $0.kind == .sessionCommentAdd }
        )

        let result = try repository.apply(
            response: TodoistSyncCommandResponse(
                syncStatus: [
                    command.id.uuidString.lowercased(): .ok,
                ]
            ),
            commands: [command],
            at: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(result.succeeded, 0)
        XCTAssertEqual(try repository.counts().pending, 2)
        XCTAssertEqual(
            try repository.fetchPending(limit: 100)
                .first { $0.id == command.id }?.request.uuid,
            command.request.uuid
        )
    }

    func testTransportFailureSurvivesContainerReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let storeURL = directory.appendingPathComponent("outbox.store")
        let commandID: UUID

        do {
            let diskContainer = try makeContainer(
                configuration: diskConfiguration(url: storeURL)
            )
            let diskContext = ModelContext(diskContainer)
            let diskRepository = SwiftDataTodoistOutboxRepository(
                context: diskContext
            )
            try SwiftDataSessionRepository(context: diskContext)
                .save(makeDraft())
            let command = try XCTUnwrap(
                diskRepository.fetchPending(limit: 1).first
            )
            commandID = command.id
            try diskRepository.recordTransportFailure(
                commandIDs: [commandID],
                at: Date(timeIntervalSince1970: 2_000)
            )
        }

        do {
            let reopenedContainer = try makeContainer(
                configuration: diskConfiguration(url: storeURL)
            )
            let reopened = SwiftDataTodoistOutboxRepository(
                context: ModelContext(reopenedContainer)
            )
            let command = try XCTUnwrap(reopened.fetchPending(limit: 1).first)
            XCTAssertEqual(command.id, commandID)
        }
    }

    func testUndoBeforeCloseIsSentCancelsPendingClose() throws {
        let selection = taskSelection()

        try repository.enqueueTaskClose(
            selection: selection,
            at: Date(timeIntervalSince1970: 1_000)
        )
        try repository.enqueueTaskUncomplete(
            selection: selection,
            at: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(try repository.counts(), .init(pending: 0, failed: 0))
    }

    func testSuccessfulCloseRemovesCacheAndUndoQueuesUncomplete() throws {
        let selection = taskSelection()
        context.insert(
            TodoistTaskCache(
                id: selection.taskID,
                projectID: selection.projectID,
                content: selection.content,
                taskDescription: "",
                priority: 1,
                dueDateKey: nil,
                dueString: nil,
                isRecurring: false,
                parentID: nil,
                childOrder: 0,
                dayOrder: -1,
                cachedAt: Date()
            )
        )
        try context.save()
        try repository.enqueueTaskClose(selection: selection, at: Date())
        let close = try XCTUnwrap(repository.fetchPending(limit: 1).first)

        let result = try repository.apply(
            response: TodoistSyncCommandResponse(
                syncStatus: [
                    close.id.uuidString.lowercased(): .ok,
                ]
            ),
            commands: [close],
            at: Date()
        )
        try repository.enqueueTaskUncomplete(selection: selection, at: Date())

        XCTAssertTrue(result.taskCacheChanged)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<TodoistTaskCache>()).isEmpty
        )
        XCTAssertEqual(
            try repository.fetchPending(limit: 1).first?.kind,
            .taskUncomplete
        )
    }

    func testEditingSyncedNoteQueuesCommentUpdate() throws {
        let sessionRepository = SwiftDataSessionRepository(context: context)
        let sessionID = try sessionRepository.save(makeDraft())
        try applyAllPendingSuccessfully()

        try sessionRepository.updateNote(
            sessionID: sessionID,
            note: "New detail"
        )

        let command = try XCTUnwrap(repository.fetchPending(limit: 10).first)
        XCTAssertEqual(command.kind, .sessionCommentUpdate)
        XCTAssertTrue(command.arguments["content"]?.contains("New detail") == true)
        XCTAssertNotNil(command.arguments["id"])
    }

    func testDeletingSyncedSessionQueuesDeleteAndRecalculatesSummary() throws {
        let sessionRepository = SwiftDataSessionRepository(context: context)
        let firstID = try sessionRepository.save(makeDraft())
        var second = makeDraft()
        second = FocusSessionDraft(
            id: UUID(),
            startedAt: second.startedAt.addingTimeInterval(600),
            endedAt: second.endedAt.addingTimeInterval(600),
            activeDuration: second.activeDuration,
            tomatoCount: second.tomatoCount,
            completedInterval: second.completedInterval,
            todoistTaskID: second.todoistTaskID,
            taskContent: second.taskContent,
            todoistProjectID: second.todoistProjectID,
            projectName: second.projectName,
            segments: second.segments.map {
                .init(
                    kind: $0.kind,
                    startedAt: $0.startedAt.addingTimeInterval(600),
                    endedAt: $0.endedAt.addingTimeInterval(600)
                )
            }
        )
        try sessionRepository.save(second)
        try applyAllPendingSuccessfully()

        try sessionRepository.delete(sessionID: firstID)

        let commands = try repository.fetchPending(limit: 10)
        XCTAssertEqual(
            Set(commands.map(\.kind)),
            Set([.sessionCommentDelete, .summaryCommentUpdate])
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<TodoistTaskSummary>())
                .first?.tomatoCount,
            0.2
        )
    }

    private func makeDraft() -> FocusSessionDraft {
        let start = Date(timeIntervalSince1970: 1_000)
        return FocusSessionDraft(
            startedAt: start,
            endedAt: start.addingTimeInterval(300),
            activeDuration: 300,
            tomatoCount: 0.2,
            completedInterval: false,
            todoistTaskID: "task-1",
            taskContent: "Write report",
            todoistProjectID: "project-1",
            projectName: "Work",
            segments: [
                .init(
                    kind: .focus,
                    startedAt: start,
                    endedAt: start.addingTimeInterval(300)
                ),
            ]
        )
    }

    private func taskSelection() -> TodoistTaskSelection {
        TodoistTaskSelection(
            taskID: "task-1",
            content: "Write report",
            projectID: "project-1",
            projectName: "Work"
        )
    }

    private func applyAllPendingSuccessfully() throws {
        let commands = try repository.fetchPending(limit: 100)
        let statuses = Dictionary(
            uniqueKeysWithValues: commands.map {
                ($0.id.uuidString.lowercased(), TodoistSyncCommandResult.ok)
            }
        )
        let mappings = Dictionary(
            uniqueKeysWithValues: commands.compactMap { command in
                command.temporaryID.map { ($0, "remote-\($0)") }
            }
        )
        _ = try repository.apply(
            response: TodoistSyncCommandResponse(
                syncStatus: statuses,
                tempIDMapping: mappings
            ),
            commands: commands,
            at: Date(timeIntervalSince1970: 2_000)
        )
    }

    private func makeContainer(
        configuration: ModelConfiguration
    ) throws -> ModelContainer {
        try ModelContainer(
            for: FocusSession.self,
            FocusSegment.self,
            TodoistProjectCache.self,
            TodoistTaskCache.self,
            TodoistSyncMetadata.self,
            PendingTodoistCommand.self,
            TodoistTaskSummary.self,
            configurations: configuration
        )
    }

    private func diskConfiguration(url: URL) -> ModelConfiguration {
        let schema = Schema([
            FocusSession.self,
            FocusSegment.self,
            TodoistProjectCache.self,
            TodoistTaskCache.self,
            TodoistSyncMetadata.self,
            PendingTodoistCommand.self,
            TodoistTaskSummary.self,
        ])
        return ModelConfiguration(
            "TodoistOutboxRepositoryTests",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
    }
}
