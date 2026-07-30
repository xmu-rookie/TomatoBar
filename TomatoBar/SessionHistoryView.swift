import SwiftData
import SwiftUI

struct SessionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FocusSession.startedAt, order: .reverse)
    private var sessions: [FocusSession]
    @Query(sort: \TodoistTaskCache.content)
    private var cachedTasks: [TodoistTaskCache]
    @Query(sort: \TodoistProjectCache.name)
    private var cachedProjects: [TodoistProjectCache]
    @State private var editingSession: FocusSession?

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    NSLocalizedString(
                        "SessionHistory.empty.title",
                        comment: "Empty session history title"
                    ),
                    systemImage: "timer"
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        SessionHistoryRow(session: session) {
                            editingSession = session
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .navigationTitle(
            NSLocalizedString(
                "SessionHistory.title",
                comment: "Session history window title"
            )
        )
        .sheet(item: $editingSession) { session in
            SessionEditorView(
                session: session,
                tasks: cachedTasks.map(\.snapshot),
                projects: cachedProjects.map(\.snapshot)
            )
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            try? SwiftDataSessionRepository(context: modelContext)
                .delete(sessionID: sessions[index].id)
        }
        TodoistOutboxProcessor.shared.refreshState()
        Task {
            await TodoistOutboxProcessor.shared.process()
        }
    }
}

private struct SessionHistoryRow: View {
    let session: FocusSession
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(
                    session.startedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                Spacer()
                Text(summary)
                    .foregroundStyle(.secondary)
                if session.todoistTaskID != nil {
                    Image(systemName: syncImage)
                        .foregroundStyle(syncColor)
                        .help(syncHelp)
                }
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString(
                    "SessionHistory.edit.help",
                    comment: "Edit focus session help"
                ))
            }
            if let taskContent = session.taskContent {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                    Text(taskContent)
                        .lineLimit(1)
                    if let projectName = session.projectName {
                        Text("· \(projectName)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !session.note.isEmpty {
                Text(session.note)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        let duration = Duration.seconds(session.activeDuration)
            .formatted(.time(pattern: .hourMinute))
        let tomatoes = session.tomatoCount.formatted(
            .number.precision(.fractionLength(0 ... 1))
        )
        return "\(duration) · 🍅 \(tomatoes)"
    }

    private var syncImage: String {
        switch session.syncState {
        case .localOnly:
            return "icloud.slash"
        case .pending:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.icloud"
        case .failed:
            return "exclamationmark.icloud"
        }
    }

    private var syncColor: Color {
        switch session.syncState {
        case .failed:
            return .red
        case .pending:
            return .orange
        default:
            return .secondary
        }
    }

    private var syncHelp: String {
        NSLocalizedString(
            "SessionHistory.sync.\(session.syncState.rawValue)",
            comment: "Session Todoist sync state"
        )
    }
}

private struct SessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let session: FocusSession
    let tasks: [TodoistTaskSnapshot]
    let projects: [TodoistProjectSnapshot]

    @State private var note: String
    @State private var selectedTaskID: String?
    @State private var errorMessage: String?

    init(
        session: FocusSession,
        tasks: [TodoistTaskSnapshot],
        projects: [TodoistProjectSnapshot]
    ) {
        self.session = session
        self.tasks = tasks
        self.projects = projects
        _note = State(initialValue: session.note)
        _selectedTaskID = State(initialValue: session.todoistTaskID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString(
                "SessionEditor.title",
                comment: "Edit focus session title"
            ))
            .font(.title2)

            Picker(
                NSLocalizedString(
                    "SessionEditor.task.label",
                    comment: "Edit session task label"
                ),
                selection: $selectedTaskID
            ) {
                Text(NSLocalizedString(
                    "TodoistTasks.noTask.label",
                    comment: "No Todoist task label"
                ))
                .tag(String?.none)
                if let oldTaskID = session.todoistTaskID,
                   !tasks.contains(where: { $0.id == oldTaskID }) {
                    Text(session.taskContent ?? oldTaskID)
                        .tag(Optional(oldTaskID))
                }
                ForEach(tasks) { task in
                    Text(task.content).tag(Optional(task.id))
                }
            }

            TextField(
                NSLocalizedString(
                    "SessionNote.placeholder",
                    comment: "Optional session note"
                ),
                text: $note,
                axis: .vertical
            )
            .lineLimit(3 ... 6)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button(NSLocalizedString(
                    "SessionEditor.cancel.label",
                    comment: "Cancel session edit"
                )) {
                    dismiss()
                }
                Button(NSLocalizedString(
                    "SessionEditor.save.label",
                    comment: "Save session edit"
                )) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func save() {
        do {
            try SwiftDataSessionRepository(context: modelContext).update(
                sessionID: session.id,
                note: note,
                taskSelection: selection
            )
            TodoistOutboxProcessor.shared.refreshState()
            Task {
                await TodoistOutboxProcessor.shared.process()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var selection: TodoistTaskSelection? {
        guard let selectedTaskID else {
            return nil
        }
        if let task = tasks.first(where: { $0.id == selectedTaskID }) {
            return TodoistTaskSelection(
                taskID: task.id,
                content: task.content,
                projectID: task.projectID,
                projectName: projects.first {
                    $0.id == task.projectID
                }?.name
            )
        }
        guard selectedTaskID == session.todoistTaskID,
              let content = session.taskContent,
              let projectID = session.todoistProjectID else {
            return nil
        }
        return TodoistTaskSelection(
            taskID: selectedTaskID,
            content: content,
            projectID: projectID,
            projectName: session.projectName
        )
    }
}

final class SessionHistoryWindowController {
    static let shared = SessionHistoryWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let rootView = StatisticsRootView()
                .modelContainer(AppPersistence.shared)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = NSLocalizedString(
                "Statistics.title",
                comment: "Statistics window title"
            )
            window.contentViewController = NSHostingController(rootView: rootView)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
