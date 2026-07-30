import Foundation

struct FocusSessionTracker {
    private struct TrackedSegment {
        let kind: FocusSegmentKind
        let startedAt: Date
        var endedAt: Date

        var duration: TimeInterval {
            max(0, endedAt.timeIntervalSince(startedAt))
        }
    }

    private var sessionStartedAt: Date?
    private var activeSegmentStartedAt: Date?
    private var pauseSegmentStartedAt: Date?
    private var segments: [TrackedSegment] = []

    @discardableResult
    mutating func consume(
        transition: TimerEngine.Transition,
        at date: Date,
        recordWork: Bool = true
    ) -> FocusSessionDraft? {
        var draft: FocusSessionDraft?

        if transition.from.phase == .work {
            switch transition.reason {
            case .paused:
                closeActiveSegment(at: date)
                if sessionStartedAt != nil {
                    pauseSegmentStartedAt = date
                }

            case .resumed:
                if sessionStartedAt == nil {
                    beginWork(at: date)
                } else {
                    closePauseSegment(at: date)
                    activeSegmentStartedAt = date
                }

            case .stopped, .intervalCompleted:
                if transition.from.status == .running {
                    closeActiveSegment(at: date)
                } else if transition.from.status == .paused {
                    closePauseSegment(at: date)
                }
                if recordWork, let result = transition.workResult {
                    draft = makeDraft(result: result, endedAt: date)
                }
                reset()

            case .started, .restSkipped:
                break
            }
        }

        if transition.from.phase != .work,
           transition.to.phase == .work {
            reset()
            if transition.to.status == .running {
                beginWork(at: date)
            }
        }

        return draft
    }

    private mutating func beginWork(at date: Date) {
        sessionStartedAt = date
        activeSegmentStartedAt = date
        pauseSegmentStartedAt = nil
        segments = []
    }

    private mutating func closeActiveSegment(at date: Date) {
        guard let activeSegmentStartedAt else {
            return
        }
        if date > activeSegmentStartedAt {
            segments.append(
                TrackedSegment(
                    kind: .focus,
                    startedAt: activeSegmentStartedAt,
                    endedAt: date
                )
            )
        }
        self.activeSegmentStartedAt = nil
    }

    private mutating func closePauseSegment(at date: Date) {
        guard let pauseSegmentStartedAt else {
            return
        }
        if date > pauseSegmentStartedAt {
            segments.append(
                TrackedSegment(
                    kind: .pause,
                    startedAt: pauseSegmentStartedAt,
                    endedAt: date
                )
            )
        }
        self.pauseSegmentStartedAt = nil
    }

    private func makeDraft(
        result: TimerEngine.WorkResult,
        endedAt: Date
    ) -> FocusSessionDraft? {
        guard result.activeDuration > 0, let sessionStartedAt else {
            return nil
        }

        var remainingFocusDuration = result.activeDuration
        var normalizedSegments: [FocusSessionDraft.Segment] = []

        for segment in segments {
            switch segment.kind {
            case .focus:
                let duration = min(segment.duration, remainingFocusDuration)
                if duration > 0 {
                    normalizedSegments.append(
                        .init(
                            kind: .focus,
                            startedAt: segment.startedAt,
                            endedAt: segment.startedAt.addingTimeInterval(duration)
                        )
                    )
                    remainingFocusDuration -= duration
                }

            case .pause:
                normalizedSegments.append(
                    .init(
                        kind: .pause,
                        startedAt: segment.startedAt,
                        endedAt: segment.endedAt
                    )
                )
            }
        }

        return FocusSessionDraft(
            startedAt: sessionStartedAt,
            endedAt: endedAt,
            activeDuration: result.activeDuration,
            tomatoCount: result.tomatoCount,
            completedInterval: result.completedInterval,
            segments: normalizedSegments
        )
    }

    private mutating func reset() {
        sessionStartedAt = nil
        activeSegmentStartedAt = nil
        pauseSegmentStartedAt = nil
        segments = []
    }
}
