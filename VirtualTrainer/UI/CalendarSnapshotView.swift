import SwiftUI

struct CalendarSnapshotView: View {
    let snapshot: WorkoutCalendarSnapshot
    let accent: Color

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs),
        count: 7
    )

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(monthTitle)
                    .font(.system(size: 16, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                Text("\(snapshot.completedDays.count) days / \(snapshot.streak)d streak")
                    .caption()
            }

            if snapshot.days.isEmpty {
                emptyState
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
                        ForEach(weekdayLabels, id: \.self) { label in
                            Text(label)
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
                        ForEach(snapshot.days) { day in
                            CalendarDayTile(
                                day: day,
                                dayLabel: dayLabel(for: day.date),
                                accent: accent
                            )
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var emptyState: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 40, height: 40)
                .background(Theme.Colors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text("No calendar data yet")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Saved workouts will appear here.")
                    .caption()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        if let timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        return calendar
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: snapshot.currentMonth)
    }

    private var weekdayLabels: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstIndex = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private func dayLabel(for date: Date) -> String {
        "\(calendar.component(.day, from: date))"
    }
}

private struct CalendarDayTile: View {
    let day: WorkoutCalendarDay
    let dayLabel: String
    let accent: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(dayLabel)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .monospacedDigit()
            Circle()
                .fill(day.isCompleted ? activeDotColor : Color.clear)
                .frame(width: 4, height: 4)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .accessibilityLabel(accessibilityLabel)
    }

    private var foregroundColor: Color {
        if day.isCompleted {
            return Theme.Colors.background
        }
        return day.isInCurrentMonth ? Theme.Colors.textSecondary : Theme.Colors.textTertiary.opacity(0.45)
    }

    private var backgroundColor: Color {
        if day.isCompleted {
            return accent
        }
        return day.isInCurrentMonth ? Theme.Colors.surfaceRaised : Theme.Colors.surfaceRaised.opacity(0.35)
    }

    private var activeDotColor: Color {
        Theme.Colors.background.opacity(0.78)
    }

    private var accessibilityLabel: String {
        if day.workoutCount == 1 {
            return "One workout"
        }
        return "\(day.workoutCount) workouts"
    }
}
