import SwiftUI

struct PlannedWorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @State private var coordinator: PlannedWorkoutCoordinator
    @State private var didSaveHistorySummary = false
    @State private var savedHistorySummary: WorkoutSessionSummary?

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
                RestScreenView(restContext: restContext) { result in
                    continueTapped(result)
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
        WorkoutSummaryView(
            summary: coordinator.workoutSummary(),
            historySummary: savedHistorySummary
        ) {
            dismiss()
        }
        .onAppear {
            saveHistorySummaryIfNeeded()
        }
    }

    private func handleSetCompleted(_ summary: PlannedWorkoutSetSummary) {
        guard coordinator.completeCurrentSet(with: summary) else { return }
    }

    private func continueTapped(_ result: PlannedWorkoutRestResult) {
        coordinator.recordRestOutcome(result)
        coordinator.continueToNextSet()
    }

    private func cancelTapped() {
        coordinator.cancelSession()
        dismiss()
    }

    private func saveHistorySummaryIfNeeded() {
        guard coordinator.sessionState == .completed,
              !didSaveHistorySummary
        else { return }

        let summary = coordinator.workoutSessionSummary()
        guard historyStore.addSummary(summary) else { return }
        savedHistorySummary = summary
        didSaveHistorySummary = true
    }
}

#Preview {
    PlannedWorkoutSessionView(
        plan: WorkoutPlan.MockData.legDay.convertedToV2()
    )
    .environmentObject(WorkoutHistoryStore())
}
