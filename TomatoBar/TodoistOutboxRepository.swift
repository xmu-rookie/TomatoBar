import Foundation
import SwiftData

struct TodoistOutboxCounts: Equatable {
    let pending: Int
    let failed: Int

    var total: Int {
        pending + failed
    }
}

struct TodoistOutboxApplyResult: Equatable {
    let succeeded: Int
    let failed: Int
    let taskCacheChanged: Bool
}

protocol TodoistOutboxRepository {
    func fetchPending(limit: Int) throws -> [TodoistCommandEnvelope]
    func counts() throws -> TodoistOutboxCounts
    func recordTransportFailure(
        commandIDs: [UUID],
        at date: Date
    ) throws
    func apply(
        response: TodoistSyncCommandResponse,
        commands: [TodoistCommandEnvelope],
        at date: Date
    ) throws -> TodoistOutboxApplyResult
    func retryFailed(at date: Date) throws
    func enqueueTaskClose(
        selection: TodoistTaskSelection,
        at date: Date
    ) throws
    func enqueueTaskUncomplete(
        selection: TodoistTaskSelection,
        at date: Date
    ) throws
}

final class SwiftDataTodoistOutboxRepository: TodoistOutboxRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    convenience init(container: ModelContainer = AppPersistence.shared) {
        self.init(context: ModelContext(container))
    }

    func fetchPending(limit: Int = 100) throws -> [TodoistCommandEnvelope] {
        var descriptor = FetchDescriptor<PendingTodoistCommand>(
            predicate: #Predicate {
                $0.stateRawValue == "pending"
            },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = max(1, min(100, limit))
        return try context.fetch(descriptor).compactMap(\.envelope)
    }

    func counts() throws -> TodoistOutboxCounts {
        let commands = try context.fetch(
            FetchDescriptor<PendingTodoistCommand>()
        )
        return TodoistOutboxCounts(
            pending: commands.filter { $0.state == .pending }.count,
            failed: commands.filter { $0.state == .failed }.count
        )
    }

    func recordTransportFailure(
        commandIDs: [UUID],
        at date: Date
    ) throws {
        let idSet = Set(commandIDs)
        for command in try allCommands() where idSet.contains(command.id) {
            command.attemptCount += 1
            command.lastAttemptAt = date
            command.updatedAt = date
        }
        try context.save()
    }

    func apply(
        response: TodoistSyncCommandResponse,
        commands: [TodoistCommandEnvelope],
        at date: Date
    ) throws -> TodoistOutboxApplyResult {
        let storedByID = Dictionary(
            uniqueKeysWithValues: try allCommands().map { ($0.id, $0) }
        )
        var succeeded = 0
        var failed = 0
        var taskCacheChanged = false

        for envelope in commands {
            guard let stored = storedByID[envelope.id] else {
                continue
            }
            let key = envelope.id.uuidString.lowercased()
            guard let result = response.syncStatus[key] else {
                stored.attemptCount += 1
                stored.lastAttemptAt = date
                stored.updatedAt = date
                continue
            }

            switch result {
            case .ok:
                let applied = try applySuccess(
                    envelope,
                    response: response,
                    at: date
                )
                guard applied else {
                    stored.attemptCount += 1
                    stored.lastAttemptAt = date
                    stored.updatedAt = date
                    continue
                }
                if envelope.kind == .taskClose
                    || envelope.kind == .taskUncomplete {
                    taskCacheChanged = true
                }
                context.delete(stored)
                succeeded += 1

            case let .failure(httpCode, errorCode):
                stored.state = .failed
                stored.attemptCount += 1
                stored.lastAttemptAt = date
                stored.lastErrorCode = errorCode ?? httpCode
                stored.updatedAt = date
                if let sessionID = envelope.sessionID,
                   let session = try findSession(id: sessionID) {
                    session.syncState = .failed
                }
                failed += 1
            }
        }

        try context.save()
        return TodoistOutboxApplyResult(
            succeeded: succeeded,
            failed: failed,
            taskCacheChanged: taskCacheChanged
        )
    }

    func retryFailed(at date: Date) throws {
        for command in try allCommands() where command.state == .failed {
            command.state = .pending
            command.lastErrorCode = nil
            command.updatedAt = date
            if let sessionID = command.sessionID,
               let session = try findSession(id: sessionID) {
                session.syncState = .pending
            }
        }
        try context.save()
    }

    func enqueueTaskClose(
        selection: TodoistTaskSelection,
        at date: Date = Date()
    ) throws {
        let taskCommands = try allCommands().filter {
            $0.taskID == selection.taskID
                && ($0.kind == .taskClose || $0.kind == .taskUncomplete)
        }
        if let pendingUndo = taskCommands.first(where: {
            $0.kind == .taskUncomplete
        }) {
            context.delete(pendingUndo)
        } else if !taskCommands.contains(where: { $0.kind == .taskClose }) {
            context.insert(
                PendingTodoistCommand(
                    kind: .taskClose,
                    taskID: selection.taskID,
                    createdAt: date
                )
            )
        }
        try context.save()
    }

    func enqueueTaskUncomplete(
        selection: TodoistTaskSelection,
        at date: Date = Date()
    ) throws {
        let taskCommands = try allCommands().filter {
            $0.taskID == selection.taskID
                && ($0.kind == .taskClose || $0.kind == .taskUncomplete)
        }
        if let pendingClose = taskCommands.first(where: {
            $0.kind == .taskClose
        }) {
            context.delete(pendingClose)
        } else if !taskCommands.contains(where: {
            $0.kind == .taskUncomplete
        }) {
            context.insert(
                PendingTodoistCommand(
                    kind: .taskUncomplete,
                    taskID: selection.taskID,
                    createdAt: date
                )
            )
        }
        try context.save()
    }

    private func applySuccess(
        _ envelope: TodoistCommandEnvelope,
        response: TodoistSyncCommandResponse,
        at date: Date
    ) throws -> Bool {
        switch envelope.kind {
        case .sessionCommentAdd:
            guard let temporaryID = envelope.temporaryID,
                  let remoteID = response.tempIDMapping[temporaryID] else {
                return false
            }
            if let sessionID = envelope.sessionID,
               let session = try findSession(id: sessionID) {
                session.todoistCommentID = remoteID
                session.syncState = .synced
            }

        case .sessionCommentUpdate:
            if let sessionID = envelope.sessionID,
               let session = try findSession(id: sessionID) {
                session.syncState = .synced
            }

        case .sessionCommentDelete:
            break

        case .summaryCommentAdd:
            guard let temporaryID = envelope.temporaryID,
                  let remoteID = response.tempIDMapping[temporaryID] else {
                return false
            }
            if let summary = try findSummary(taskID: envelope.taskID) {
                summary.remoteCommentID = remoteID
                summary.updatedAt = date
            }

        case .summaryCommentUpdate:
            if let summary = try findSummary(taskID: envelope.taskID) {
                summary.updatedAt = date
            }

        case .taskClose:
            if let task = try findTask(id: envelope.taskID) {
                context.delete(task)
            }

        case .taskUncomplete:
            break
        }
        return true
    }

    private func allCommands() throws -> [PendingTodoistCommand] {
        try context.fetch(FetchDescriptor<PendingTodoistCommand>())
    }

    private func findSession(id: UUID) throws -> FocusSession? {
        try context.fetch(FetchDescriptor<FocusSession>())
            .first { $0.id == id }
    }

    private func findSummary(taskID: String) throws -> TodoistTaskSummary? {
        try context.fetch(FetchDescriptor<TodoistTaskSummary>())
            .first { $0.taskID == taskID }
    }

    private func findTask(id: String) throws -> TodoistTaskCache? {
        try context.fetch(FetchDescriptor<TodoistTaskCache>())
            .first { $0.id == id }
    }
}

