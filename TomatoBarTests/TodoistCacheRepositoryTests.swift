import SwiftData
import XCTest
@testable import TomatoBar

final class TodoistCacheRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataTodoistCacheRepository!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: TodoistProjectCache.self,
            TodoistTaskCache.self,
            TodoistSyncMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        repository = SwiftDataTodoistCacheRepository(
            context: ModelContext(container)
        )
    }

    override func tearDown() {
        repository = nil
        container = nil
    }

    func testFullSyncStoresActiveProjectsTasksAndCursor() throws {
        let syncDate = Date(timeIntervalSince1970: 1_000)

        try repository.apply(.fixture, at: syncDate)

        XCTAssertEqual(
            try repository.fetchProjects(),
            [
                TodoistProjectSnapshot(
                    id: "project-1",
                    name: "Work",
                    color: "blue",
                    parentID: nil,
                    childOrder: 1
                ),
            ]
        )
        XCTAssertEqual(try repository.fetchTasks().map(\.id), ["task-1"])
        XCTAssertEqual(try repository.fetchTasks().first?.dueDateKey, "2026-07-30")
        XCTAssertEqual(try repository.syncToken(), "sync-1")
        XCTAssertEqual(try repository.lastSyncedAt(), syncDate)
    }

    func testIncrementalSyncUpdatesAndDeletesCachedObjects() throws {
        try repository.apply(.fixture, at: Date(timeIntervalSince1970: 1_000))

        let incremental = TodoistSyncResponse(
            syncToken: "sync-2",
            fullSync: false,
            projects: [
                TodoistRemoteProject(id: "project-1", name: "Renamed Work"),
            ],
            tasks: [
                TodoistRemoteTask(
                    id: "task-1",
                    projectID: "project-1",
                    content: "Write final report",
                    checked: true
                ),
            ]
        )
        try repository.apply(incremental, at: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(try repository.fetchProjects().first?.name, "Renamed Work")
        XCTAssertTrue(try repository.fetchTasks().isEmpty)
        XCTAssertEqual(try repository.syncToken(), "sync-2")
    }

    func testFullSyncRemovesObjectsMissingFromServer() throws {
        try repository.apply(.fixture, at: Date(timeIntervalSince1970: 1_000))

        try repository.apply(
            TodoistSyncResponse(
                syncToken: "sync-empty",
                fullSync: true,
                projects: [],
                tasks: []
            ),
            at: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertTrue(try repository.fetchProjects().isEmpty)
        XCTAssertTrue(try repository.fetchTasks().isEmpty)
    }

    func testCacheSurvivesContainerReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let storeURL = directory.appendingPathComponent("todoist.store")
        do {
            let diskRepository = try makeDiskRepository(storeURL: storeURL)
            try diskRepository.apply(.fixture, at: Date(timeIntervalSince1970: 1_000))
        }

        do {
            let reopenedRepository = try makeDiskRepository(storeURL: storeURL)
            XCTAssertEqual(try reopenedRepository.fetchTasks().map(\.id), ["task-1"])
            XCTAssertEqual(try reopenedRepository.syncToken(), "sync-1")
        }
    }

    private func makeDiskRepository(
        storeURL: URL
    ) throws -> SwiftDataTodoistCacheRepository {
        let schema = Schema([
            TodoistProjectCache.self,
            TodoistTaskCache.self,
            TodoistSyncMetadata.self,
        ])
        let configuration = ModelConfiguration(
            "TodoistCacheRepositoryTests",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            configurations: configuration
        )
        return SwiftDataTodoistCacheRepository(context: ModelContext(container))
    }
}

private extension TodoistSyncResponse {
    static var fixture: TodoistSyncResponse {
        TodoistSyncResponse(
            syncToken: "sync-1",
            fullSync: true,
            projects: [
                TodoistRemoteProject(
                    id: "project-1",
                    name: "Work",
                    color: "blue",
                    childOrder: 1
                ),
            ],
            tasks: [
                TodoistRemoteTask(
                    id: "task-1",
                    projectID: "project-1",
                    content: "Write report",
                    priority: 4,
                    due: .init(
                        date: "2026-07-30T12:00:00",
                        string: "today at noon"
                    )
                ),
            ]
        )
    }
}
