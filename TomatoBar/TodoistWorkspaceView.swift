import SwiftUI

struct TodoistWorkspaceView: View {
    @ObservedObject var connectionViewModel: TodoistConnectionViewModel
    @ObservedObject var taskViewModel: TodoistTaskListViewModel
    @Binding var selection: TodoistTaskSelection?
    let isSelectionDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TodoistSettingsView(viewModel: connectionViewModel)

            Divider()

            HStack {
                Text(NSLocalizedString(
                    "TodoistTasks.title",
                    comment: "Todoist tasks title"
                ))
                .font(.headline)
                Spacer()
                Button {
                    Task {
                        await taskViewModel.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(taskViewModel.state == .syncing)
                .help(NSLocalizedString(
                    "TodoistTasks.refresh.help",
                    comment: "Refresh Todoist tasks help"
                ))
            }

            TextField(
                NSLocalizedString(
                    "TodoistTasks.search.placeholder",
                    comment: "Search Todoist tasks placeholder"
                ),
                text: $taskViewModel.searchText
            )
            .textFieldStyle(.roundedBorder)

            Picker(
                NSLocalizedString(
                    "TodoistTasks.project.label",
                    comment: "Todoist project filter label"
                ),
                selection: $taskViewModel.selectedProjectID
            ) {
                Text(NSLocalizedString(
                    "TodoistTasks.allProjects.label",
                    comment: "All Todoist projects label"
                ))
                .tag(String?.none)
                ForEach(taskViewModel.projects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    taskButton(
                        title: NSLocalizedString(
                            "TodoistTasks.noTask.label",
                            comment: "No Todoist task label"
                        ),
                        subtitle: nil,
                        isSelected: selection == nil
                    ) {
                        selection = nil
                    }

                    if taskViewModel.visibleTasks.isEmpty {
                        Text(emptyMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(taskViewModel.visibleTasks) { task in
                            taskButton(
                                title: task.content,
                                subtitle: subtitle(for: task),
                                isSelected: selection?.taskID == task.id
                            ) {
                                selection = taskViewModel.selection(for: task)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 70, maxHeight: 170)
            .disabled(isSelectionDisabled)

            syncStatus
        }
        .onChange(of: connectionViewModel.state) {
            guard case .connected = connectionViewModel.state else {
                return
            }
            Task {
                await taskViewModel.refresh()
            }
        }
    }

    private var emptyMessage: String {
        if taskViewModel.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NSLocalizedString(
                "TodoistTasks.todayEmpty.message",
                comment: "No today or overdue Todoist tasks message"
            )
        }
        return NSLocalizedString(
            "TodoistTasks.searchEmpty.message",
            comment: "No matching Todoist tasks message"
        )
    }

    private func subtitle(for task: TodoistTaskSnapshot) -> String? {
        let projectName = taskViewModel.projects.first {
            $0.id == task.projectID
        }?.name
        return [projectName, task.dueString]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func taskButton(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var syncStatus: some View {
        switch taskViewModel.state {
        case .idle:
            EmptyView()
        case .syncing:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(NSLocalizedString(
                    "TodoistTasks.syncing.status",
                    comment: "Todoist tasks syncing status"
                ))
            }
            .font(.caption)
        case let .synced(date):
            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString(
                        "TodoistTasks.synced.status",
                        comment: "Todoist tasks last synced status"
                    ),
                    date.formatted(date: .omitted, time: .shortened)
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .notConnected:
            Text(NSLocalizedString(
                "TodoistTasks.notConnected.status",
                comment: "Todoist tasks not connected status"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
