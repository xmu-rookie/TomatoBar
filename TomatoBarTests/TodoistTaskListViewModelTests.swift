import XCTest
@testable import TomatoBar

@MainActor
final class TodoistTaskListViewModelTests: XCTestCase {
    func testDefaultQueryShowsTodayAndOverdueOnly() {
        let tasks = [
            task(id: "overdue", dueDateKey: "2026-07-29"),
            task(id: "today", dueDateKey: "2026-07-30"),
            task(id: "future", dueDateKey: "2026-07-31"),
            task(id: "undated", dueDateKey: nil),
        ]

        let result = TodoistTaskQuery.filter(
            tasks: tasks,
            searchText: "",
            projectID: nil,
            todayKey: "2026-07-30"
        )

        XCTAssertEqual(result.map(\.id), ["overdue", "today"])
    }

    func testSearchIncludesUndatedTasksAndProjectFilter() {
        let tasks = [
            task(
                id: "matching-content",
                projectID: "work",
                content: "Write report",
                dueDateKey: nil
            ),
            task(
                id: "matching-description",
                projectID: "work",
                content: "Prepare",
                description: "Report charts",
                dueDateKey: "2026-08-01"
            ),
            task(
                id: "other-project",
                projectID: "home",
                content: "Report expenses",
                dueDateKey: nil
            ),
        ]

        let result = TodoistTaskQuery.filter(
            tasks: tasks,
            searchText: "report",
            projectID: "work",
            todayKey: "2026-07-30"
        )

        XCTAssertEqual(
            Set(result.map(\.id)),
            Set(["matching-content", "matching-description"])
        )
    }

    func testRefreshUsesStoredCursorAndKeepsCachedDataOnFailure() async {
        let repository = TodoistCacheRepositoryStub(
            projects: [.init(id: "p", name: "Cached", color: nil, parentID: nil, childOrder: 0)],
            tasks: [task(id: "cached", dueDateKey: "2026-07-30")],
            syncToken: "cursor"
        )
        let client = TodoistSyncClientStub(results: [.failure(.network)])
        let viewModel = TodoistTaskListViewModel(
            credentialStore: TodoistTaskCredentialStoreStub(token: "token"),
            client: client,
            repository: repository,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        await viewModel.refresh()

        XCTAssertEqual(client.receivedSyncTokens, ["cursor"])
        XCTAssertEqual(viewModel.tasks.map(\.id), ["cached"])
        guard case .failed = viewModel.state else {
            return XCTFail("Expected failed state")
        }
    }

    func testExpiredCursorRetriesOneFullSync() async {
        let fullResponse = TodoistSyncResponse(
            syncToken: "fresh",
            fullSync: true,
            projects: [],
            tasks: []
        )
        let repository = TodoistCacheRepositoryStub(syncToken: "expired")
        let client = TodoistSyncClientStub(
            results: [
                .failure(.badRequest),
                .success(fullResponse),
            ]
        )
        let viewModel = TodoistTaskListViewModel(
            credentialStore: TodoistTaskCredentialStoreStub(token: "token"),
            client: client,
            repository: repository,
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        await viewModel.refresh()

        XCTAssertEqual(client.receivedSyncTokens, ["expired", "*"])
        XCTAssertEqual(repository.resetCount, 1)
        XCTAssertEqual(repository.appliedResponses, [fullResponse])
        XCTAssertEqual(viewModel.state, .synced(Date(timeIntervalSince1970: 2_000)))
    }

    func testSelectionContainsProjectSnapshot() {
        let repository = TodoistCacheRepositoryStub(
            projects: [
                .init(id: "work", name: "Work", color: nil, parentID: nil, childOrder: 0),
            ],
            tasks: [
                task(
                    id: "task",
                    projectID: "work",
                    content: "Write report",
                    dueDateKey: "2026-07-30"
                ),
            ]
        )
        let viewModel = TodoistTaskListViewModel(
            credentialStore: TodoistTaskCredentialStoreStub(),
            client: TodoistSyncClientStub(results: []),
            repository: repository
        )

        XCTAssertEqual(
            viewModel.selection(for: repository.tasks[0]),
            TodoistTaskSelection(
                taskID: "task",
                content: "Write report",
                projectID: "work",
                projectName: "Work"
            )
        )
    }

    private func task(
        id: String,
        projectID: String = "project",
        content: String = "Task",
        description: String = "",
        dueDateKey: String?
    ) -> TodoistTaskSnapshot {
        TodoistTaskSnapshot(
            id: id,
            projectID: projectID,
            content: content,
            description: description,
            priority: 1,
            dueDateKey: dueDateKey,
            dueString: dueDateKey,
            isRecurring: false,
            parentID: nil,
            childOrder: 0,
            dayOrder: -1
        )
    }
}

private final class TodoistTaskCredentialStoreStub: CredentialStore {
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

private final class TodoistSyncClientStub: TodoistSyncing {
    var results: [Result<TodoistSyncResponse, TodoistClientError>]
    private(set) var receivedSyncTokens: [String] = []

    init(results: [Result<TodoistSyncResponse, TodoistClientError>]) {
        self.results = results
    }

    func syncResources(
        token _: String,
        syncToken: String
    ) async throws -> TodoistSyncResponse {
        receivedSyncTokens.append(syncToken)
        return try results.removeFirst().get()
    }
}

private final class TodoistCacheRepositoryStub: TodoistCacheRepository {
    var projects: [TodoistProjectSnapshot]
    var tasks: [TodoistTaskSnapshot]
    var storedSyncToken: String?
    var storedLastSyncedAt: Date?
    private(set) var resetCount = 0
    private(set) var appliedResponses: [TodoistSyncResponse] = []

    init(
        projects: [TodoistProjectSnapshot] = [],
        tasks: [TodoistTaskSnapshot] = [],
        syncToken: String? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.projects = projects
        self.tasks = tasks
        storedSyncToken = syncToken
        storedLastSyncedAt = lastSyncedAt
    }

    func fetchProjects() throws -> [TodoistProjectSnapshot] {
        projects
    }

    func fetchTasks() throws -> [TodoistTaskSnapshot] {
        tasks
    }

    func syncToken() throws -> String? {
        storedSyncToken
    }

    func lastSyncedAt() throws -> Date? {
        storedLastSyncedAt
    }

    func apply(_ response: TodoistSyncResponse, at date: Date) throws {
        appliedResponses.append(response)
        storedSyncToken = response.syncToken
        storedLastSyncedAt = date
    }

    func resetSyncToken() throws {
        resetCount += 1
        storedSyncToken = nil
    }
}
