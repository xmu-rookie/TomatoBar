import XCTest
@testable import TomatoBar

final class StatisticsEngineTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
    }

    func testTodayWeekAndMonthUseCalendarBoundaries() {
        let records = [
            record(at: date(2026, 7, 30, 9), seconds: 600, tomatoes: 0.4),
            record(at: date(2026, 7, 27, 9), seconds: 900, tomatoes: 0.6),
            record(at: date(2026, 7, 1, 9), seconds: 1_200, tomatoes: 0.8),
            record(at: date(2026, 6, 30, 9), seconds: 1_500, tomatoes: 1),
        ]

        let result = StatisticsEngine.analyze(
            records: records,
            now: date(2026, 7, 30, 12),
            calendar: calendar
        )

        XCTAssertEqual(result.today.seconds, 600, accuracy: 0.001)
        XCTAssertEqual(result.week.seconds, 1_500, accuracy: 0.001)
        XCTAssertEqual(result.month.seconds, 2_700, accuracy: 0.001)
        XCTAssertEqual(result.today.tomatoes, 0.4, accuracy: 0.001)
    }

    func testCrossMidnightFocusIsSplitAcrossDays() {
        let start = date(2026, 7, 30, 23, 50)
        let end = date(2026, 7, 31, 0, 10)
        let record = FocusSessionRecord(
            startedAt: start,
            endedAt: end,
            activeDuration: 1_200,
            tomatoCount: 1,
            focusIntervals: [DateInterval(start: start, end: end)]
        )

        let result = StatisticsEngine.analyze(
            records: [record],
            now: date(2026, 7, 31, 12),
            calendar: calendar
        )

        XCTAssertEqual(result.today.seconds, 600, accuracy: 0.001)
        XCTAssertEqual(result.today.tomatoes, 0.5, accuracy: 0.001)
        XCTAssertEqual(
            result.dailyTrend.suffix(2).map(\.aggregate.seconds),
            [600, 600]
        )
    }

    func testTrendAndHeatmapIncludeEmptyCalendarDays() {
        let result = StatisticsEngine.analyze(
            records: [],
            now: date(2026, 7, 30, 12),
            calendar: calendar
        )

        XCTAssertEqual(result.dailyTrend.count, 14)
        XCTAssertEqual(result.heatmap.count, 84)
        XCTAssertTrue(
            result.dailyTrend.allSatisfy { $0.aggregate == FocusAggregate() }
        )
        XCTAssertEqual(result.heatmap.first?.weekdayIndex, 0)
        XCTAssertEqual(
            result.heatmap.first?.date,
            date(2026, 5, 11)
        )
    }

    func testTaskAndProjectRankingsUseTotalFocusTime() {
        let records = [
            record(
                at: date(2026, 7, 30, 9),
                seconds: 600,
                tomatoes: 0.4,
                taskID: "a",
                task: "Write",
                projectID: "work",
                project: "Work"
            ),
            record(
                at: date(2026, 7, 30, 10),
                seconds: 1_200,
                tomatoes: 0.8,
                taskID: "b",
                task: "Review",
                projectID: "work",
                project: "Work"
            ),
            record(
                at: date(2026, 7, 30, 11),
                seconds: 300,
                tomatoes: 0.2
            ),
        ]

        let result = StatisticsEngine.analyze(
            records: records,
            now: date(2026, 7, 30, 12),
            calendar: calendar
        )

        XCTAssertEqual(result.tasks.map(\.id), ["b", "a"])
        XCTAssertEqual(result.projects.map(\.id), ["work"])
        XCTAssertEqual(
            result.projects.first?.aggregate.seconds ?? 0,
            1_800,
            accuracy: 0.001
        )
        XCTAssertEqual(
            result.projects.first?.aggregate.tomatoes ?? 0,
            1.2,
            accuracy: 0.001
        )
    }

    private func record(
        at start: Date,
        seconds: TimeInterval,
        tomatoes: Double,
        taskID: String? = nil,
        task: String? = nil,
        projectID: String? = nil,
        project: String? = nil
    ) -> FocusSessionRecord {
        FocusSessionRecord(
            startedAt: start,
            endedAt: start.addingTimeInterval(seconds),
            activeDuration: seconds,
            tomatoCount: tomatoes,
            taskID: taskID,
            taskContent: task,
            projectID: projectID,
            projectName: project,
            focusIntervals: [
                DateInterval(
                    start: start,
                    end: start.addingTimeInterval(seconds)
                ),
            ]
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
