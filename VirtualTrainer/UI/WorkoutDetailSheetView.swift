import SwiftUI

struct WorkoutDetailSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let summary: WorkoutSessionSummary

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                statGrid
                effortCard
                topCueCard
                setList
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button {
                    HapticsEngine.shared.buttonTap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Theme.Colors.surfaceRaised)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close workout detail")
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .background(Theme.Colors.background)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(summary.mode.displayName.uppercased())
                .font(.system(size: 12, weight: .black))
                .tracking(1.4)
                .foregroundStyle(Theme.Colors.accent)

            Text(summary.title)
                .header(size: 34)

            HStack(spacing: Theme.Spacing.sm) {
                Text(summary.endedAt, style: .date)
                Text(summary.endedAt, style: .time)
                Text(summary.coach.coachName)
            }
            .font(.system(size: 12, weight: .heavy))
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.textSecondary)

            if let goal = summary.goal {
                Text(goal)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Theme.Spacing.sm),
                GridItem(.flexible(), spacing: Theme.Spacing.sm)
            ],
            spacing: Theme.Spacing.sm
        ) {
            DetailStatCard(label: "Duration", value: durationText(summary.durationSeconds))
            DetailStatCard(label: "Reps", value: "\(summary.totalReps)")
            DetailStatCard(label: "Hold", value: durationText(summary.totalHoldSeconds))
            DetailStatCard(label: "Avg Form", value: formText)
            if let completionPercent = summary.completionPercent {
                DetailStatCard(
                    label: "Complete",
                    value: "\(Int((completionPercent * 100).rounded()))%"
                )
            }
        }
    }

    private var effortCard: some View {
        DetailInfoCard(
            systemImage: "bolt.heart.fill",
            title: "Effort",
            tint: Theme.Colors.accent,
            bodyText: summary.effortSummary
        )
    }

    @ViewBuilder
    private var topCueCard: some View {
        if let cue = summary.topCue {
            DetailInfoCard(
                systemImage: "lightbulb.fill",
                title: "Top Cue",
                tint: cueTint(cue.severity),
                bodyText: cue.cueMessage
            )
        }
    }

    private var setList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Exercises Logged")
                .font(.system(size: 18, weight: .black))
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(summary.exerciseSummaries.enumerated()), id: \.offset) { _, setSummary in
                    ExerciseSetDetailRow(summary: setSummary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.divider, lineWidth: 1)
        )
    }

    private var formText: String {
        guard let average = summary.averageFormScore else { return "N/A" }
        return "\(Int(average.rounded()))%"
    }

    private func cueTint(_ severity: CoachCue.Severity) -> Color {
        switch severity {
        case .info:
            return Theme.Colors.positive
        case .warning:
            return Theme.Colors.accent
        case .critical:
            return Theme.Colors.danger
        }
    }

    private func durationText(_ seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        guard safeSeconds >= 60 else { return "\(safeSeconds)s" }
        return String(format: "%d:%02d", safeSeconds / 60, safeSeconds % 60)
    }
}

private struct DetailStatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(label)
                .font(.system(size: 10, weight: .black))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text(value)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.divider, lineWidth: 1)
        )
    }
}

private struct DetailInfoCard: View {
    let systemImage: String
    let title: String
    let tint: Color
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .black))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(tint)

            Text(bodyText)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct ExerciseSetDetailRow: View {
    let summary: ExerciseSetSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Theme.Colors.background)
                    .frame(width: 28, height: 28)
                    .background(statusTint)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                    Text(summary.exerciseType.displayName)
                        .font(.system(size: 15, weight: .black))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(detailText)
                        .font(.system(size: 11, weight: .heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()
            }

            if let cue = summary.cueEvents.first {
                Text(cue.cueMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var detailText: String {
        var pieces: [String] = []
        if let setIndex = summary.setIndex {
            pieces.append("Set \(setIndex + 1)")
        }
        if let target = summary.target {
            pieces.append(target.formattedText)
        }
        if summary.achievedReps > 0 {
            pieces.append("\(summary.achievedReps) reps")
        }
        if summary.achievedHoldSeconds > 0 {
            pieces.append("\(summary.achievedHoldSeconds)s hold")
        }
        if let score = summary.averageFormScore {
            pieces.append("\(Int(score.rounded()))% form")
        }
        if summary.restExtended {
            pieces.append("rest extended")
        }
        if summary.skipped {
            pieces.append("rest skipped")
        }
        return pieces.isEmpty ? "Logged" : pieces.joined(separator: " / ")
    }

    private var statusIcon: String {
        summary.skipped ? "forward.fill" : "checkmark"
    }

    private var statusTint: Color {
        summary.skipped ? Theme.Colors.accent : Theme.Colors.positive
    }
}

#Preview {
    WorkoutDetailSheetView(
        summary: WorkoutSessionSummary(
            mode: .plannedWorkout,
            planId: UUID(),
            title: "Preview Strength",
            goal: "Build clean strength.",
            coach: .good,
            startedAt: Date().addingTimeInterval(-1_200),
            endedAt: Date(),
            durationSeconds: 1_200,
            totalReps: 32,
            totalHoldSeconds: 45,
            averageFormScore: 88,
            completionPercent: 1,
            exerciseSummaries: [
                ExerciseSetSummary(
                    exerciseType: .squat,
                    setIndex: 0,
                    target: .reps(12),
                    achievedReps: 12,
                    achievedHoldSeconds: 0,
                    averageFormScore: 90,
                    cueEvents: [
                        CueEvent(
                            timestamp: Date(),
                            exerciseType: .squat,
                            cueMessage: "Keep your knees tracking over your toes",
                            severity: .warning
                        )
                    ]
                )
            ],
            topCue: CueEvent(
                timestamp: Date(),
                exerciseType: .squat,
                cueMessage: "Keep your knees tracking over your toes",
                severity: .warning
            ),
            effortSummary: "Peak effort reached 58%. Solid working intensity."
        )
    )
}
