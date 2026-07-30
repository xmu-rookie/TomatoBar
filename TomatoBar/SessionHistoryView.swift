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
            modelContext.delete(sessions[index])
        }
        try? modelContext.save()
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
