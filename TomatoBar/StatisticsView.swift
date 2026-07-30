import Charts
import SwiftData
import SwiftUI

struct StatisticsRootView: View {
    var body: some View {
        TabView {
            StatisticsDashboardView()
                .tabItem {
                    Label(
                        NSLocalizedString(
                            "Statistics.overview.tab",
                            comment: "Statistics overview tab"
                        ),
                        systemImage: "chart.bar"
                    )
                }
            SessionHistoryView()
                .tabItem {
                    Label(
                        NSLocalizedString(
                            "Statistics.history.tab",
                            comment: "Statistics history tab"
                        ),
                        systemImage: "clock.arrow.circlepath"
                    )
                }
        }
        .frame(minWidth: 720, minHeight: 560)
    }
}

struct StatisticsDashboardView: View {
    @Query(sort: \FocusSession.startedAt)
    private var sessions: [FocusSession]

    private var statistics: FocusStatistics {
        StatisticsEngine.analyze(
            records: sessions.map(FocusSessionRecord.init)
        )
    }

    var body: some View {
        let current = statistics
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    summaryCard(
                        title: NSLocalizedString(
                            "Statistics.today.title",
                            comment: "Today statistics title"
                        ),
                        aggregate: current.today
                    )
                    summaryCard(
                        title: NSLocalizedString(
                            "Statistics.week.title",
                            comment: "Week statistics title"
                        ),
                        aggregate: current.week
                    )
                    summaryCard(
                        title: NSLocalizedString(
                            "Statistics.month.title",
                            comment: "Month statistics title"
                        ),
                        aggregate: current.month
                    )
                }

                GroupBox(
                    NSLocalizedString(
                        "Statistics.trend.title",
                        comment: "Daily trend title"
                    )
                ) {
                    Chart(current.dailyTrend) { day in
                        BarMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value(
                                "Minutes",
                                day.aggregate.seconds / 60
                            )
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                    .chartYAxisLabel(
                        NSLocalizedString(
                            "Statistics.minutes.axis",
                            comment: "Minutes chart axis"
                        )
                    )
                    .frame(height: 180)
                    .padding(.top, 8)
                }

                GroupBox(
                    NSLocalizedString(
                        "Statistics.heatmap.title",
                        comment: "Focus heatmap title"
                    )
                ) {
                    LazyHGrid(
                        rows: Array(
                            repeating: GridItem(.fixed(15), spacing: 4),
                            count: 7
                        ),
                        spacing: 4
                    ) {
                        ForEach(current.heatmap) { day in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    Color.accentColor.opacity(
                                        heatmapOpacity(
                                            seconds: day.aggregate.seconds
                                        )
                                    )
                                )
                                .frame(width: 15, height: 15)
                                .help(heatmapHelp(day))
                        }
                    }
                    .padding(.vertical, 8)
                }

                HStack(alignment: .top, spacing: 12) {
                    rankingBox(
                        title: NSLocalizedString(
                            "Statistics.tasks.title",
                            comment: "Task ranking title"
                        ),
                        values: current.tasks
                    )
                    rankingBox(
                        title: NSLocalizedString(
                            "Statistics.projects.title",
                            comment: "Project ranking title"
                        ),
                        values: current.projects
                    )
                }
            }
            .padding(20)
        }
        .navigationTitle(
            NSLocalizedString(
                "Statistics.title",
                comment: "Statistics window title"
            )
        )
    }

    private func summaryCard(
        title: String,
        aggregate: FocusAggregate
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(formatDuration(aggregate.seconds))
                    .font(.title2.monospacedDigit())
                Text(
                    String.localizedStringWithFormat(
                        NSLocalizedString(
                            "Statistics.tomatoes.format",
                            comment: "Statistics tomato count"
                        ),
                        aggregate.tomatoes,
                        aggregate.sessionCount
                    )
                )
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rankingBox(
        title: String,
        values: [RankedFocusStat]
    ) -> some View {
        GroupBox(title) {
            VStack(spacing: 8) {
                if values.isEmpty {
                    Text(NSLocalizedString(
                        "Statistics.ranking.empty",
                        comment: "Empty ranking message"
                    ))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(
                        Array(values.prefix(8).enumerated()),
                        id: \.element.id
                    ) { entry in
                        HStack {
                            Text("\(entry.offset + 1)")
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)
                            Text(entry.element.name)
                                .lineLimit(1)
                            Spacer()
                            Text(formatDuration(entry.element.aggregate.seconds))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .time(pattern: seconds >= 3600 ? .hourMinute : .minuteSecond)
        )
    }

    private func heatmapOpacity(seconds: TimeInterval) -> Double {
        guard seconds > 0 else {
            return 0.1
        }
        return min(1, 0.25 + seconds / 7200)
    }

    private func heatmapHelp(_ day: DailyFocusStat) -> String {
        "\(day.date.formatted(date: .abbreviated, time: .omitted)) · "
            + formatDuration(day.aggregate.seconds)
    }
}