struct TodoistOutboxComposer {
    let context: ModelContext

    func enqueueNewSession(
        _ session: FocusSession,
        at date: Date = Date()
    ) throws {
        guard let taskID = session.todoistTaskID,
              let taskContent = session.taskContent else {
            return
        }

        session.syncState = .pending
        context.insert(
            PendingTodoistCommand(
                kind: .sessionCommentAdd,
                taskID: taskID,
                sessionID: session.id,
                content: TodoistCommentFormatter.session(
                    tomatoCount: session.tomatoCount,
                    note: session.note
                ),
                temporaryID: UUID().uuidString.lowercased(),
                createdAt: date
            )
        )

        var sessions = try sessions(for: taskID)
        if !sessions.contains(where: { $0.id == session.id }) {
            sessions.append(session)
        }
        try updateSummary(
            taskID: taskID,
            taskContent: taskContent,
            sessions: sessions,
            at: date
        )
    }

    func updateSessionNote(
        _ session: FocusSession,
        at date: Date = Date()
    ) throws {
        guard let taskID = session.todoistTaskID else {
            return
        }
        let content = TodoistCommentFormatter.session(
            tomatoCount: session.tomatoCount,
            note: session.note
        )
        let commands = try allCommands()
        if let pendingAdd = commands.first(where: {
            $0.sessionID == session.id
                && $0.kind == .sessionCommentAdd
        }) {
            pendingAdd.content = content
            pendingAdd.updatedAt = date
            pendingAdd.state = .pending
            session.syncState = .pending
        } else if let commentID = session.todoistCommentID {
            if let pendingUpdate = commands.first(where: {
                $0.sessionID == session.id
                    && $0.kind == .sessionCommentUpdate
            }) {
                pendingUpdate.content = content
                pendingUpdate.updatedAt = date
                pendingUpdate.state = .pending
            } else {
                context.insert(
                    PendingTodoistCommand(
                        kind: .sessionCommentUpdate,
                        taskID: taskID,
                        sessionID: session.id,
                        content: content,
                        remoteObjectID: commentID,
                        createdAt: date
                    )
                )
            }
            session.syncState = .pending
        }
    }

