import Foundation
import SwiftData

protocol SessionRepository {
    @discardableResult
    func save(_ draft: FocusSessionDraft) throws -> UUID

    func updateNote(sessionID: UUID, note: String) throws
    func delete(sessionID: UUID) throws
    func fetchAll() throws -> [FocusSession]
}

final class SwiftDataSessionRepository: SessionRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    convenience init(container: ModelContainer = AppPersistence.shared) {
        self.init(context: ModelContext(container))
    }

    @discardableResult
    func save(_ draft: FocusSessionDraft) throws -> UUID {
        let segments = draft.segments.map {
            FocusSegment(
                kind: $0.kind,
                startedAt: $0.startedAt,
                endedAt: $0.endedAt
            )
        }
        let session = FocusSession(
            id: draft.id,
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            activeDuration: draft.activeDuration,
            tomatoCount: draft.tomatoCount,
            completedInterval: draft.completedInterval,
            note: draft.note,
            segments: segments
        )
        context.insert(session)
        try context.save()
        return session.id
    }

    func updateNote(sessionID: UUID, note: String) throws {
        guard let session = try find(sessionID: sessionID) else {
            return
        }
        session.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    func delete(sessionID: UUID) throws {
        guard let session = try find(sessionID: sessionID) else {
            return
        }
        context.delete(session)
        try context.save()
    }

    func fetchAll() throws -> [FocusSession] {
        let descriptor = FetchDescriptor<FocusSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private func find(sessionID: UUID) throws -> FocusSession? {
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

enum AppPersistence {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(
                for: FocusSession.self,
                FocusSegment.self
            )
        } catch {
            fatalError("Unable to create local session store: \(error)")
        }
    }()
}
