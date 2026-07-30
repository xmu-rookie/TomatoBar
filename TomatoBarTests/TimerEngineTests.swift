import XCTest
@testable import TomatoBar

final class TimerEngineTests: XCTestCase {
    private let startDate = Date(timeIntervalSince1970: 1_000)

    func testStartsWorkWithConfiguredDuration() {
        var engine = TimerEngine()

        let transition = engine.start(
            configuration: makeConfiguration(workDuration: 1_500),
            at: startDate
        )

        XCTAssertEqual(transition?.reason, .started)
        XCTAssertEqual(engine.status, .running)
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.remaining(at: startDate), 1_500)
    }

    func testPauseAndResumeExcludePausedTime() {
        var engine = TimerEngine()
        engine.start(
            configuration: makeConfiguration(workDuration: 1_500),
            at: startDate
        )

        engine.pause(at: startDate.addingTimeInterval(300))
        XCTAssertEqual(engine.status, .paused)
        XCTAssertEqual(engine.remaining(at: startDate.addingTimeInterval(900)), 1_200)

        engine.resume(at: startDate.addingTimeInterval(900))
        let transition = engine.stop(at: startDate.addingTimeInterval(1_200))

        XCTAssertEqual(transition?.workResult?.activeDuration, 600)
        XCTAssertEqual(transition?.workResult?.tomatoCount, 0.4)
    }

    func testCompletedWorkStartsShortRestByDefault() {
        var engine = TimerEngine()
        engine.start(configuration: makeConfiguration(workDuration: 60), at: startDate)

        let transition = engine.completeCurrentInterval(
            at: startDate.addingTimeInterval(60)
        )

        XCTAssertEqual(transition?.workResult?.tomatoCount, 1)
        XCTAssertEqual(engine.phase, .shortRest)
        XCTAssertEqual(engine.status, .running)
    }

    func testBreakWaitsWhenAutoStartBreaksIsDisabled() {
        var engine = TimerEngine()
        var configuration = makeConfiguration(workDuration: 60)
        configuration.autoStartBreaks = false
        engine.start(configuration: configuration, at: startDate)

        engine.completeCurrentInterval(at: startDate.addingTimeInterval(60))

        XCTAssertEqual(engine.phase, .shortRest)
        XCTAssertEqual(engine.status, .paused)
        XCTAssertEqual(engine.remaining(at: startDate.addingTimeInterval(600)), 30)
    }

    func testWorkWaitsWhenAutoStartWorkIsDisabled() {
        var engine = TimerEngine()
        var configuration = makeConfiguration(workDuration: 60)
        configuration.autoStartWork = false
        engine.start(configuration: configuration, at: startDate)
        engine.completeCurrentInterval(at: startDate.addingTimeInterval(60))

        engine.completeCurrentInterval(at: startDate.addingTimeInterval(90))

        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.status, .paused)
        XCTAssertEqual(engine.remaining(at: startDate.addingTimeInterval(600)), 60)
    }

    func testStopAfterBreakReturnsToIdle() {
        var engine = TimerEngine()
        var configuration = makeConfiguration(workDuration: 60)
        configuration.stopAfterBreak = true
        engine.start(configuration: configuration, at: startDate)
        engine.completeCurrentInterval(at: startDate.addingTimeInterval(60))

        let transition = engine.completeCurrentInterval(
            at: startDate.addingTimeInterval(90)
        )

        XCTAssertEqual(transition?.to.status, .idle)
        XCTAssertEqual(engine.status, .idle)
        XCTAssertNil(engine.phase)
    }

    func testFourthCompletedWorkStartsLongRest() {
        var engine = TimerEngine()
        let configuration = makeConfiguration(
            workDuration: 10,
            shortRestDuration: 5,
            longRestDuration: 20,
            workIntervalsPerSet: 4
        )
        engine.start(configuration: configuration, at: startDate)
        var date = startDate

        for _ in 1 ... 3 {
            date = date.addingTimeInterval(10)
            engine.completeCurrentInterval(at: date)
            XCTAssertEqual(engine.phase, .shortRest)
            date = date.addingTimeInterval(5)
            engine.completeCurrentInterval(at: date)
        }

        date = date.addingTimeInterval(10)
        engine.completeCurrentInterval(at: date)

        XCTAssertEqual(engine.phase, .longRest)
        XCTAssertEqual(engine.remaining(at: date), 20)
        XCTAssertEqual(engine.completedWorkIntervals, 0)
    }

    func testSkipRestStartsWorkImmediately() {
        var engine = TimerEngine()
        var configuration = makeConfiguration(workDuration: 60)
        configuration.autoStartWork = false
        engine.start(configuration: configuration, at: startDate)
        engine.completeCurrentInterval(at: startDate.addingTimeInterval(60))

        let transition = engine.skipRest(at: startDate.addingTimeInterval(65))

        XCTAssertEqual(transition?.reason, .restSkipped)
        XCTAssertEqual(engine.phase, .work)
        XCTAssertEqual(engine.status, .running)
    }

    func testCannotCompleteBeforeDeadline() {
        var engine = TimerEngine()
        engine.start(configuration: makeConfiguration(workDuration: 60), at: startDate)

        let transition = engine.completeCurrentInterval(
            at: startDate.addingTimeInterval(59)
        )

        XCTAssertNil(transition)
        XCTAssertEqual(engine.phase, .work)
    }

    func testTomatoCountUsesFifthBoundaries() {
        let cases: [(TimeInterval, Double)] = [
            (0, 0),
            (4 * 60 + 59, 0),
            (5 * 60, 0.2),
            (9 * 60 + 59, 0.2),
            (10 * 60, 0.4),
            (20 * 60, 0.8),
            (24 * 60 + 59, 0.8),
            (25 * 60, 1),
        ]

        for (duration, expected) in cases {
            XCTAssertEqual(
                TimerEngine.tomatoCount(
                    activeDuration: duration,
                    workDuration: 25 * 60
                ),
                expected,
                "Unexpected tomato count for \(duration) seconds"
            )
        }
    }

    func testCompletedCustomIntervalIsOneTomato() {
        XCTAssertEqual(
            TimerEngine.tomatoCount(
                activeDuration: 45 * 60,
                workDuration: 45 * 60,
                completedInterval: true
            ),
            1
        )
    }

    private func makeConfiguration(
        workDuration: TimeInterval = 60,
        shortRestDuration: TimeInterval = 30,
        longRestDuration: TimeInterval = 90,
        workIntervalsPerSet: Int = 4
    ) -> TimerEngine.Configuration {
        TimerEngine.Configuration(
            workDuration: workDuration,
            shortRestDuration: shortRestDuration,
            longRestDuration: longRestDuration,
            workIntervalsPerSet: workIntervalsPerSet
        )
    }
}
