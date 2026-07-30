import XCTest
@testable import TomatoBar

final class FocusSessionTrackerTests: XCTestCase {
    private let startDate = Date(timeIntervalSince1970: 1_000)

    func testTracksFocusAndPauseSegments() throws {
        var engine = TimerEngine()
        var tracker = FocusSessionTracker()
        let configuration = TimerEngine.Configuration(workDuration: 1_500)

        let started = try XCTUnwrap(
            engine.start(configuration: configuration, at: startDate)
        )
        tracker.consume(transition: started, at: startDate)

        let pausedAt = startDate.addingTimeInterval(300)
        let paused = try XCTUnwrap(engine.pause(at: pausedAt))
        tracker.consume(transition: paused, at: pausedAt)

        let resumedAt = startDate.addingTimeInterval(600)
        let resumed = try XCTUnwrap(engine.resume(at: resumedAt))
        tracker.consume(transition: resumed, at: resumedAt)

        let stoppedAt = startDate.addingTimeInterval(900)
        let stopped = try XCTUnwrap(engine.stop(at: stoppedAt))
        let draft = try XCTUnwrap(
            tracker.consume(transition: stopped, at: stoppedAt)
        )

        XCTAssertEqual(draft.activeDuration, 600)
        XCTAssertEqual(draft.tomatoCount, 0.4)
        XCTAssertEqual(draft.segments.map(\.kind), [.focus, .pause, .focus])
        XCTAssertEqual(
            draft.segments.filter { $0.kind == .focus }
                .reduce(0) { $0 + $1.endedAt.timeIntervalSince($1.startedAt) },
            600
        )
    }

    func testCompletedWorkTrimsLateTimerTick() throws {
        var engine = TimerEngine()
        var tracker = FocusSessionTracker()
        let configuration = TimerEngine.Configuration(workDuration: 60)
        let started = try XCTUnwrap(
            engine.start(configuration: configuration, at: startDate)
        )
        tracker.consume(transition: started, at: startDate)

        let lateTick = startDate.addingTimeInterval(61)
        let completed = try XCTUnwrap(
            engine.completeCurrentInterval(at: lateTick)
        )
        let draft = try XCTUnwrap(
            tracker.consume(transition: completed, at: lateTick)
        )

        XCTAssertEqual(draft.activeDuration, 60)
        XCTAssertEqual(draft.segments.count, 1)
        XCTAssertEqual(
            draft.segments[0].endedAt.timeIntervalSince(
                draft.segments[0].startedAt
            ),
            60
        )
    }

    func testWaitingForManualWorkStartDoesNotCreatePauseSegment() throws {
        var configuration = TimerEngine.Configuration(
            workDuration: 60,
            shortRestDuration: 30,
            autoStartWork: false
        )
        configuration.autoStartBreaks = true
        var engine = TimerEngine()
        var tracker = FocusSessionTracker()

        let started = try XCTUnwrap(
            engine.start(configuration: configuration, at: startDate)
        )
        tracker.consume(transition: started, at: startDate)

        let workCompletedAt = startDate.addingTimeInterval(60)
        let workCompleted = try XCTUnwrap(
            engine.completeCurrentInterval(at: workCompletedAt)
        )
        tracker.consume(transition: workCompleted, at: workCompletedAt)

        let restCompletedAt = startDate.addingTimeInterval(90)
        let restCompleted = try XCTUnwrap(
            engine.completeCurrentInterval(at: restCompletedAt)
        )
        tracker.consume(transition: restCompleted, at: restCompletedAt)
        XCTAssertEqual(engine.status, .paused)

        let resumedAt = startDate.addingTimeInterval(600)
        let resumed = try XCTUnwrap(engine.resume(at: resumedAt))
        tracker.consume(transition: resumed, at: resumedAt)

        let stoppedAt = resumedAt.addingTimeInterval(300)
        let stopped = try XCTUnwrap(engine.stop(at: stoppedAt))
        let draft = try XCTUnwrap(
            tracker.consume(transition: stopped, at: stoppedAt)
        )

        XCTAssertEqual(draft.startedAt, resumedAt)
        XCTAssertEqual(draft.segments.map(\.kind), [.focus])
    }

    func testCanDiscardOverrunWork() throws {
        var engine = TimerEngine()
        var tracker = FocusSessionTracker()
        let started = try XCTUnwrap(
            engine.start(
                configuration: .init(workDuration: 60),
                at: startDate
            )
        )
        tracker.consume(transition: started, at: startDate)

        let stoppedAt = startDate.addingTimeInterval(600)
        let stopped = try XCTUnwrap(engine.stop(at: stoppedAt))
        let draft = tracker.consume(
            transition: stopped,
            at: stoppedAt,
            recordWork: false
        )

        XCTAssertNil(draft)
    }
}
