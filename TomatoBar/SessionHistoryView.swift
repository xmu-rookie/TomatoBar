import SwiftData
import SwiftUI

struct SessionHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FocusSession.startedAt, order: .reverse)
    private var sessions: [FocusSession]

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
                        SessionHistoryRow(session: session)
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

final class SessionHistoryWindowController {
    static let shared = SessionHistoryWindowController()

    private var window: NSWindow?

    private init() {}

    func show() {
        if window == nil {
            let rootView = SessionHistoryView()
                .modelContainer(AppPersistence.shared)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = NSLocalizedString(
                "SessionHistory.title",
                comment: "Session history window title"
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