    func prepareDelete(
        _ session: FocusSession,
        at date: Date = Date()
    ) throws {
        guard let taskID = session.todoistTaskID else {
            return
        }

        let sessionCommands = try allCommands().filter {
            $0.sessionID == session.id
        }
        for command in sessionCommands {
            context.delete(command)
        }
        if let commentID = session.todoistCommentID {
            context.insert(
                PendingTodoistCommand(
                    kind: .sessionCommentDelete,
                    taskID: taskID,
                    remoteObjectID: commentID,
                    createdAt: date
                )
            )
        }

        let remaining = try sessions(for: taskID).filter {
            $0.id != session.id
        }
        try updateSummary(
            taskID: taskID,
            taskContent: session.taskContent ?? "",
            sessions: remaining,
            at: date
        )
    }

    private func updateSummary(
        taskID: String,
        taskContent: String,
        sessions: [FocusSession],
        at date: Date
    ) throws {
        let total = sessions.reduce(0) { $0 + $1.tomatoCount }
        let commands = try allCommands()
        let summaryCommands = commands.filter {
            $0.taskID == taskID
                && ($0.kind == .summaryCommentAdd
                    || $0.kind == .summaryCommentUpdate)
        }
        let existingSummary = try context.fetch(
            FetchDescriptor<TodoistTaskSummary>()
        ).first { $0.taskID == taskID }

        if sessions.isEmpty,
           existingSummary?.remoteCommentID == nil {
            for command in summaryCommands {
                context.delete(command)
            }
            if let existingSummary {
                context.delete(existingSummary)
            }
            return
        }

        let summary = existingSummary ?? TodoistTaskSummary(
            taskID: taskID,
            taskContent: taskContent,
            tomatoCount: total,
            updatedAt: date
        )
        if existingSummary == nil {
            context.insert(summary)
        }
        summary.taskContent = taskContent
        summary.tomatoCount = total
        summary.updatedAt = date
        let content = TodoistCommentFormatter.summary(tomatoCount: total)

        if let pending = summaryCommands.first {
            pending.content = content
            pending.state = .pending
            pending.updatedAt = date
            for duplicate in summaryCommands.dropFirst() {
                context.delete(duplicate)
            }
        } else if let remoteCommentID = summary.remoteCommentID {
            context.insert(
                PendingTodoistCommand(
                    kind: .summaryCommentUpdate,
                    taskID: taskID,
                    content: content,
                    remoteObjectID: remoteCommentID,
                    createdAt: date
                )
            )
        } else {
            context.insert(
                PendingTodoistCommand(
                    kind: .summaryCommentAdd,
                    taskID: taskID,
                    content: content,
                    temporaryID: UUID().uuidString.lowercased(),
                    createdAt: date
                )
            )
        }
    }

    private func sessions(for taskID: String) throws -> [FocusSession] {
        try context.fetch(FetchDescriptor<FocusSession>())
            .filter { $0.todoistTaskID == taskID }
    }

    private func allCommands() throws -> [PendingTodoistCommand] {
        try context.fetch(FetchDescriptor<PendingTodoistCommand>())
    }
}
