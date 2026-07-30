import Foundation
import SwiftData

struct TodoistProjectSnapshot: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let color: String?
    let parentID: String?
    let childOrder: Int
}

struct TodoistTaskSnapshot: Identifiable, Equatable, Hashable {
    let id: String
    let projectID: String
    let content: String
    let description: String
    let priority: Int
    let dueDateKey: String?
    let dueString: String?
    let isRecurring: Bool
    let parentID: String?
    let childOrder: Int
    let dayOrder: Int
}

struct TodoistTaskSelection: Equatable, Hashable {
    let taskID: String
    let content: String
    let projectID: String
    let projectName: String?
}

@Model
final class TodoistProjectCache {
    @Attribute(.unique) var id: String
    var name: String
    var color: String?
    var parentID: String?
    var childOrder: Int
    var cachedAt: Date

    init(
        id: String,
        name: String,
        color: String?,
        parentID: String?,
        childOrder: Int,
        cachedAt: Date
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.parentID = parentID
        self.childOrder = childOrder
        self.cachedAt = cachedAt
    }

    var snapshot: TodoistProjectSnapshot {
        TodoistProjectSnapshot(
            id: id,
            name: name,
            color: color,
            parentID: parentID,
            childOrder: childOrder
        )
    }
}

@Model
final class TodoistTaskCache {
    @Attribute(.unique) var id: String
    var projectID: String
    var content: String
    var taskDescription: String
    var priority: Int
    var dueDateKey: String?
    var dueString: String?
    var isRecurring: Bool
    var parentID: String?
    var childOrder: Int
    var dayOrder: Int
    var cachedAt: Date

    init(
        id: String,
        projectID: String,
        content: String,
        taskDescription: String,
        priority: Int,
        dueDateKey: String?,
        dueString: String?,
        isRecurring: Bool,
        parentID: String?,
        childOrder: Int,
        dayOrder: Int,
        cachedAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.content = content
        self.taskDescription = taskDescription
        self.priority = priority
        self.dueDateKey = dueDateKey
        self.dueString = dueString
        self.isRecurring = isRecurring
        self.parentID = parentID
        self.childOrder = childOrder
        self.dayOrder = dayOrder
        self.cachedAt = cachedAt
    }

    var snapshot: TodoistTaskSnapshot {
        TodoistTaskSnapshot(
            id: id,
            projectID: projectID,
            content: content,
            description: taskDescription,
            priority: priority,
            dueDateKey: dueDateKey,
            dueString: dueString,
            isRecurring: isRecurring,
            parentID: parentID,
            childOrder: childOrder,
            dayOrder: dayOrder
        )
    }
}

@Model
final class TodoistSyncMetadata {
    @Attribute(.unique) var id: String
    var syncToken: String?
    var lastSyncedAt: Date?

    init(
        id: String = "todoist",
        syncToken: String? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.syncToken = syncToken
        self.lastSyncedAt = lastSyncedAt
    }
}

enum TodoistDateKey {
    static func today(
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func normalized(_ apiDate: String?) -> String? {
        guard let apiDate, apiDate.count >= 10 else {
            return nil
        }
        return String(apiDate.prefix(10))
    }
}
