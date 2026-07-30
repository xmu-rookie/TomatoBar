import Foundation

struct FocusSessionRecord: Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let activeDuration: TimeInterval
    let tomatoCount: Double
    let taskID: String?
    let taskContent: String?
    let projectID: String?
    let projectName: String?
    let focusIntervals: [DateInterval]

    init(session: FocusSession) {
        id = session.id
        startedAt = session.startedAt
        endedAt = session.endedAt
        activeDuration = session.activeDuration
        tomatoCount = session.tomatoCount
        taskID = session.todoistTaskID
        taskContent = session.taskContent
        projectID = session.todoistProjectID
        projectName = session.projectName
        focusIntervals = session.segments
            .filter { $0.kind == .focus && $0.endedAt > $0.startedAt }
            .map {
                DateInterval(start: $0.startedAt, end: $0.endedAt)
            }
    }

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        activeDuration: TimeInterval,
        tomatoCount: Double,
        taskID: String? = nil,
        taskContent: String? = nil,
        projectID: String? = nil,
        projectName: String? = nil,
        focusIntervals: [DateInterval] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeDuration = activeDuration
        self.tomatoCount = tomatoCount
        self.taskID = taskID
        self.taskContent = taskContent
        self.projectID = projectID
        self.projectName = projectName
        self.focusIntervals = focusIntervals
    }
}

struct FocusAggregate: Equatable {
    var seconds: TimeInterval = 0
    var tomatoes: Double = 0
    var sessionCount = 0
}

struct DailyFocusStat: Identifiable, Equatable {
    var id: Date {
        date
    }

    let date: Date
    let aggregate: FocusAggregate
    let weekIndex: Int
    let weekdayIndex: Int
}

struct RankedFocusStat: Identifiable, Equatable {
    let id: String
    let name: String
    let aggregate: FocusAggregate
}

struct FocusStatistics: Equatable {
    let today: FocusAggregate
    let week: FocusAggregate
    let month: FocusAggregate
    let dailyTrend: [DailyFocusStat]
    let heatmap: [DailyFocusStat]
    let tasks: [RankedFocusStat]
    let projects: [RankedFocusStat]
}

enum StatisticsEngine {
    static func analyze(
        records: [FocusSessionRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FocusStatistics {
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: todayStart, end: todayEnd)
        let month = calendar.dateInterval(of: .month, for: now)
            ?? DateInterval(start: todayStart, end: todayEnd)

        let trendStart = calendar.date(
            byAdding: .day,
            value: -13,
            to: todayStart
        )!
        let weekStart = week.start
        let heatmapStart = calendar.date(
            byAdding: .weekOfYear,
            value: -11,
            to: weekStart
        )!

        return FocusStatistics(
            today: aggregate(
                records,
                in: DateInterval(start: todayStart, end: todayEnd)
            ),
            week: aggregate(records, in: week),
            month: aggregate(records, in: month),
            dailyTrend: dailyStats(
                records: records,
                start: trendStart,
                dayCount: 14,
                calendar: calendar
            ),
            heatmap: dailyStats(
                records: records,
                start: heatmapStart,
                dayCount: 84,
                calendar: calendar
            ),
            tasks: ranking(
                records: records,
                key: \.taskID,
                name: \.taskContent
            ),
            projects: ranking(
                records: records,
                key: \.projectID,
                name: \.projectName
            )
        )
    }

    private static func aggregate(
        _ records: [FocusSessionRecord],
        in interval: DateInterval
    ) -> FocusAggregate {
        var result = FocusAggregate()
        for record in records {
            let seconds = overlapSeconds(record: record, interval: interval)
            guard seconds > 0 else {
                continue
            }
            result.seconds += seconds
            if record.activeDuration > 0 {
                result.tomatoes +=
                    record.tomatoCount * seconds / record.activeDuration
            }
            result.sessionCount += 1
        }
        return result
    }

    private static func overlapSeconds(
        record: FocusSessionRecord,
        interval: DateInterval
    ) -> TimeInterval {
        if !record.focusIntervals.isEmpty {
            return record.focusIntervals.reduce(0) { result, focus in
                result + overlap(focus, interval)
            }
        }

        let wallClock = DateInterval(
            start: record.startedAt,
            end: max(record.startedAt, record.endedAt)
        )
        guard wallClock.duration > 0 else {
            return interval.contains(record.startedAt)
                ? record.activeDuration
                : 0
        }
        let ratio = overlap(wallClock, interval) / wallClock.duration
        return record.activeDuration * ratio
    }

    private static func overlap(
        _ lhs: DateInterval,
        _ rhs: DateInterval
    ) -> TimeInterval {
        max(0, min(lhs.end, rhs.end).timeIntervalSince(max(lhs.start, rhs.start)))
    }

    private static func dailyStats(
        records: [FocusSessionRecord],
        start: Date,
        dayCount: Int,
        calendar: Calendar
    ) -> [DailyFocusStat] {
        (0 ..< dayCount).compactMap { offset in
            guard let day = calendar.date(
                byAdding: .day,
                value: offset,
                to: start
            ),
            let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: day
            ) else {
                return nil
            }
            let weekday = calendar.component(.weekday, from: day)
            let normalizedWeekday =
                (weekday - calendar.firstWeekday + 7) % 7
            return DailyFocusStat(
                date: day,
                aggregate: aggregate(
                    records,
                    in: DateInterval(start: day, end: nextDay)
                ),
                weekIndex: offset / 7,
                weekdayIndex: normalizedWeekday
            )
        }
    }

    private static func ranking(
        records: [FocusSessionRecord],
        key: KeyPath<FocusSessionRecord, String?>,
        name: KeyPath<FocusSessionRecord, String?>
    ) -> [RankedFocusStat] {
        var values: [String: (String, FocusAggregate)] = [:]
        for record in records {
            guard let id = record[keyPath: key],
                  let label = record[keyPath: name],
                  !label.isEmpty else {
                continue
            }
            var current = values[id]?.1 ?? FocusAggregate()
            current.seconds += record.activeDuration
            current.tomatoes += record.tomatoCount
            current.sessionCount += 1
            values[id] = (label, current)
        }
        return values.map {
            RankedFocusStat(
                id: $0.key,
                name: $0.value.0,
                aggregate: $0.value.1
            )
        }
        .sorted {
            if $0.aggregate.seconds != $1.aggregate.seconds {
                return $0.aggregate.seconds > $1.aggregate.seconds
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
    }
}
