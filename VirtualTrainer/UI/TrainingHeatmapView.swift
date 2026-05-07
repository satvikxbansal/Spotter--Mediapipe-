import SwiftUI
import UIKit

struct TrainingHeatmapView: View {
    static let defaultDayCount = 84

    let summariesByDay: [Date: DayIntensitySummary]
    let profile: UserProfile
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDay: DayIntensitySummary?
    @State private var sharePayload: SharePayload?
    @State private var isRenderingShareCard = false

    private let rows = 7
    private let columns = 12

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                    Text("Last 12 Weeks")
                        .font(.system(size: 16, weight: .black))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(summaryLine)
                        .caption()
                }

                Spacer()

                Text(activeDayText)
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(accent)
            }

            heatmapGrid

            HStack(spacing: Theme.Spacing.xs) {
                Text("Less")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)

                ForEach(0...4, id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(fillColor(for: intensity))
                        .frame(width: 16, height: 16)
                        .shadow(
                            color: glowColor(for: intensity),
                            radius: reduceMotion ? 0 : glowRadius(for: intensity)
                        )
                }

                Text("More")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .accessibilityHidden(true)

            Button {
                renderShareCard()
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    if isRenderingShareCard {
                        ProgressView()
                            .tint(accent)
                        Text("Rendering")
                    } else {
                        Label("Share Heatmap", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .buttonStyle(SecondaryCTAStyle())
            .disabled(isRenderingShareCard)
            .opacity(isRenderingShareCard ? 0.7 : 1)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .sheet(item: $selectedDay) { day in
            DayDrillInSheet(day: day, calendar: calendar, accent: accent)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: [payload.image])
                .presentationDetents([.medium, .large])
        }
    }

    private var heatmapGrid: some View {
        VStack(spacing: 5) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<columns, id: \.self) { column in
                        let day = daySummary(row: row, column: column)
                        Button {
                            HapticsEngine.shared.buttonTap()
                            selectedDay = day
                        } label: {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(fillColor(for: day.intensity))
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(borderColor(for: day), lineWidth: 1)
                                )
                                .shadow(
                                    color: glowColor(for: day.intensity),
                                    radius: reduceMotion ? 0 : glowRadius(for: day.intensity)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(for: day))
                        .accessibilityValue("Intensity \(day.intensity) of 4")
                    }
                }
            }
        }
    }

    private var orderedDays: [DayIntensitySummary] {
        summariesByDay.values.sorted { $0.date < $1.date }
    }

    private var calendar: Calendar {
        TrendEngine().calendar(for: profile)
    }

    private var activeDayCount: Int {
        orderedDays.filter { $0.workoutCount > 0 }.count
    }

    private var activeDayText: String {
        activeDayCount == 1 ? "1 day active" : "\(activeDayCount) days active"
    }

    private var totalWorkoutCount: Int {
        orderedDays.reduce(0) { $0 + $1.workoutCount }
    }

    private var summaryLine: String {
        guard totalWorkoutCount > 0 else {
            return "No saved sessions in this window yet."
        }
        return "\(totalWorkoutCount) workouts / \(totalReps) reps / \(holdText(totalHoldSeconds)) holds"
    }

    private var totalReps: Int {
        orderedDays.reduce(0) { $0 + $1.totalReps }
    }

    private var totalHoldSeconds: Int {
        orderedDays.reduce(0) { $0 + $1.totalHoldSeconds }
    }

    private func daySummary(row: Int, column: Int) -> DayIntensitySummary {
        let index = column * rows + row
        if orderedDays.indices.contains(index) {
            return orderedDays[index]
        }

        let fallbackDate = calendar.startOfDay(for: Date())
        return DayIntensitySummary(
            date: fallbackDate,
            workoutCount: 0,
            totalReps: 0,
            totalHoldSeconds: 0,
            averageFormScore: nil,
            sessions: []
        )
    }

    private func fillColor(for intensity: Int) -> Color {
        switch intensity {
        case 1:
            return accent.opacity(0.24)
        case 2:
            return accent.opacity(0.52)
        case 3:
            return accent.opacity(0.86)
        case 4...:
            return accent
        default:
            return Theme.Colors.surfaceRaised.opacity(0.62)
        }
    }

    private func borderColor(for day: DayIntensitySummary) -> Color {
        day.workoutCount > 0 ? Theme.Colors.textPrimary.opacity(0.12) : Theme.Colors.divider.opacity(0.55)
    }

    private func glowColor(for intensity: Int) -> Color {
        intensity >= 4 ? accent.opacity(0.48) : .clear
    }

    private func glowRadius(for intensity: Int) -> CGFloat {
        intensity >= 4 ? 8 : 0
    }

    private func accessibilityLabel(for day: DayIntensitySummary) -> String {
        "\(dateLabel(for: day.date)), \(workoutCountText(day.workoutCount)), \(formText(day.averageFormScore)) form"
    }

    private func dateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }

    private func formText(_ score: Double?) -> String {
        guard let score else { return "no" }
        return "\(Int(score.rounded()))%"
    }

    private func workoutCountText(_ count: Int) -> String {
        count == 1 ? "1 workout" : "\(count) workouts"
    }

    private func holdText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0s" }
        guard seconds >= 60 else { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return remainingSeconds == 0 ? "\(minutes)m" : "\(minutes)m \(remainingSeconds)s"
    }

    @MainActor
    private func renderShareCard() {
        guard !isRenderingShareCard else { return }
        isRenderingShareCard = true
        Task { @MainActor in
            await Task.yield()
            let renderer = ShareCardRenderer()
            let image = renderer.renderTrainingHeatmapPoster(
                summariesByDay: summariesByDay,
                profile: profile,
                accent: accent
            )
            isRenderingShareCard = false
            if let image {
                sharePayload = SharePayload(image: image)
            }
        }
    }
}

