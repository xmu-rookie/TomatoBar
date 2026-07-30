import Foundation
import SwiftData

enum FocusSegmentKind: String, Codable {
    case focus
    case pause
}

enum FocusSessionSyncState: String, Codable {
    case localOnly
    case pending
    case synced
    case failed
}

@Model
final class FocusSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var activeDuration: TimeInterval
    var tomatoCount: Double
    var completedInterval: Bool
    var note: String
    var todoistTaskID: String?
    var taskContent: String?
    var todoistProjectID: String?
    var projectName: String?
    var syncStateRawValue: String

    @Relationship(deleteRule: .cascade, inverse: \FocusSegment.session)
    var segments: [FocusSegment]

    var syncState: FocusSessionSyncState {
        get {
            FocusSessionSyncState(rawValue: syncStateRawValue) ?? .localOnly
        }
        set {
            syncStateRawValue = newValue.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        activeDuration: TimeInterval,
        tomatoCount: Double,
        completedInterval: Bool,
        note: String = "",
        todoistTaskID: String? = nil,
        taskContent: String? = nil,
        todoistProjectID: String? = nil,
        projectName: String? = nil,
        syncState: FocusSessionSyncState = .localOnly,
        segments: [FocusSegment] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeDuration = activeDuration
        self.tomatoCount = tomatoCount
        self.completedInterval = completedInterval
        self.note = note
        self.todoistTaskID = todoistTaskID
        self.taskContent = taskContent
        self.todoistProjectID = todoistProjectID
        self.projectName = projectName
        syncStateRawValue = syncState.rawValue
        self.segments = segments
    }
}

@Model
final class FocusSegment {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var startedAt: Date
    var endedAt: Date
    var session: FocusSession?

    var kind: FocusSegmentKind {
        get {
            FocusSegmentKind(rawValue: kindRawValue) ?? .focus
        }
        set {
            kindRawValue = newValue.rawValue
        }
    }

    var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    init(
        id: UUID = UUID(),
        kind: FocusSegmentKind,
        startedAt: Date,
        endedAt: Date,
        session: FocusSession? = nil
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.session = session
    }
}

struct FocusSessionDraft {
    struct Segment {
        let kind: FocusSegmentKind
        let startedAt: Date
        let endedAt: Date
    }

    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let activeDuration: TimeInterval
    let tomatoCount: Double
    let completedInterval: Bool
    let note: String
    let segments: [Segment]

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        activeDuration: TimeInterval,
        tomatoCount: Double,
        completedInterval: Bool,
        note: String = "",
        segments: [Segment]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeDuration = activeDuration
        self.tomatoCount = tomatoCount
        self.completedInterval = completedInterval
        self.note = note
        self.segments = segments
    }
}
