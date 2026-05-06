import SwiftUI

struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    let historySummary: WorkoutSessionSummary?
    let onDone: () -> Void

    @State private var isShowingDetail = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                statGrid
                exerciseList
                coachInsightCard
            }
            .padding(Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Spacing.sm) {
                if historySummary != nil {
                    Button {
                        HapticsEngine.shared.buttonTap()
                        isShowingDetail = true
                    } label: {
                        Text("View Saved Detail")
                    }
                    .buttonStyle(SecondaryCTAStyle())
                }

                Button {
                    HapticsEngine.shared.buttonTap()
                    onDone()
                } label: {
                    Text("Done")
                }
                .buttonStyle(PrimaryCTAStyle())
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.sm)
            .background(Theme.Colors.background)
        }
        .sheet(isPresented: $isShowingDetail) {
            if let historySummary {
                WorkoutDetailSheetView(summary: historySummary)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(Theme.Colors.background)
                .frame(width: 70, height: 70)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))

            Text("Mission Complete")
                .header(size: 42)
            Text(summary.planTitle)
                .font(.system(size: 13, weight: .black))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textSecondary)
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
            SummaryStatCard(label: "Duration", value: durationText(summary.duration))
            SummaryStatCard(
                label: "Exercises",
                value: "\(summary.exercisesCompleted)/\(summary.totalExercises)"
            )
            SummaryStatCard(label: "Reps", value: "\(summary.totalReps)")
            SummaryStatCard(label: "Hold", value: durationText(summary.totalHoldSeconds))
            SummaryStatCard(label: "Avg Form", value: averageFormText)
            SummaryStatCard(label: "Completion", value: completionText)
        }
    }

    @ViewBuilder
    private var exerciseList: some View {
        if !summary.exerciseSummaries.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Exercises Completed")
                    .font(.system(size: 18, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textPrimary)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(summary.exerciseSummaries) { exercise in
                        WorkoutSummaryExerciseRow(summary: exercise)
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        }
    }

    private var coachInsightCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Theme.Colors.accent)
                Text("Coach Insight")
                    .font(.system(size: 13, weight: .black))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.accent)
            }

            Text(summary.coachInsight)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private var averageFormText: String {
        guard let average = summary.averageFormScore else { return "N/A" }
        return "\(Int(average.rounded()))%"
    }

    private var completionText: String {
        "\(Int((summary.completionPercentage * 100).rounded()))%"
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        guard seconds >= 60 else { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct SummaryStatCard: View {
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
                .font(.system(size: 32, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.divider, lineWidth: 1)
        )
    }
}

private struct WorkoutSummaryExerciseRow: View {
    let summary: WorkoutExerciseSummary

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Theme.Colors.background)
                .frame(width: 28, height: 28)
                .background(Theme.Colors.accent)
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
    }

    private var detailText: String {
        var pieces = ["\(summary.setsCompleted) \(summary.setsCompleted == 1 ? "set" : "sets")"]
        if summary.totalReps > 0 {
            pieces.append("\(summary.totalReps) reps")
        }
        if summary.totalHoldSeconds > 0 {
            pieces.append("\(Int(summary.totalHoldSeconds.rounded()))s hold")
        }
        return pieces.joined(separator: " / ")
    }
}

#Preview {
    WorkoutSummaryView(
        summary: WorkoutSummary(
            planId: UUID(),
            planTitle: "Preview Strength",
            duration: 1_420,
            exercisesCompleted: 2,
            totalExercises: 2,
            completedSets: 4,
            totalSets: 4,
            totalReps: 42,
            totalHoldSeconds: 45,
            averageFormScore: 88,
            completionPercentage: 1,
            coachInsight: "Coach insight will use form, cue, rest, and completion trends once workout history is live.",
            exerciseSummaries: [
                WorkoutExerciseSummary(
                    exerciseIndex: 0,
                    exerciseType: .squat,
                    setsCompleted: 2,
                    totalReps: 24,
                    totalHoldSeconds: 0
                ),
                WorkoutExerciseSummary(
                    exerciseIndex: 1,
                    exerciseType: .plank,
                    setsCompleted: 2,
                    totalReps: 0,
                    totalHoldSeconds: 45
                )
            ]
        ),
        historySummary: nil,
        onDone: {}
    )
}
