import KeyboardShortcuts
import SwiftUI

@MainActor
final class TBTimer: ObservableObject {
    @AppStorage("stopAfterBreak") var stopAfterBreak = false
    @AppStorage("autoStartBreaks") var autoStartBreaks = true
    @AppStorage("autoStartWork") var autoStartWork = true
    @AppStorage("showTimerInMenuBar") var showTimerInMenuBar = true
    @AppStorage("workIntervalLength") var workIntervalLength = 25
    @AppStorage("shortRestIntervalLength") var shortRestIntervalLength = 5
    @AppStorage("longRestIntervalLength") var longRestIntervalLength = 15
    @AppStorage("workIntervalsInSet") var workIntervalsInSet = 4
    // This preference is "hidden"
    @AppStorage("overrunTimeLimit") var overrunTimeLimit = -60.0

    public let player = TBPlayer()

    @Published private(set) var timeLeftString = ""
    @Published private(set) var status = TimerEngine.Status.idle
    @Published private(set) var phase: TimerEngine.Phase?
    @Published private(set) var timer: DispatchSourceTimer?
    @Published private(set) var pendingNoteSessionID: UUID?
    @Published var pendingNoteText = ""
    @Published var selectedTodoistTask: TodoistTaskSelection?
    @Published private(set) var persistenceErrorMessage: String?

    private var engine = TimerEngine()
    private var sessionTracker = FocusSessionTracker()
    private let sessionRepository: SessionRepository
    private let outboxProcessor: TodoistOutboxProcessing
    private let notificationCenter = TBNotificationCenter()
    private let timerFormatter = DateComponentsFormatter()

    var isActive: Bool {
        status != .idle
    }

    var isPaused: Bool {
        status == .paused
    }

    var isResting: Bool {
        phase?.isRest == true
    }

    var isAwaitingSessionNote: Bool {
        pendingNoteSessionID != nil
    }

