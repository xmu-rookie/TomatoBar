import Foundation

struct TimerEngine {
    enum Phase: String, Equatable {
        case work
        case shortRest
        case longRest

        var isRest: Bool {
            self != .work
        }
    }

    enum Status: String, Equatable {
        case idle
        case running
        case paused
    }

    enum Reason: String, Equatable {
        case started
        case paused
        case resumed
        case stopped
        case intervalCompleted
        case restSkipped
    }

    struct Configuration: Equatable {
        var workDuration: TimeInterval
        var shortRestDuration: TimeInterval
        var longRestDuration: TimeInterval
        var workIntervalsPerSet: Int
        var stopAfterBreak: Bool
        var autoStartBreaks: Bool
        var autoStartWork: Bool

        init(
            workDuration: TimeInterval = 25 * 60,
            shortRestDuration: TimeInterval = 5 * 60,
            longRestDuration: TimeInterval = 15 * 60,
            workIntervalsPerSet: Int = 4,
            stopAfterBreak: Bool = false,
            autoStartBreaks: Bool = true,
            autoStartWork: Bool = true
        ) {
            self.workDuration = max(1, workDuration)
            self.shortRestDuration = max(1, shortRestDuration)
            self.longRestDuration = max(1, longRestDuration)
            self.workIntervalsPerSet = max(1, workIntervalsPerSet)
            self.stopAfterBreak = stopAfterBreak
            self.autoStartBreaks = autoStartBreaks
            self.autoStartWork = autoStartWork
        }

        func duration(for phase: Phase) -> TimeInterval {
            switch phase {
            case .work:
                workDuration
            case .shortRest:
                shortRestDuration
            case .longRest:
                longRestDuration
            }
        }
    }

    struct Snapshot: Equatable {
        let status: Status
        let phase: Phase?
        let remaining: TimeInterval
        let completedWorkIntervals: Int
    }

    struct WorkResult: Equatable {
        let activeDuration: TimeInterval
        let tomatoCount: Double
        let completedInterval: Bool
    }

    struct Transition: Equatable {
        let from: Snapshot
        let to: Snapshot
        let reason: Reason
        let workResult: WorkResult?
    }

    private(set) var configuration = Configuration()
    private(set) var status = Status.idle
    private(set) var phase: Phase?
    private(set) var completedWorkIntervals = 0

    private var deadline: Date?
    private var remainingWhenPaused: TimeInterval = 0
    private var accumulatedWorkDuration: TimeInterval = 0
    private var workResumedAt: Date?

    var isActive: Bool {
        status != .idle
    }

    @discardableResult
    mutating func start(
        configuration: Configuration,
        at date: Date = Date()
    ) -> Transition? {
        guard status == .idle else {
            return nil
        }

        let from = snapshot(at: date)
        self.configuration = configuration
        completedWorkIntervals = 0
        move(to: .work, status: .running, at: date)
        return makeTransition(from: from, reason: .started, at: date)
    }

    @discardableResult
    mutating func pause(at date: Date = Date()) -> Transition? {
        guard status == .running else {
            return nil
        }

        let from = snapshot(at: date)
        if phase == .work {
            accumulatedWorkDuration = activeWorkDuration(at: date)
        }
        remainingWhenPaused = remaining(at: date)
        deadline = nil
        workResumedAt = nil
        status = .paused
        return makeTransition(from: from, reason: .paused, at: date)
    }

    @discardableResult
    mutating func resume(at date: Date = Date()) -> Transition? {
        guard status == .paused, let phase else {
            return nil
        }

        let from = snapshot(at: date)
        status = .running
        deadline = date.addingTimeInterval(remainingWhenPaused)
        if phase == .work {
            workResumedAt = date
        }
        return makeTransition(from: from, reason: .resumed, at: date)
    }

    @discardableResult
    mutating func stop(at date: Date = Date()) -> Transition? {
        guard status != .idle else {
            return nil
        }

        let from = snapshot(at: date)
        let workResult = partialWorkResult(at: date)
        reset()
        return makeTransition(
            from: from,
            reason: .stopped,
            at: date,
            workResult: workResult
        )
    }

