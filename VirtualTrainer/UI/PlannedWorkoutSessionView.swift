import SwiftUI

struct PlannedWorkoutSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @EnvironmentObject private var trophyStore: TrophyStore
    @EnvironmentObject private var insightStore: InsightStore
    @State private var coordinator: PlannedWorkoutCoordinator
    @State private var didSaveHistorySummary = false
    @State private var savedHistorySummary: WorkoutSessionSummary?
    @State private var newlyEarnedTrophyEvents: [TrophyUnlockEvent] = []
    @State private var nearestTrophyProgress: TrophyProgress?
    @State private var workoutInsight: AIInsight?

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
        let historyCandidate = savedHistorySummary ?? coordinator.workoutSessionSummary()
        return WorkoutSummaryView(
            summary: coordinator.workoutSummary(),
            historySummary: savedHistorySummary,
            recap: WorkoutRecapBuilder().build(summary: historyCandidate),
            trophyEvents: newlyEarnedTrophyEvents,
            nearestTrophyProgress: nearestTrophyProgress,
            coachInsight: workoutInsight
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
        newlyEarnedTrophyEvents = trophyStore.update(
            after: summary,
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status
        )
        nearestTrophyProgress = trophyStore.snapshot.nearestInProgress
        workoutInsight = makeWorkoutInsight(for: summary)
        didSaveHistorySummary = true
    }

    private func makeWorkoutInsight(for summary: WorkoutSessionSummary) -> AIInsight? {
        guard let profile = onboardingStore.profile else { return nil }
        let now = Date()
        let trendEngine = TrendEngine()
        let trendSnapshot = trendEngine.buildSnapshot(
            history: historyStore.summaries,
            profile: profile,
            trophies: trophyStore.snapshot,
            now: now
        )
        let signals = SignalExtractor(trendEngine: trendEngine).extractSignals(
            snapshot: trendSnapshot,
            history: historyStore.summaries,
            profile: profile,
            trophies: trophyStore.snapshot,
            context: SignalGenerationContext(historySessionCount: historyStore.summaries.count)
        )
        let generated = InsightEngine().generateWorkoutInsights(
            profile: profile,
            summary: summary,
            plan: coordinator.plan,
            trendSnapshot: trendSnapshot,
            signals: signals,
            engagementRecords: insightStore.engagementRecordsSnapshot(),
            now: now
        )
        let currentWorkoutGenerated = generated.filter { insight in
            insight.evidence.contains { $0.workoutId == summary.id }
        }
        return insightStore.selectGeneratedInsights(
            currentWorkoutGenerated,
            for: .workoutSummary,
            profile: profile,
            limit: 1,
            now: now
        ).first
    }
}

#Preview {
    PlannedWorkoutSessionView(
        plan: WorkoutPlan.MockData.legDay.convertedToV2()
    )
    .environmentObject(OnboardingStore())
    .environmentObject(CalibrationStore())
    .environmentObject(WorkoutHistoryStore())
    .environmentObject(TrophyStore())
    .environmentObject(InsightStore())
}
