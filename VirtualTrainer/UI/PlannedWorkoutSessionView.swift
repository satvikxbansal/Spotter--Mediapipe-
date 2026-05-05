import SwiftUI

struct PlannedWorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator: PlannedWorkoutCoordinator

    init(plan: WorkoutPlanV2) {
        _coordinator = State(
            initialValue: PlannedWorkoutCoordinator(plan: plan)
        )
    }

    var body: some View {
        ZStack {
            sessionContent

            if coordinator.isAwaitingContinue,
               let summary = coordinator.completedSetSummaries.last {
                setCompleteOverlay(summary)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var sessionContent: some View {
        if coordinator.isSessionComplete {
            workoutCompleteView
        } else if let context = coordinator.currentContext {
            TrainerSessionView(context: context) { summary in
                handleSetCompleted(summary)
            }
            .id(context.id)
        } else {
            workoutCompleteView
        }
    }

    private func setCompleteOverlay(_ summary: PlannedWorkoutSetSummary) -> some View {
        ZStack {
            Theme.Colors.scrim
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Set Complete")
                        .header(size: 34)
                    Text(summary.exerciseType.displayName)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(summary.target.formattedText)
                        .caption()
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SessionSummaryRow(
                        label: "Progress",
                        value: "Exercise \(summary.exerciseIndex + 1) of \(summary.totalExercises) • Set \(summary.setIndex + 1) of \(summary.totalSets)"
                    )
                    SessionSummaryRow(label: "Reps", value: "\(summary.reps)")
                    if summary.holdDuration > 0 {
                        SessionSummaryRow(
                            label: "Hold",
                            value: Self.durationText(summary.holdDuration)
                        )
                    }
                    SessionSummaryRow(
                        label: "Time",
                        value: Self.durationText(summary.duration)
                    )
                }

                Button(coordinator.hasNextSet ? "Continue" : "Finish") {
                    continueTapped()
                }
                .buttonStyle(PrimaryCTAStyle())
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .padding(Theme.Spacing.lg)
        }
        .transition(.opacity)
    }

    private var workoutCompleteView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Spacer()

            Text("Workout Complete")
                .header(size: 36)
            Text("\(coordinator.completedSetSummaries.count) sets logged")
                .bodyText()
                .foregroundStyle(Theme.Colors.textSecondary)

            Button("Done") {
                HapticsEngine.shared.buttonTap()
                dismiss()
            }
            .buttonStyle(PrimaryCTAStyle())

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.background)
    }

    private func handleSetCompleted(_ summary: PlannedWorkoutSetSummary) {
        guard coordinator.completeCurrentSet(with: summary) else { return }
    }

    private func continueTapped() {
        HapticsEngine.shared.buttonTap()
        coordinator.continueToNextSet()
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct SessionSummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label.uppercased())
                .caption()
                .frame(width: 92, alignment: .leading)
            Text(value)
                .bodyText()
            Spacer()
        }
    }
}

#Preview {
    PlannedWorkoutSessionView(
        plan: WorkoutPlan.MockData.legDay.convertedToV2()
    )
}