    @discardableResult
    mutating func completeCurrentInterval(at date: Date = Date()) -> Transition? {
        guard status == .running, let phase, remaining(at: date) <= 0 else {
            return nil
        }

        let from = snapshot(at: date)
        switch phase {
        case .work:
            let workResult = WorkResult(
                activeDuration: configuration.workDuration,
                tomatoCount: 1,
                completedInterval: true
            )
            completedWorkIntervals += 1
            let isLongRest = completedWorkIntervals >= configuration.workIntervalsPerSet
            if isLongRest {
                completedWorkIntervals = 0
            }
            move(
                to: isLongRest ? .longRest : .shortRest,
                status: configuration.autoStartBreaks ? .running : .paused,
                at: date
            )
            return makeTransition(
                from: from,
                reason: .intervalCompleted,
                at: date,
                workResult: workResult
            )

        case .shortRest, .longRest:
            if configuration.stopAfterBreak {
                reset()
            } else {
                move(
                    to: .work,
                    status: configuration.autoStartWork ? .running : .paused,
                    at: date
                )
            }
            return makeTransition(from: from, reason: .intervalCompleted, at: date)
        }
    }

    @discardableResult
    mutating func skipRest(at date: Date = Date()) -> Transition? {
        guard status != .idle, phase?.isRest == true else {
            return nil
        }

        let from = snapshot(at: date)
        move(to: .work, status: .running, at: date)
        return makeTransition(from: from, reason: .restSkipped, at: date)
    }

    func remaining(at date: Date = Date()) -> TimeInterval {
        max(0, timeUntilDeadline(at: date))
    }

    func timeUntilDeadline(at date: Date = Date()) -> TimeInterval {
        switch status {
        case .idle:
            0
        case .paused:
            remainingWhenPaused
        case .running:
            deadline?.timeIntervalSince(date) ?? 0
        }
    }

    func snapshot(at date: Date = Date()) -> Snapshot {
        Snapshot(
            status: status,
            phase: phase,
            remaining: remaining(at: date),
            completedWorkIntervals: completedWorkIntervals
        )
    }

    func activeWorkDuration(at date: Date = Date()) -> TimeInterval {
        guard phase == .work else {
            return 0
        }

        var duration = accumulatedWorkDuration
        if status == .running, let workResumedAt {
            duration += max(0, date.timeIntervalSince(workResumedAt))
        }
        return min(configuration.workDuration, duration)
    }

    static func tomatoCount(
        activeDuration: TimeInterval,
        workDuration: TimeInterval,
        completedInterval: Bool = false
    ) -> Double {
        let normalizedWorkDuration = max(1, workDuration)
        let normalizedActiveDuration = max(0, activeDuration)
        if completedInterval || normalizedActiveDuration >= normalizedWorkDuration {
            return 1
        }

        let fifth = normalizedWorkDuration / 5
        let completedFifths = min(4, Int(normalizedActiveDuration / fifth))
        return Double(completedFifths) / 5
    }

    private mutating func move(to phase: Phase, status: Status, at date: Date) {
        self.phase = phase
        self.status = status
        remainingWhenPaused = configuration.duration(for: phase)
        deadline = status == .running
            ? date.addingTimeInterval(remainingWhenPaused)
            : nil
        accumulatedWorkDuration = 0
        workResumedAt = phase == .work && status == .running ? date : nil
    }

    private mutating func reset() {
        status = .idle
        phase = nil
        completedWorkIntervals = 0
        deadline = nil
        remainingWhenPaused = 0
        accumulatedWorkDuration = 0
        workResumedAt = nil
    }

    private func partialWorkResult(at date: Date) -> WorkResult? {
        guard phase == .work else {
            return nil
        }

        let duration = activeWorkDuration(at: date)
        return WorkResult(
            activeDuration: duration,
            tomatoCount: Self.tomatoCount(
                activeDuration: duration,
                workDuration: configuration.workDuration
            ),
            completedInterval: false
        )
    }

    private func makeTransition(
        from: Snapshot,
        reason: Reason,
        at date: Date,
        workResult: WorkResult? = nil
    ) -> Transition {
        Transition(
            from: from,
            to: snapshot(at: date),
            reason: reason,
            workResult: workResult
        )
    }
}
