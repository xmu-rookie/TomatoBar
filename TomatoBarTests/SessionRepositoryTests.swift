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
        let schema = Schema([FocusSession.self, FocusSegment.self])
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
}
