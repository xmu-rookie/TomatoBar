import Foundation

struct TodoistSyncResponse: Decodable, Equatable {
    let syncToken: String
    let fullSync: Bool
    let projects: [TodoistRemoteProject]
    let tasks: [TodoistRemoteTask]

    private enum CodingKeys: String, CodingKey {
        case syncToken = "sync_token"
        case fullSync = "full_sync"
        case projects
        case tasks = "items"
    }

    init(
        syncToken: String,
        fullSync: Bool,
        projects: [TodoistRemoteProject],
        tasks: [TodoistRemoteTask]
    ) {
        self.syncToken = syncToken
        self.fullSync = fullSync
        self.projects = projects
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        syncToken = try values.decode(String.self, forKey: .syncToken)
        fullSync = try values.decodeIfPresent(Bool.self, forKey: .fullSync) ?? false
        projects = try values.decodeIfPresent(
            [TodoistRemoteProject].self,
            forKey: .projects
        ) ?? []
        tasks = try values.decodeIfPresent(
            [TodoistRemoteTask].self,
            forKey: .tasks
        ) ?? []
    }
}

struct TodoistRemoteProject: Decodable, Equatable {
    let id: String
    let name: String
    let color: String?
    let parentID: String?
    let childOrder: Int
    let isDeleted: Bool
    let isArchived: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case parentID = "parent_id"
        case childOrder = "child_order"
        case isDeleted = "is_deleted"
        case isArchived = "is_archived"
    }

    init(
        id: String,
        name: String,
        color: String? = nil,
        parentID: String? = nil,
        childOrder: Int = 0,
        isDeleted: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.parentID = parentID
        self.childOrder = childOrder
        self.isDeleted = isDeleted
        self.isArchived = isArchived
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeString(forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        color = try values.decodeIfPresent(String.self, forKey: .color)
        parentID = try values.decodeStringIfPresent(forKey: .parentID)
        childOrder = try values.decodeIfPresent(Int.self, forKey: .childOrder) ?? 0
        isDeleted = try values.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        isArchived = try values.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

struct TodoistRemoteTask: Decodable, Equatable {
    struct Due: Decodable, Equatable {
        let date: String
        let string: String
        let isRecurring: Bool

        private enum CodingKeys: String, CodingKey {
            case date
            case string
            case isRecurring = "is_recurring"
        }

        init(date: String, string: String, isRecurring: Bool = false) {
            self.date = date
            self.string = string
            self.isRecurring = isRecurring
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            date = try values.decode(String.self, forKey: .date)
            string = try values.decodeIfPresent(String.self, forKey: .string) ?? date
            isRecurring =
                try values.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
        }
    }

    let id: String
    let projectID: String
    let content: String
    let description: String
    let priority: Int
    let due: Due?
    let parentID: String?
    let childOrder: Int
    let dayOrder: Int
    let checked: Bool
    let isDeleted: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case content
        case description
        case priority
        case due
        case parentID = "parent_id"
        case childOrder = "child_order"
        case dayOrder = "day_order"
        case checked
        case isDeleted = "is_deleted"
    }

    init(
        id: String,
        projectID: String,
        content: String,
        description: String = "",
        priority: Int = 1,
        due: Due? = nil,
        parentID: String? = nil,
        childOrder: Int = 0,
        dayOrder: Int = -1,
        checked: Bool = false,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.content = content
        self.description = description
        self.priority = priority
        self.due = due
        self.parentID = parentID
        self.childOrder = childOrder
        self.dayOrder = dayOrder
        self.checked = checked
        self.isDeleted = isDeleted
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeString(forKey: .id)
        projectID = try values.decodeString(forKey: .projectID)
        content = try values.decode(String.self, forKey: .content)
        description =
            try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        priority = try values.decodeIfPresent(Int.self, forKey: .priority) ?? 1
        due = try values.decodeIfPresent(Due.self, forKey: .due)
        parentID = try values.decodeStringIfPresent(forKey: .parentID)
        childOrder = try values.decodeIfPresent(Int.self, forKey: .childOrder) ?? 0
        dayOrder = try values.decodeIfPresent(Int.self, forKey: .dayOrder) ?? -1
        checked = try values.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        isDeleted = try values.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
}

private extension KeyedDecodingContainer {
    func decodeString(forKey key: Key) throws -> String {
        if let string = try? decode(String.self, forKey: key) {
            return string
        }
        return String(try decode(Int64.self, forKey: key))
    }

    func decodeStringIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }
        return try decodeString(forKey: key)
    }
}