    init(
        sessionRepository: SessionRepository = SwiftDataSessionRepository(),
        outboxProcessor: TodoistOutboxProcessing? = nil
    ) {
        self.sessionRepository = sessionRepository
        self.outboxProcessor =
            outboxProcessor ?? TodoistOutboxProcessor.shared
        timerFormatter.unitsStyle = .positional
        timerFormatter.allowedUnits = [.minute, .second]
        timerFormatter.zeroFormattingBehavior = .pad

        KeyboardShortcuts.onKeyUp(for: .startStopTimer, action: startStop)
        notificationCenter.setActionHandler { [weak self] action in
            self?.onNotificationAction(action: action)
        }

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    deinit {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent _: NSAppleEventDescriptor
    ) {
        guard let urlString = event.forKeyword(AEKeyword(keyDirectObject))?.stringValue else {
            print("url handling error: cannot get url")
            return
        }
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              let host = url.host else {
            print("url handling error: cannot parse url")
            return
        }
        guard scheme.caseInsensitiveCompare("tomatobar") == .orderedSame else {
            print("url handling error: unknown scheme \(scheme)")
            return
        }

        switch host.lowercased() {
        case "startstop":
            startStop()
        default:
            print("url handling error: unknown command \(host)")
        }
    }

    func startStop() {
        let now = Date()
        let transition: TimerEngine.Transition?
        if engine.isActive {
            transition = engine.stop(at: now)
        } else {
            transition = engine.start(configuration: configuration, at: now)
        }
        apply(transition, at: now)
    }

    func pauseResume() {
        let now = Date()
        let transition = engine.status == .paused
            ? engine.resume(at: now)
            : engine.pause(at: now)
        apply(transition, at: now)
    }

    func skipRest() {
        let now = Date()
        apply(engine.skipRest(at: now), at: now)
    }

    func updateTimeLeft() {
        publishEngineState(at: Date())
    }

    func savePendingNote() {
        guard let pendingNoteSessionID else {
            return
        }
        do {
            try sessionRepository.updateNote(
                sessionID: pendingNoteSessionID,
                note: pendingNoteText
            )
            clearPendingNote()
            Task {
                await outboxProcessor.process()
            }
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }

    func skipPendingNote() {
        clearPendingNote()
        Task {
            await outboxProcessor.process()
        }
    }

    func dismissPersistenceError() {
        persistenceErrorMessage = nil
    }

    private var configuration: TimerEngine.Configuration {
        TimerEngine.Configuration(
            workDuration: TimeInterval(workIntervalLength * 60),
            shortRestDuration: TimeInterval(shortRestIntervalLength * 60),
            longRestDuration: TimeInterval(longRestIntervalLength * 60),
            workIntervalsPerSet: workIntervalsInSet,
            stopAfterBreak: stopAfterBreak,
            autoStartBreaks: autoStartBreaks,
            autoStartWork: autoStartWork
        )
    }

    private func onTimerTick() {
        let now = Date()
        let timeUntilDeadline = engine.timeUntilDeadline(at: now)
        if timeUntilDeadline <= 0 {
            let isOverrun = timeUntilDeadline < overrunTimeLimit
            let transition = isOverrun
                ? engine.stop(at: now)
                : engine.completeCurrentInterval(at: now)
            apply(transition, at: now, recordWork: !isOverrun)
        } else {
            publishEngineState(at: now)
        }
    }

    private func onNotificationAction(action: TBNotification.Action) {
        guard action == .skipRest else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard self?.isResting == true else {
                return
            }
            self?.skipRest()
        }
    }

    private func apply(
        _ transition: TimerEngine.Transition?,
        at date: Date,
        recordWork: Bool = true
    ) {
        guard let transition else {
            return
        }

        let sessionDraft = sessionTracker.consume(
            transition: transition,
            at: date,
            recordWork: recordWork,
            taskSelection: selectedTodoistTask
        )
        stopTicker()
        if transition.from.phase == .work, transition.from.status == .running {
            player.stopTicking()
        }

        if transition.reason == .intervalCompleted,
           transition.from.phase == .work {
            player.playDing()
        }

        if transition.from.phase == .work,
           let restPhase = transition.to.phase,
           restPhase.isRest {
            sendRestStartedNotification(for: restPhase)
        }

        if transition.reason == .intervalCompleted,
           transition.from.phase?.isRest == true,
           transition.to.phase == .work {
            sendRestFinishedNotification()
        }

        logger.append(event: TBLogEventTransition(transition: transition))
        publishEngineState(at: date)
        applyDestinationPresentation(for: transition)
        if let sessionDraft {
            persistSession(sessionDraft)
        }
    }

    private func applyDestinationPresentation(for transition: TimerEngine.Transition) {
        switch transition.to.phase {
        case nil:
            TBStatusItem.shared.setIcon(name: .idle)

        case .work:
            TBStatusItem.shared.setIcon(name: .work)
            if transition.to.status == .running {
                if transition.reason != .resumed {
                    player.playWindup()
                }
                player.startTicking()
                startTicker()
            }

        case .shortRest:
            TBStatusItem.shared.setIcon(name: .shortRest)
            if transition.to.status == .running {
                startTicker()
            }

        case .longRest:
            TBStatusItem.shared.setIcon(name: .longRest)
            if transition.to.status == .running {
                startTicker()
            }
        }
    }

    private func publishEngineState(at date: Date) {
        status = engine.status
        phase = engine.phase

        if engine.isActive {
            let remainingSeconds = ceil(engine.remaining(at: date))
            timeLeftString = timerFormatter.string(from: remainingSeconds) ?? "00:00"
        } else {
            timeLeftString = ""
        }

        if engine.isActive, showTimerInMenuBar {
            TBStatusItem.shared.setTitle(title: timeLeftString)
        } else {
            TBStatusItem.shared.setTitle(title: nil)
        }
    }

    private func startTicker() {
        guard timer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.onTimerTick()
        }
        self.timer = timer
        timer.resume()
    }

    private func stopTicker() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func sendRestStartedNotification(for phase: TimerEngine.Phase) {
        let isLongRest = phase == .longRest
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title"),
            body: NSLocalizedString(
                isLongRest
                    ? "TBTimer.onRestStart.long.body"
                    : "TBTimer.onRestStart.short.body",
                comment: isLongRest ? "Long break body" : "Short break body"
            ),
            category: .restStarted
        )
    }

    private func sendRestFinishedNotification() {
        notificationCenter.send(
            title: NSLocalizedString(
                "TBTimer.onRestFinish.title",
                comment: "Break is over title"
            ),
            body: NSLocalizedString(
                "TBTimer.onRestFinish.body",
                comment: "Break is over body"
            ),
            category: .restFinished
        )
    }

    private func persistSession(_ draft: FocusSessionDraft) {
        do {
            pendingNoteSessionID = try sessionRepository.save(draft)
            pendingNoteText = ""
            persistenceErrorMessage = nil
            DispatchQueue.main.async {
                TBStatusItem.shared.resizePopoverToFit()
                TBStatusItem.shared.showPopover(nil)
            }
        } catch {
            persistenceErrorMessage = error.localizedDescription
            DispatchQueue.main.async {
                TBStatusItem.shared.resizePopoverToFit()
                TBStatusItem.shared.showPopover(nil)
            }
        }
    }

    private func clearPendingNote() {
        pendingNoteSessionID = nil
        pendingNoteText = ""
        DispatchQueue.main.async {
            TBStatusItem.shared.resizePopoverToFit()
        }
    }
}
