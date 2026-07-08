import SwiftUI
import Charts

/// "Statistics" section content for the Focus settings tab.
struct FocusStatisticsView: View {
    let history: FocusHistoryStore
    @State private var rangeDays = 7

    private var calendar: Calendar { .current }

    var body: some View {
        LabeledContent("Today", value: summary(
            count: history.completedToday,
            seconds: history.focusSeconds(since: calendar.startOfDay(for: .now))
        ))
        LabeledContent("This week", value: summary(
            count: history.sessionCount(since: startOfWeek),
            seconds: history.focusSeconds(since: startOfWeek)
        ))
        LabeledContent("All time", value: summary(
            count: history.totalSessions,
            seconds: history.totalFocusSeconds
        ))

        if history.totalSessions > 0 {
            Picker("Range", selection: $rangeDays) {
                Text("7 days").tag(7)
                Text("14 days").tag(14)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Chart(history.dailyTotals(days: rangeDays)) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Minutes", day.focusSeconds / 60)
                )
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    // Weekday letters repeat past one week; switch to day numbers.
                    if rangeDays > 7 {
                        AxisValueLabel(format: .dateTime.day(), centered: true)
                    } else {
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
            }
            .frame(height: 160)
        } else {
            Text("No completed focus sessions yet.")
                .foregroundStyle(.secondary)
        }
    }

    private var startOfWeek: Date {
        calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
    }

    private func summary(count: Int, seconds: TimeInterval) -> String {
        let sessions = "\(count) session\(count == 1 ? "" : "s")"
        guard seconds > 0 else { return sessions }
        let time = Duration.seconds(seconds)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return "\(sessions) · \(time)"
    }
}