struct DayDrillInSheet: View {
    let day: DayIntensitySummary
    let calendar: Calendar
    let accent: Color

    @State private var selectedSummary: WorkoutSessionSummary?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(dateTitle)
                        .header(size: 30)
                    Text(daySummaryText)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                if !intensityTags.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(intensityTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 10, weight: .black))
                                    .tracking(0.7)
                                    .textCase(.uppercase)
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .background(accent.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))
                            }
                        }

                        Text(coachReadText)
                            .caption()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if day.sessions.isEmpty {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "calendar")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: 42, height: 42)
                            .background(Theme.Colors.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                            Text("No saved sessions")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("A planned workout or free analysis save will fill this day.")
                                .caption()
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                } else {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(day.sessions) { summary in
                            DaySessionRow(summary: summary, accent: accent) {
                                HapticsEngine.shared.buttonTap()
                                selectedSummary = summary
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
        .sheet(item: $selectedSummary) { summary in
            WorkoutDetailSheetView(summary: summary)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: day.date)
    }

    private var daySummaryText: String {
        [
            day.workoutCount == 1 ? "1 workout" : "\(day.workoutCount) workouts",
            "\(day.totalReps) reps",
            "\(durationText(day.totalHoldSeconds)) hold",
            formText(day.averageFormScore)
        ].joined(separator: " / ")
    }

    private var intensityTags: [String] {
        var tags: [String] = []
        if day.workoutCount > 0 {
            tags.append(day.workoutCount == 1 ? "Workout logged" : "\(day.workoutCount) workouts")
        }
        if day.hasStrongForm {
            tags.append("Strong form")
        }
        if day.hasHighVolume {
            tags.append("High volume")
        }
        return tags
    }

    private var coachReadText: String {
        if day.intensity >= 4 {
            return "Big training day: session count, quality, and volume all stacked up."
        }
        if day.hasStrongForm && day.hasHighVolume {
            return "Quality and volume both showed up on the same day."
        }
        if day.hasStrongForm {
            return "Clean form helped this day stand out."
        }
        if day.hasHighVolume {
            return "Volume carried this day, even before form bonuses."
        }
        return "This day is logged, but it stayed light on the intensity scale."
    }

    private func formText(_ score: Double?) -> String {
        guard let score else { return "N/A form" }
        return "\(Int(score.rounded()))% form"
    }
}

private struct DaySessionRow: View {
    let summary: WorkoutSessionSummary
    let accent: Color
    let onOpenDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: summary.mode == .plannedWorkout ? "list.bullet.clipboard.fill" : "camera.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Theme.Colors.background)
                    .frame(width: 42, height: 42)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                    Text(summary.title)
                        .font(.system(size: 15, weight: .black))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    Text(detailText)
                        .caption()
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.xs)
            }

            Button(action: onOpenDetail) {
                Label("Open detail", systemImage: "chevron.right.circle.fill")
                    .font(.system(size: 12, weight: .black))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var detailText: String {
        var pieces = [summary.mode.displayName, durationText(summary.durationSeconds)]
        if summary.totalReps > 0 {
            pieces.append("\(summary.totalReps) reps")
        }
        if summary.totalHoldSeconds > 0 {
            pieces.append("\(durationText(summary.totalHoldSeconds)) hold")
        }
        if let score = summary.averageFormScore {
            pieces.append("\(Int(score.rounded()))% form")
        }
        return pieces.joined(separator: " / ")
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

private func durationText(_ seconds: Int) -> String {
    let safeSeconds = max(seconds, 0)
    guard safeSeconds >= 60 else { return "\(safeSeconds)s" }
    let hours = safeSeconds / 3_600
    let minutes = (safeSeconds % 3_600) / 60
    let remainingSeconds = safeSeconds % 60
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return remainingSeconds == 0 ? "\(minutes)m" : "\(minutes):\(String(format: "%02d", remainingSeconds))"
}

#Preview("Training Heatmap") {
    let profile = TrainingHeatmapPreviewData.profile
    let summaries = TrendEngine(calendar: TrainingHeatmapPreviewData.calendar).dailyIntensitySummary(
        history: TrainingHeatmapPreviewData.history,
        profile: profile,
        days: TrainingHeatmapView.defaultDayCount,
        now: TrainingHeatmapPreviewData.now
    )
    TrainingHeatmapView(
        summariesByDay: summaries,
        profile: profile,
        accent: profile.selectedTheme.accentColor
    )
    .padding()
    .background(Theme.Colors.background)
    .preferredColorScheme(.dark)
}

private enum TrainingHeatmapPreviewData {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        return calendar
    }()

    static let now = Date(timeIntervalSince1970: 1_778_100_300)

    static let profile = UserProfile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000008401") ?? UUID(),
        displayName: "Preview Athlete",
        genderIdentity: .preferNotToSay,
        age: 30,
        height: 170,
        heightUnit: .metric,
        weight: 70,
        weightUnit: .metric,
        primaryGoal: .strength,
        fitnessLevel: .beginner,
        equipment: [.bodyweight],
        preferredCoach: .bennett,
        selectedTheme: .hyper,
        timezoneIdentifier: "Asia/Kolkata",
        onboardingCompletedAt: now,
        createdAt: now,
        updatedAt: now
    )

    static let history: [WorkoutSessionSummary] = [
        makeSummary(dayOffset: -1, reps: 45, holdSeconds: 0, form: 88),
        makeSummary(dayOffset: -2, reps: 18, holdSeconds: 120, form: 82),
        makeSummary(dayOffset: -9, reps: 130, holdSeconds: 0, form: 91),
        makeSummary(dayOffset: -16, reps: 60, holdSeconds: 80, form: 86),
        makeSummary(dayOffset: -30, reps: 32, holdSeconds: 0, form: 76),
        makeSummary(dayOffset: -57, reps: 95, holdSeconds: 90, form: 89)
    ]

    static func makeSummary(
        dayOffset: Int,
        reps: Int,
        holdSeconds: Int,
        form: Double
    ) -> WorkoutSessionSummary {
        let endedAt = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        let set = ExerciseSetSummary(
            exerciseType: .squat,
            setIndex: 0,
            target: .reps(reps),
            achievedReps: reps,
            achievedHoldSeconds: holdSeconds,
            averageFormScore: form,
            completedAt: endedAt,
            durationSeconds: 360
        )
        return WorkoutSessionSummary(
            mode: .plannedWorkout,
            title: "Preview Strength",
            goal: "Build clean strength.",
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-1_200),
            endedAt: endedAt,
            durationSeconds: 1_200,
            totalReps: reps,
            totalHoldSeconds: holdSeconds,
            averageFormScore: form,
            completionPercent: 1,
            exerciseSummaries: [set],
            topCue: nil,
            effortSummary: "Preview effort."
        )
    }
}
