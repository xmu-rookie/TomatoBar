import Combine
import Foundation

enum TodoistTaskQuery {
    static func filter(
        tasks: [TodoistTaskSnapshot],
        searchText: String,
        projectID: String?,
        todayKey: String
    ) -> [TodoistTaskSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return tasks
            .filter { task in
                if let projectID, task.projectID != projectID {
                    return false
                }
                if query.isEmpty {
                    guard let dueDateKey = task.dueDateKey else {
                        return false
                    }
                    return dueDateKey <= todayKey
                }
                return task.content.localizedCaseInsensitiveContains(query)
                    || task.description.localizedCaseInsensitiveContains(query)
            }
            .sorted(by: taskSort)
    }

    private static func taskSort(
        _ lhs: TodoistTaskSnapshot,
        _ rhs: TodoistTaskSnapshot
    ) -> Bool {
        switch (lhs.dueDateKey, rhs.dueDateKey) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        let leftOrder = lhs.dayOrder < 0 ? Int.max : lhs.dayOrder
        let rightOrder = rhs.dayOrder < 0 ? Int.max : rhs.dayOrder
        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }
        return lhs.content.localizedCaseInsensitiveCompare(rhs.content)
            == .orderedAscending
    }
}

@MainActor
final class TodoistTaskListViewModel: ObservableObject {
    enum SyncState: Equatable {
        case idle
        case syncing
        case synced(Date)
        case notConnected
        case failed(message: String)
    }

    @Published private(set) var projects: [TodoistProjectSnapshot] = []
    @Published private(set) var tasks: [TodoistTaskSnapshot] = []
    @Published private(set) var state = SyncState.idle
    @Published var searchText = ""
    @Published var selectedProjectID: String?

    private let credentialStore: CredentialStore
    private let client: TodoistSyncing
    private let repository: TodoistCacheRepository
    private let now: () -> Date
    private let calendar: Calendar

    init(
        credentialStore: CredentialStore = KeychainCredentialStore(),
        client: TodoistSyncing = TodoistClient(),
        repository: TodoistCacheRepository =
            SwiftDataTodoistCacheRepository(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.credentialStore = credentialStore
        self.client = client
        self.repository = repository
        self.now = now
        self.calendar = calendar
        loadCache()
    }

    var visibleTasks: [TodoistTaskSnapshot] {
        TodoistTaskQuery.filter(
            tasks: tasks,
            searchText: searchText,
            projectID: selectedProjectID,
            todayKey: TodoistDateKey.today(at: now(), calendar: calendar)
        )
    }

    func selection(for task: TodoistTaskSnapshot) -> TodoistTaskSelection {
        TodoistTaskSelection(
            taskID: task.id,
            content: task.content,
            projectID: task.projectID,
            projectName: projects.first { $0.id == task.projectID }?.name
        )
    }

    func loadCache() {
        do {
            projects = try repository.fetchProjects()
            tasks = try repository.fetchTasks()
            if let lastSyncedAt = try repository.lastSyncedAt() {
                state = .synced(lastSyncedAt)
            }
        } catch {
            state = .failed(message: cacheErrorMessage)
        }
    }

    func refresh() async {
        guard state != .syncing else {
            return
        }
        loadCache()

        let token: String
        do {
            guard let storedToken = try credentialStore.loadToken() else {
                state = .notConnected
                return
            }
            token = storedToken
        } catch {
            state = .failed(message: safeMessage(for: error))
            return
        }

        state = .syncing
        do {
            let storedSyncToken = try repository.syncToken()
            let response: TodoistSyncResponse
            do {
                response = try await client.syncResources(
                    token: token,
                    syncToken: storedSyncToken ?? "*"
                )
            } catch TodoistClientError.badRequest where storedSyncToken != nil {
                try repository.resetSyncToken()
                response = try await client.syncResources(
                    token: token,
                    syncToken: "*"
                )
            }

            let date = now()
            try repository.apply(response, at: date)
            projects = try repository.fetchProjects()
            tasks = try repository.fetchTasks()
            state = .synced(date)
        } catch {
            loadCache()
            state = .failed(message: safeMessage(for: error))
        }
    }

    private var cacheErrorMessage: String {
        NSLocalizedString(
            "TodoistTasks.cacheError",
            comment: "Todoist cache error"
        )
    }

    private func safeMessage(for error: Error) -> String {
        if let error = error as? TodoistClientError {
            return error.localizedDescription
        }
        if let error = error as? CredentialStoreError {
            return error.localizedDescription
        }
        return NSLocalizedString(
            "TodoistTasks.syncError",
            comment: "Unknown Todoist sync error"
        )
    }
}
