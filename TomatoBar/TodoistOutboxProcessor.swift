import Combine
import Foundation

extension Notification.Name {
    static let todoistWriteDidSucceed =
        Notification.Name("todoistWriteDidSucceed")
}

@MainActor
protocol TodoistOutboxProcessing {
    func process() async
}

@MainActor
final class TodoistOutboxProcessor:
    ObservableObject,
    TodoistOutboxProcessing {
    enum State: Equatable {
        case idle
        case syncing
        case pending(TodoistOutboxCounts)
        case synced
        case notConnected(TodoistOutboxCounts)
        case failed(TodoistOutboxCounts)
    }

    static let shared = TodoistOutboxProcessor()

    @Published private(set) var state = State.idle

    private let credentialStore: CredentialStore
    private let client: TodoistCommandExecuting
    private let repository: TodoistOutboxRepository
    private let now: () -> Date

    init(
        credentialStore: CredentialStore = KeychainCredentialStore(),
        client: TodoistCommandExecuting = TodoistClient(),
        repository: TodoistOutboxRepository =
            SwiftDataTodoistOutboxRepository(),
        now: @escaping () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        self.client = client
        self.repository = repository
        self.now = now
        refreshState()
    }

    func process() async {
        guard state != .syncing else {
            return
        }

        let token: String
        do {
            let counts = try repository.counts()
            guard counts.pending > 0 else {
                state = counts.failed > 0 ? .failed(counts) : .synced
                return
            }
            guard let storedToken = try credentialStore.loadToken() else {
                state = .notConnected(counts)
                return
            }
            token = storedToken
        } catch {
            refreshState()
            return
        }

        state = .syncing
        var didWrite = false
        var taskCacheChanged = false

        do {
            while true {
                let commands = try repository.fetchPending(limit: 100)
                guard !commands.isEmpty else {
                    break
                }
                do {
                    let response = try await client.execute(
                        token: token,
                        commands: commands.map(\.request)
                    )
                    let result = try repository.apply(
                        response: response,
                        commands: commands,
                        at: now()
                    )
                    didWrite = didWrite || result.succeeded > 0
                    taskCacheChanged =
                        taskCacheChanged || result.taskCacheChanged
                    if result.succeeded + result.failed == 0 {
                        break
                    }
                } catch {
                    try repository.recordTransportFailure(
                        commandIDs: commands.map(\.id),
                        at: now()
                    )
                    break
                }
            }
        } catch {
            // The durable commands remain in SwiftData and will be retried later.
        }

        refreshState()
        if didWrite, state == .idle {
            state = .synced
        }
        if didWrite {
            NotificationCenter.default.post(
                name: .todoistWriteDidSucceed,
                object: nil,
                userInfo: ["taskCacheChanged": taskCacheChanged]
            )
        }
    }

    func retryFailed() async {
        do {
            try repository.retryFailed(at: now())
        } catch {
            refreshState()
            return
        }
        await process()
    }

    func refreshState() {
        do {
            let counts = try repository.counts()
            if counts.failed > 0 {
                state = .failed(counts)
            } else if counts.pending > 0 {
                state = .pending(counts)
            } else {
                state = .idle
            }
        } catch {
            state = .failed(TodoistOutboxCounts(pending: 0, failed: 1))
        }
    }
}

@MainActor
final class TodoistWriteViewModel: ObservableObject {
    enum ActionState: Equatable {
        case idle
        case queued
        case error
    }

    @Published private(set) var actionState = ActionState.idle
    @Published private(set) var undoSelection: TodoistTaskSelection?
    let processor: TodoistOutboxProcessor

    private let repository: TodoistOutboxRepository
    private let now: () -> Date

    init(
        repository: TodoistOutboxRepository =
            SwiftDataTodoistOutboxRepository(),
        processor: TodoistOutboxProcessor? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.processor = processor ?? .shared
        self.now = now
    }

    func complete(_ selection: TodoistTaskSelection) {
        do {
            try repository.enqueueTaskClose(
                selection: selection,
                at: now()
            )
            undoSelection = selection
            actionState = .queued
            processor.refreshState()
            Task {
                await processor.process()
            }
        } catch {
            actionState = .error
        }
    }

    func undo() {
        guard let selection = undoSelection else {
            return
        }
        do {
            try repository.enqueueTaskUncomplete(
                selection: selection,
                at: now()
            )
            undoSelection = nil
            actionState = .queued
            processor.refreshState()
            Task {
                await processor.process()
            }
        } catch {
            actionState = .error
        }
    }
}
