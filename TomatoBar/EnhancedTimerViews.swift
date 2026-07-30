import AppKit
import SwiftUI

struct EnhancedPresentationState: Equatable {
    let showsFloatingTimer: Bool
    let showsFullscreenBreak: Bool
}

enum TimerPresentationPolicy {
    static func resolve(
        floatingEnabled: Bool,
        fullscreenBreakEnabled: Bool,
        status: TimerEngine.Status,
        phase: TimerEngine.Phase?
    ) -> EnhancedPresentationState {
        let isActive = status != .idle
        return EnhancedPresentationState(
            showsFloatingTimer: floatingEnabled && isActive,
            showsFullscreenBreak:
                fullscreenBreakEnabled && isActive && phase?.isRest == true
        )
    }
}

@MainActor
final class FloatingTimerWindowController {
    static let shared = FloatingTimerWindowController()

    private var panel: NSPanel?

    private init() {}

    func update(
        timer: TBTimer,
        presentation: EnhancedPresentationState
    ) {
        guard presentation.showsFloatingTimer else {
            panel?.orderOut(nil)
            return
        }

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 92),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
            ]
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(
                rootView: FloatingTimerView(timer: timer)
            )
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                panel.setFrameOrigin(
                    NSPoint(
                        x: frame.maxX - panel.frame.width - 24,
                        y: frame.maxY - panel.frame.height - 24
                    )
                )
            }
            self.panel = panel
        }
        panel?.orderFrontRegardless()
    }
}

private struct FloatingTimerView: View {
    @ObservedObject var timer: TBTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(timer.timeLeftString)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                Spacer()
                Text(phaseLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let task = timer.selectedTodoistTask {
                Text(task.content)
                    .font(.caption)
                    .lineLimit(1)
            }
            HStack {
                Button {
                    timer.pauseResume()
                } label: {
                    Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                }
                .help(
                    NSLocalizedString(
                        timer.isPaused
                            ? "TBPopoverView.resume.label"
                            : "TBPopoverView.pause.label",
                        comment: "Floating timer pause or resume"
                    )
                )
                Button {
                    timer.startStop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .help(NSLocalizedString(
                    "TBPopoverView.stop.label",
                    comment: "Floating timer stop"
                ))
                Spacer()
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .foregroundStyle(.tertiary)
                    .help(NSLocalizedString(
                        "EnhancedTimer.drag.help",
                        comment: "Drag floating timer help"
                    ))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var phaseLabel: String {
        switch timer.phase {
        case .work:
            return NSLocalizedString(
                "EnhancedTimer.work.label",
                comment: "Floating work phase label"
            )
        case .shortRest, .longRest:
            return NSLocalizedString(
                "EnhancedTimer.break.label",
                comment: "Floating break phase label"
            )
        case nil:
            return ""
        }
    }
}

@MainActor
final class FullscreenBreakWindowController {
    static let shared = FullscreenBreakWindowController()

    private var windows: [NSWindow] = []

    private init() {}

    func update(
        timer: TBTimer,
        presentation: EnhancedPresentationState
    ) {
        guard presentation.showsFullscreenBreak else {
            hide()
            return
        }

        let screens = NSScreen.screens
        if windows.count != screens.count {
            hide()
            windows = screens.map { screen in
                let window = NSWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
                window.level = .floating
                window.isOpaque = true
                window.backgroundColor = .windowBackgroundColor
                window.collectionBehavior = [
                    .canJoinAllSpaces,
                    .fullScreenAuxiliary,
                ]
                window.contentView = NSHostingView(
                    rootView: FullscreenBreakView(timer: timer)
                )
                return window
            }
        }
        for (window, screen) in zip(windows, screens) {
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
        }
    }

    private func hide() {
        windows.forEach { $0.orderOut(nil) }
    }
}

private struct FullscreenBreakView: View {
    @ObservedObject var timer: TBTimer

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)
            Text(NSLocalizedString(
                "EnhancedTimer.break.title",
                comment: "Fullscreen break title"
            ))
            .font(.largeTitle.weight(.semibold))
            Text(timer.timeLeftString)
                .font(.system(size: 64, design: .monospaced).weight(.medium))
            Button {
                timer.skipRest()
            } label: {
                Text(NSLocalizedString(
                    "TBPopoverView.skipRest.label",
                    comment: "Skip fullscreen break"
                ))
                .padding(.horizontal, 24)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.16),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
