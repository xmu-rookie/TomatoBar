import Foundation
import SwiftData

protocol TodoistCacheRepository {
    func fetchProjects() throws -> [TodoistProjectSnapshot]
    func fetchTasks() throws -> [TodoistTaskSnapshot]
    func syncToken() throws -> String?
    func lastSyncedAt() throws -> Date?
    func apply(_ response: TodoistSyncResponse, at date: Date) throws
    func resetSyncToken() throws
}

final class SwiftDataTodoistCacheRepository: TodoistCacheRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    convenience init(container: ModelContainer = AppPersistence.shared) {
        self.init(context: ModelContext(container))
    }

    func fetchProjects() throws -> [TodoistProjectSnapshot] {
        let descriptor = FetchDescriptor<TodoistProjectCache>(
            sortBy: [
                SortDescriptor(\.childOrder),
                SortDescriptor(\.name),
            ]
        )
        return try context.fetch(descriptor).map(\.snapshot)
    }

    func fetchTasks() throws -> [TodoistTaskSnapshot] {
        let descriptor = FetchDescriptor<TodoistTaskCache>(
            sortBy: [
                SortDescriptor(\.dayOrder),
                SortDescriptor(\.childOrder),
                SortDescriptor(\.content),
            ]
        )
        return try context.fetch(descriptor).map(\.snapshot)
    }

    func syncToken() throws -> String? {
        try metadata()?.syncToken
    }

    func lastSyncedAt() throws -> Date? {
        try metadata()?.lastSyncedAt
    }

    func apply(_ response: TodoistSyncResponse, at date: Date) throws {
        let cachedProjects = try context.fetch(
            FetchDescriptor<TodoistProjectCache>()
        )
        var projectsByID = Dictionary(
            uniqueKeysWithValues: cachedProjects.map { ($0.id, $0) }
        )

        if response.fullSync {
            let activeIDs = Set(
                response.projects
                    .filter { !$0.isDeleted && !$0.isArchived }
                    .map(\.id)
            )
            for project in cachedProjects where !activeIDs.contains(project.id) {
                context.delete(project)
                projectsByID[project.id] = nil
            }
        }

        for remote in response.projects {
            if remote.isDeleted || remote.isArchived {
                if let cached = projectsByID[remote.id] {
                    context.delete(cached)
                    projectsByID[remote.id] = nil
                }
                continue
            }

            if let cached = projectsByID[remote.id] {
                cached.name = remote.name
                cached.color = remote.color
                cached.parentID = remote.parentID
                cached.childOrder = remote.childOrder
                cached.cachedAt = date
            } else {
                let cached = TodoistProjectCache(
                    id: remote.id,
                    name: remote.name,
                    color: remote.color,
                    parentID: remote.parentID,
                    childOrder: remote.childOrder,
                    cachedAt: date
                )
                context.insert(cached)
                projectsByID[remote.id] = cached
            }
        }

        let cachedTasks = try context.fetch(FetchDescriptor<TodoistTaskCache>())
        var tasksByID = Dictionary(
            uniqueKeysWithValues: cachedTasks.map { ($0.id, $0) }
        )

        if response.fullSync {
            let activeIDs = Set(
                response.tasks
                    .filter { !$0.isDeleted && !$0.checked }
                    .map(\.id)
            )
            for task in cachedTasks where !activeIDs.contains(task.id) {
                context.delete(task)
                tasksByID[task.id] = nil
            }
        }

        for remote in response.tasks {
            if remote.isDeleted || remote.checked {
                if let cached = tasksByID[remote.id] {
                    context.delete(cached)
                    tasksByID[remote.id] = nil
                }
                continue
            }

            if let cached = tasksByID[remote.id] {
                update(cached, from: remote, at: date)
            } else {
                let cached = TodoistTaskCache(
                    id: remote.id,
                    projectID: remote.projectID,
                    content: remote.content,
                    taskDescription: remote.description,
                    priority: remote.priority,
                    dueDateKey: TodoistDateKey.normalized(remote.due?.date),
                    dueString: remote.due?.string,
                    isRecurring: remote.due?.isRecurring ?? false,
                    parentID: remote.parentID,
                    childOrder: remote.childOrder,
                    dayOrder: remote.dayOrder,
                    cachedAt: date
                )
                context.insert(cached)
                tasksByID[remote.id] = cached
            }
        }

        let storedMetadata = try metadata()
        let metadata = storedMetadata ?? TodoistSyncMetadata()
        if storedMetadata == nil {
            context.insert(metadata)
        }
        metadata.syncToken = response.syncToken
        metadata.lastSyncedAt = date
        try context.save()
    }

    func resetSyncToken() throws {
        guard let metadata = try metadata() else {
            return
        }
        metadata.syncToken = nil
        try context.save()
    }

    private func metadata() throws -> TodoistSyncMetadata? {
        var descriptor = FetchDescriptor<TodoistSyncMetadata>(
            predicate: #Predicate { $0.id == "todoist" }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func update(
        _ cached: TodoistTaskCache,
        from remote: TodoistRemoteTask,
        at date: Date
    ) {
        cached.projectID = remote.projectID
        cached.content = remote.content
        cached.taskDescription = remote.description
        cached.priority = remote.priority
        cached.dueDateKey = TodoistDateKey.normalized(remote.due?.date)
        cached.dueString = remote.due?.string
        cached.isRecurring = remote.due?.isRecurring ?? false
        cached.parentID = remote.parentID
        cached.childOrder = remote.childOrder
        cached.dayOrder = remote.dayOrder
        cached.cachedAt = date
    }
}
