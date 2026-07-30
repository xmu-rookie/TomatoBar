import Foundation
import SwiftData

enum TodoistCommandKind: String, Codable {
    case sessionCommentAdd
    case sessionCommentUpdate
    case sessionCommentDelete
    case summaryCommentAdd
    case summaryCommentUpdate
    case taskClose
    case taskUncomplete

    var apiType: String {
        switch self {
        case .sessionCommentAdd, .summaryCommentAdd:
            return "note_add"
        case .sessionCommentUpdate, .summaryCommentUpdate:
            return "note_update"
        case .sessionCommentDelete:
            return "note_delete"
        case .taskClose:
            return "item_close"
        case .taskUncomplete:
            return "item_uncomplete"
        }
    }
}

enum TodoistOutboxCommandState: String, Codable {
    case pending
    case failed
}

@Model
final class PendingTodoistCommand {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var stateRawValue: String
    var taskID: String
    var sessionID: UUID?
    var content: String?
    var remoteObjectID: String?
    var temporaryID: String?
    var createdAt: Date
    var updatedAt: Date
    var attemptCount: Int
    var lastAttemptAt: Date?
    var lastErrorCode: Int?

    var kind: TodoistCommandKind {
        get {
            TodoistCommandKind(rawValue: kindRawValue) ?? .taskClose
        }
        set {
            kindRawValue = newValue.rawValue
        }
    }

    var state: TodoistOutboxCommandState {
        get {
            TodoistOutboxCommandState(rawValue: stateRawValue) ?? .pending
        }
        set {
            stateRawValue = newValue.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        kind: TodoistCommandKind,
        taskID: String,
        sessionID: UUID? = nil,
        content: String? = nil,
        remoteObjectID: String? = nil,
        temporaryID: String? = nil,
        state: TodoistOutboxCommandState = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        stateRawValue = state.rawValue
        self.taskID = taskID
        self.sessionID = sessionID
        self.content = content
        self.remoteObjectID = remoteObjectID
        self.temporaryID = temporaryID
        self.createdAt = createdAt
        updatedAt = createdAt
        attemptCount = 0
    }

    var envelope: TodoistCommandEnvelope? {
        let arguments: [String: String]
        switch kind {
        case .sessionCommentAdd, .summaryCommentAdd:
            guard let content else {
                return nil
            }
            arguments = ["item_id": taskID, "content": content]
        case .sessionCommentUpdate, .summaryCommentUpdate:
            guard let content, let remoteObjectID else {
                return nil
            }
            arguments = ["id": remoteObjectID, "content": content]
        case .sessionCommentDelete:
            guard let remoteObjectID else {
                return nil
            }
            arguments = ["id": remoteObjectID]
        case .taskClose, .taskUncomplete:
            arguments = ["id": taskID]
        }

        return TodoistCommandEnvelope(
            id: id,
            kind: kind,
            taskID: taskID,
            sessionID: sessionID,
            temporaryID: temporaryID,
            arguments: arguments
        )
    }
}

@Model
final class TodoistTaskSummary {
    @Attribute(.unique) var taskID: String
    var taskContent: String
    var tomatoCount: Double
    var remoteCommentID: String?
    var updatedAt: Date

    init(
        taskID: String,
        taskContent: String,
        tomatoCount: Double,
        remoteCommentID: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.taskID = taskID
        self.taskContent = taskContent
        self.tomatoCount = tomatoCount
        self.remoteCommentID = remoteCommentID
        self.updatedAt = updatedAt
    }
}

struct TodoistCommandEnvelope: Equatable {
    let id: UUID
    let kind: TodoistCommandKind
    let taskID: String
    let sessionID: UUID?
    let temporaryID: String?
    let arguments: [String: String]

    var request: TodoistSyncCommandRequest {
        TodoistSyncCommandRequest(
            type: kind.apiType,
            uuid: id.uuidString.lowercased(),
            tempID: temporaryID,
            arguments: arguments
        )
    }
}

struct TodoistSyncCommandRequest: Encodable, Equatable {
    let type: String
    let uuid: String
    let tempID: String?
    let arguments: [String: String]

    private enum CodingKeys: String, CodingKey {
        case type
        case uuid
        case tempID = "temp_id"
        case arguments = "args"
    }
}

enum TodoistSyncCommandResult: Decodable, Equatable {
    case ok
    case failure(httpCode: Int?, errorCode: Int?)

    private struct Failure: Decodable {
        let httpCode: Int?
        let errorCode: Int?

        private enum CodingKeys: String, CodingKey {
            case httpCode = "http_code"
            case errorCode = "error_code"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self), value == "ok" {
            self = .ok
            return
        }
        let failure = try container.decode(Failure.self)
        self = .failure(
            httpCode: failure.httpCode,
            errorCode: failure.errorCode
        )
    }
}

struct TodoistSyncCommandResponse: Decodable, Equatable {
    let syncStatus: [String: TodoistSyncCommandResult]
    let tempIDMapping: [String: String]

    private enum CodingKeys: String, CodingKey {
        case syncStatus = "sync_status"
        case tempIDMapping = "temp_id_mapping"
    }

    init(
        syncStatus: [String: TodoistSyncCommandResult],
        tempIDMapping: [String: String] = [:]
    ) {
        self.syncStatus = syncStatus
        self.tempIDMapping = tempIDMapping
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        syncStatus = try values.decode(
            [String: TodoistSyncCommandResult].self,
            forKey: .syncStatus
        )
        tempIDMapping = try values.decodeIfPresent(
            [String: String].self,
            forKey: .tempIDMapping
        ) ?? [:]
    }
}

enum TodoistCommentFormatter {
    static func session(tomatoCount: Double, note: String) -> String {
        let base = String.localizedStringWithFormat(
            NSLocalizedString(
                "TodoistComment.session.format",
                comment: "Todoist per-session comment"
            ),
            tomatoCount
        )
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNote.isEmpty ? base : "\(base)\n\n\(trimmedNote)"
    }

    static func summary(tomatoCount: Double) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString(
                "TodoistComment.summary.format",
                comment: "Todoist cumulative comment"
            ),
            tomatoCount
        )
    }
}
