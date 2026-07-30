import SwiftData
import XCTest
@testable import TomatoBar

final class SessionRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataSessionRepository!

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: FocusSession.self,
            FocusSegment.self,
            PendingTodoistCommand.self,
            TodoistTaskSummary.self,
            configurations: configuration
        )
        repository = SwiftDataSessionRepository(
            context: ModelContext(container)
        )
    }

    override func tearDown() {
        repository = nil
        container = nil
    }

    func testSavesSessionAndSegments() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let draft = FocusSessionDraft(
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            activeDuration: 600,
            tomatoCount: 0.4,
            completedInterval: false,
            segments: [
                .init(
                    kind: .focus,
                    startedAt: start,
                    endedAt: start.addingTimeInterval(300)
                ),
                .init(
                    kind: .pause,
                    startedAt: start.addingTimeInterval(300),
                    endedAt: start.addingTimeInterval(600)
                ),
                .init(
                    kind: .focus,
                    startedAt: start.addingTimeInterval(600),
                    endedAt: start.addingTimeInterval(900)
                ),
            ]
        )

        let id = try repository.save(draft)
        let saved = try XCTUnwrap(repository.fetchAll().first)

        XCTAssertEqual(saved.id, id)
        XCTAssertEqual(saved.activeDuration, 600)
        XCTAssertEqual(saved.tomatoCount, 0.4)
        XCTAssertEqual(saved.syncState, .localOnly)
        XCTAssertEqual(saved.segments.count, 3)
        XCTAssertEqual(
            saved.segments.filter { $0.kind == .focus }
                .reduce(0) { $0 + $1.duration },
            600
        )
    }

    func testUpdatesAndTrimsNote() throws {
        let id = try repository.save(makeDraft())

        try repository.updateNote(
            sessionID: id,
            note: "  Finished the report  \n"
        )

        XCTAssertEqual(
            try repository.fetchAll().first?.note,
            "Finished the report"
        )
    }

    func testDeletesSessionAndSegments() throws {
        let id = try repository.save(makeDraft())

        try repository.delete(sessionID: id)

        XCTAssertTrue(try repository.fetchAll().isEmpty)
        let context = ModelContext(container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FocusSegment>()).isEmpty)
    }

    func testFetchesNewestSessionFirst() throws {
        let earlier = makeDraft(startedAt: Date(timeIntervalSince1970: 1_000))
        let later = makeDraft(startedAt: Date(timeIntervalSince1970: 2_000))
        try repository.save(earlier)
        try repository.save(later)

        XCTAssertEqual(try repository.fetchAll().map(\.id), [later.id, earlier.id])
    }

    func testSavesTodoistTaskAndProjectSnapshot() throws {
        let base = makeDraft()
        let draft = FocusSessionDraft(
            id: base.id,
            startedAt: base.startedAt,
            endedAt: base.endedAt,
            activeDuration: base.activeDuration,
            tomatoCount: base.tomatoCount,
            completedInterval: base.completedInterval,
            todoistTaskID: "task-1",
            taskContent: "Write report",
            todoistProjectID: "project-1",
            projectName: "Work",
            segments: base.segments
        )

        try repository.save(draft)
        let saved = try XCTUnwrap(repository.fetchAll().first)

        XCTAssertEqual(saved.todoistTaskID, "task-1")
        XCTAssertEqual(saved.taskContent, "Write report")
        XCTAssertEqual(saved.todoistProjectID, "project-1")
        XCTAssertEqual(saved.projectName, "Work")
        XCTAssertEqual(saved.syncState, .pending)
    }

    func testTaskSessionAtomicallyQueuesSessionAndSummaryComments() throws {
        let draft = makeTodoistDraft()

        try repository.save(draft)

        let context = ModelContext(container)
        let commands = try context.fetch(
            FetchDescriptor<PendingTodoistCommand>()
        )
        let summary = try XCTUnwrap(
            context.fetch(FetchDescriptor<TodoistTaskSummary>()).first
        )
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(
            Set(commands.map(\.kind)),
            Set([.sessionCommentAdd, .summaryCommentAdd])
        )
        XCTAssertTrue(commands.allSatisfy { $0.state == .pending })
        XCTAssertEqual(summary.taskID, "task-1")
        XCTAssertEqual(summary.tomatoCount, 0.2)
    }

    func testUpdatingNoteUpdatesUnsentSessionComment() throws {
        let draft = makeTodoistDraft()
        try repository.save(draft)

        try repository.updateNote(
            sessionID: draft.id,
            note: "  Finished report  "
        )

        let context = ModelContext(container)
        let command = try XCTUnwrap(
            context.fetch(FetchDescriptor<PendingTodoistCommand>())
                .first { $0.kind == .sessionCommentAdd }
        )
        XCTAssertTrue(command.content?.contains("Finished report") == true)
        XCTAssertEqual(try repository.fetchAll().first?.note, "Finished report")
    }

    func testTwoSessionsCoalesceOneSummaryComment() throws {
        let first = makeTodoistDraft()
        let second = makeTodoistDraft(
            startedAt: Date(timeIntervalSince1970: 2_000)
        )
        try repository.save(first)
        try repository.save(second)

        let context = ModelContext(container)
        let commands = try context.fetch(
            FetchDescriptor<PendingTodoistCommand>()
        )
        XCTAssertEqual(
            commands.filter { $0.kind == .sessionCommentAdd }.count,
            2
        )
        XCTAssertEqual(
            commands.filter { $0.kind == .summaryCommentAdd }.count,
            1
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<TodoistTaskSummary>())
                .first?.tomatoCount,
            0.4
        )
    }

    func testDeletingUnsentOnlySessionRemovesItsOutboxAndSummary() throws {
        let draft = makeTodoistDraft()
        try repository.save(draft)

        try repository.delete(sessionID: draft.id)

        let context = ModelContext(container)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<PendingTodoistCommand>()).isEmpty
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<TodoistTaskSummary>()).isEmpty
        )
    }

    func testReassignsSessionAndRebuildsBothTaskSummaries() throws {
        let draft = makeTodoistDraft()
        try repository.save(draft)
        let newSelection = TodoistTaskSelection(
            taskID: "task-2",
            content: "Review report",
            projectID: "project-2",
            projectName: "Planning"
        )

        try repository.update(
            sessionID: draft.id,
            note: "Reviewed",
            taskSelection: newSelection
        )

        let session = try XCTUnwrap(repository.fetchAll().first)
        XCTAssertEqual(session.todoistTaskID, "task-2")
        XCTAssertEqual(session.taskContent, "Review report")
        XCTAssertEqual(session.note, "Reviewed")
        let context = ModelContext(container)
        let commands = try context.fetch(
            FetchDescriptor<PendingTodoistCommand>()
        )
        XCTAssertEqual(commands.count, 2)
        XCTAssertTrue(commands.allSatisfy { $0.taskID == "task-2" })
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<TodoistTaskSummary>())
                .map(\.taskID),
            ["task-2"]
        )
    }

    func testCanChangeTodoistSessionToNoTask() throws {
        let draft = makeTodoistDraft()
        try repository.save(draft)

        try repository.update(
            sessionID: draft.id,
            note: "",
            taskSelection: nil
        )

        let session = try XCTUnwrap(repository.fetchAll().first)
        XCTAssertNil(session.todoistTaskID)
        XCTAssertEqual(session.syncState, .localOnly)
        let context = ModelContext(container)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<PendingTodoistCommand>()).isEmpty
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<TodoistTaskSummary>()).isEmpty
        )
    }

    func testSessionSurvivesContainerReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let storeURL = directory.appendingPathComponent("sessions.store")
        let sessionID: UUID
        do {
            let diskRepository = try makeDiskRepository(storeURL: storeURL)
            sessionID = try diskRepository.save(makeDraft())
        }

        do {
            let reopenedRepository = try makeDiskRepository(storeURL: storeURL)
            XCTAssertEqual(
                try reopenedRepository.fetchAll().first?.id,
                sessionID
            )
        }
    }

    private func makeDraft(
        startedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> FocusSessionDraft {
        FocusSessionDraft(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(300),
            activeDuration: 300,
            tomatoCount: 0.2,
            completedInterval: false,
            segments: [
                .init(
                    kind: .focus,
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(300)
                ),
            ]
        )
    }

    private func makeDiskRepository(
        storeURL: URL
    ) throws -> SwiftDataSessionRepository {
        let schema = Schema([
            FocusSession.self,
            FocusSegment.self,
            PendingTodoistCommand.self,
            TodoistTaskSummary.self,
        ])
        let configuration = ModelConfiguration(
            "SessionRepositoryTests",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: configuration
        )
        return SwiftDataSessionRepository(context: ModelContext(container))
    }

    private func makeTodoistDraft(
        startedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> FocusSessionDraft {
        let draft = makeDraft(startedAt: startedAt)
        return FocusSessionDraft(
            id: draft.id,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            activeDuration: draft.activeDuration,
            tomatoCount: draft.tomatoCount,
            completedInterval: draft.completedInterval,
            todoistTaskID: "task-1",
            taskContent: "Write report",
            todoistProjectID: "project-1",
            projectName: "Work",
            segments: draft.segments
        )
    }
}
