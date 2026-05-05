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
        sessionContent
        .preferredColorScheme(.dark)
        .onAppear {
            coordinator.startSession()
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        switch coordinator.sessionState {
        case .ready, .activeSet:
            activeSetView
        case .rest:
            if let restContext = coordinator.restContext {
                RestScreenView(restContext: restContext) {
                    continueTapped()
                }
                .id(restContext.id)
            } else {
                workoutCompleteView
            }
        case .completed:
            workoutCompleteView
        case .cancelled:
            Color.clear
                .background(Theme.Colors.background)
                .onAppear { dismiss() }
        }
    }

    @ViewBuilder
    private var activeSetView: some View {
        if let context = coordinator.currentContext {
            TrainerSessionView(
                context: context,
                onPlannedSetCompleted: { summary in
                    handleSetCompleted(summary)
                },
                onPlannedSessionCancelled: {
                    cancelTapped()
                }
            )
            .id(context.id)
        } else {
            workoutCompleteView
        }
    }

    private var workoutCompleteView: some View {
        WorkoutSummaryView(summary: coordinator.workoutSummary()) {
            dismiss()
        }
    }

    private func handleSetCompleted(_ summary: PlannedWorkoutSetSummary) {
        guard coordinator.completeCurrentSet(with: summary) else { return }
    }

    private func continueTapped() {
        coordinator.continueToNextSet()
    }

    private func cancelTapped() {
        coordinator.cancelSession()
        dismiss()
    }
}

#Preview {
    PlannedWorkoutSessionView(
        plan: WorkoutPlan.MockData.legDay.convertedToV2()
    )
}
