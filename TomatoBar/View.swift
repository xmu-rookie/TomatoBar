import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

extension KeyboardShortcuts.Name {
    static let startStopTimer = Self("startStopTimer")
}

private struct IntervalsView: View {
    @EnvironmentObject var timer: TBTimer
    private var minStr = NSLocalizedString("IntervalsView.min", comment: "min")

    var body: some View {
        VStack {
            Stepper(value: $timer.workIntervalLength, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.workIntervalLength.label",
                                           comment: "Work interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.workIntervalLength))
                }
            }
            Stepper(value: $timer.shortRestIntervalLength, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.shortRestIntervalLength.label",
                                           comment: "Short rest interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.shortRestIntervalLength))
                }
            }
            Stepper(value: $timer.longRestIntervalLength, in: 1 ... 60) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.longRestIntervalLength.label",
                                           comment: "Long rest interval label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String.localizedStringWithFormat(minStr, timer.longRestIntervalLength))
                }
            }
            .help(NSLocalizedString("IntervalsView.longRestIntervalLength.help",
                                    comment: "Long rest interval hint"))
            Stepper(value: $timer.workIntervalsInSet, in: 1 ... 10) {
                HStack {
                    Text(NSLocalizedString("IntervalsView.workIntervalsInSet.label",
                                           comment: "Work intervals in a set label"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(timer.workIntervalsInSet)")
                }
            }
            .help(NSLocalizedString("IntervalsView.workIntervalsInSet.help",
                                    comment: "Work intervals in set hint"))
            Toggle(isOn: $timer.autoStartBreaks) {
                Text(NSLocalizedString("SettingsView.autoStartBreaks.label",
                                       comment: "Auto-start breaks label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Toggle(isOn: $timer.autoStartWork) {
                Text(NSLocalizedString("SettingsView.autoStartWork.label",
                                       comment: "Auto-start work label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .disabled(timer.stopAfterBreak)
            Spacer().frame(minHeight: 0)
        }
        .padding(4)
    }
}

private struct SettingsView: View {
    @EnvironmentObject var timer: TBTimer
    @ObservedObject private var launchAtLogin = LaunchAtLogin.observable

    var body: some View {
        VStack {
            KeyboardShortcuts.Recorder(for: .startStopTimer) {
                Text(NSLocalizedString("SettingsView.shortcut.label",
                                       comment: "Shortcut label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle(isOn: $timer.stopAfterBreak) {
                Text(NSLocalizedString("SettingsView.stopAfterBreak.label",
                                       comment: "Stop after break label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Toggle(isOn: $timer.showTimerInMenuBar) {
                Text(NSLocalizedString("SettingsView.showTimerInMenuBar.label",
                                       comment: "Show timer in menu bar label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
                .onChange(of: timer.showTimerInMenuBar) {
                    timer.updateTimeLeft()
                }
            Toggle(isOn: $launchAtLogin.isEnabled) {
                Text(NSLocalizedString("SettingsView.launchAtLogin.label",
                                       comment: "Launch at login label"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
            Spacer().frame(minHeight: 0)
        }
        .padding(4)
    }
}

private struct VolumeSlider: View {
    @Binding var volume: Double

    var body: some View {
        Slider(value: $volume, in: 0...2) {
            Text(String(format: "%.1f", volume))
        }.gesture(TapGesture(count: 2).onEnded({
            volume = 1.0
        }))
    }
}

private struct SoundsView: View {
    @EnvironmentObject var player: TBPlayer

    private var columns = [
        GridItem(.flexible()),
        GridItem(.fixed(110))
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("SoundsView.isWindupEnabled.label",
                                   comment: "Windup label"))
            VolumeSlider(volume: $player.windupVolume)
            Text(NSLocalizedString("SoundsView.isDingEnabled.label",
                                   comment: "Ding label"))
            VolumeSlider(volume: $player.dingVolume)
            Text(NSLocalizedString("SoundsView.isTickingEnabled.label",
                                   comment: "Ticking label"))
            VolumeSlider(volume: $player.tickingVolume)
        }.padding(4)
        Spacer().frame(minHeight: 0)
    }
}

private enum ChildView {
    case intervals, settings, sounds, todoist
}

struct TBPopoverView: View {
    @StateObject private var timer = TBTimer()
    @StateObject private var todoistConnection = TodoistConnectionViewModel()
    @StateObject private var todoistTasks = TodoistTaskListViewModel()
    @State private var buttonHovered = false
    @State private var activeChildView = ChildView.intervals

    private var startLabel = NSLocalizedString("TBPopoverView.start.label", comment: "Start label")
    private var stopLabel = NSLocalizedString("TBPopoverView.stop.label", comment: "Stop label")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if timer.isAwaitingSessionNote {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString(
                            "SessionNote.prompt",
                            comment: "Session note prompt"
                        ))
                        .font(.headline)
                        TextField(
                            NSLocalizedString(
                                "SessionNote.placeholder",
                                comment: "Session note placeholder"
                            ),
                            text: $timer.pendingNoteText
                        )
                        .onSubmit {
                            timer.savePendingNote()
                        }
                        HStack {
                            Button {
                                timer.savePendingNote()
                            } label: {
                                Text(NSLocalizedString(
                                    "SessionNote.save.label",
                                    comment: "Save session note label"
                                ))
                                .frame(maxWidth: .infinity)
                            }
                            Button {
                                timer.skipPendingNote()
                            } label: {
                                Text(NSLocalizedString(
                                    "SessionNote.skip.label",
                                    comment: "Skip session note label"
                                ))
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }

            if let persistenceErrorMessage = timer.persistenceErrorMessage {
                HStack {
                    Text(persistenceErrorMessage)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        timer.dismissPersistenceError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                activeChildView = .todoist
            } label: {
                HStack {
                    Image(systemName: "checklist")
                    Text(
                        timer.selectedTodoistTask?.content
                            ?? NSLocalizedString(
                                "TodoistTasks.noTask.label",
                                comment: "No Todoist task label"
                            )
                    )
                    .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(timer.isActive)

            Button {
                timer.startStop()
                if !timer.isAwaitingSessionNote {
                    TBStatusItem.shared.closePopover(nil)
                }
            } label: {
                Text(timer.isActive ?
                     (buttonHovered ? stopLabel : timer.timeLeftString) :
                        startLabel)
                    /*
                      When appearance is set to "Dark" and accent color is set to "Graphite"
                      "defaultAction" button label's color is set to the same color as the
                      button, making the button look blank. #24
                     */
                    .foregroundColor(Color.white)
                    .font(.system(.body).monospacedDigit())
                    .frame(maxWidth: .infinity)
            }
            .onHover { over in
                buttonHovered = over
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            HStack {
                Button {
                    timer.pauseResume()
                } label: {
                    Text(NSLocalizedString(
                        timer.isPaused
                            ? "TBPopoverView.resume.label"
                            : "TBPopoverView.pause.label",
                        comment: timer.isPaused ? "Resume label" : "Pause label"
                    ))
                    .frame(maxWidth: .infinity)
                }
                .disabled(!timer.isActive)

                Button {
                    timer.skipRest()
                } label: {
                    Text(NSLocalizedString(
                        "TBPopoverView.skipRest.label",
                        comment: "Skip rest label"
                    ))
                    .frame(maxWidth: .infinity)
                }
                .disabled(!timer.isResting)
            }

            Picker("", selection: $activeChildView) {
                Text(NSLocalizedString("TBPopoverView.intervals.label",
                                       comment: "Intervals label")).tag(ChildView.intervals)
                Text(NSLocalizedString("TBPopoverView.settings.label",
                                       comment: "Settings label")).tag(ChildView.settings)
                Text(NSLocalizedString("TBPopoverView.sounds.label",
                                       comment: "Sounds label")).tag(ChildView.sounds)
                Text(NSLocalizedString("TBPopoverView.todoist.label",
                                       comment: "Todoist label")).tag(ChildView.todoist)
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .pickerStyle(.segmented)

            GroupBox {
                switch activeChildView {
                case .intervals:
                    IntervalsView().environmentObject(timer)
                case .settings:
                    SettingsView().environmentObject(timer)
                case .sounds:
                    SoundsView().environmentObject(timer.player)
                case .todoist:
                    TodoistWorkspaceView(
                        connectionViewModel: todoistConnection,
                        taskViewModel: todoistTasks,
                        selection: $timer.selectedTodoistTask,
                        isSelectionDisabled: timer.isActive
                    )
                }
            }

            Group {
                Button {
                    SessionHistoryWindowController.shared.show()
                } label: {
                    Text(NSLocalizedString(
                        "TBPopoverView.history.label",
                        comment: "History label"
                    ))
                    Spacer()
                }
                .buttonStyle(.plain)
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel()
                } label: {
                    Text(NSLocalizedString("TBPopoverView.about.label",
                                           comment: "About label"))
                    Spacer()
                    Text("⌘ A").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("a")
                Button {
                    NSApplication.shared.terminate(self)
                } label: {
                    Text(NSLocalizedString("TBPopoverView.quit.label",
                                           comment: "Quit label"))
                    Spacer()
                    Text("⌘ Q").foregroundColor(Color.gray)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
        }
        #if DEBUG
            /*
             After several hours of Googling and trying various StackOverflow
             recipes I still haven't figured a reliable way to auto resize
             popover to fit all it's contents (pull requests are welcome!).
             The following code block is used to determine the optimal
             geometry of the popover.
             */
            .overlay(
                GeometryReader { proxy in
                    debugSize(proxy: proxy)
                }
            )
        #endif
            /* Use values from GeometryReader */
//            .frame(width: 240, height: 276)
            .padding(12)
            .onChange(of: activeChildView) {
                TBStatusItem.shared.resizePopoverToFit()
            }
            .task {
                await todoistConnection.testSavedConnection()
                if !timer.isActive {
                    await todoistTasks.refresh()
                }
                TBStatusItem.shared.resizePopoverToFit()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .todoistPopoverWillOpen)
            ) { _ in
                guard !timer.isActive else {
                    return
                }
                Task {
                    await todoistTasks.refresh()
                }
            }
    }
}

#if DEBUG
    func debugSize(proxy: GeometryProxy) -> some View {
        print("Optimal popover size:", proxy.size)
        return Color.clear
    }
#endif
