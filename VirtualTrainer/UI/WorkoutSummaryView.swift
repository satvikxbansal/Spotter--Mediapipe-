import SwiftUI

struct WorkoutSummaryView: View {
    @EnvironmentObject private var insightStore: InsightStore
    @EnvironmentObject private var historyStore: WorkoutHistoryStore

    let summary: WorkoutSummary
    let historySummary: WorkoutSessionSummary?
    let recap: WorkoutRecap
    let trophyEvents: [TrophyUnlockEvent]
    let nearestTrophyProgress: TrophyProgress?
    let coachInsight: AIInsight?
    let onDone: () -> Void

    @State private var isShowingDetail = false
    @State private var selectedInsightEvidence: AIInsight?

    init(
        summary: WorkoutSummary,
        historySummary: WorkoutSessionSummary?,
        recap: WorkoutRecap,
        trophyEvents: [TrophyUnlockEvent] = [],
        nearestTrophyProgress: TrophyProgress? = nil,
        coachInsight: AIInsight? = nil,
        onDone: @escaping () -> Void
    ) {
        self.summary = summary
        self.historySummary = historySummary
        self.recap = recap
        self.trophyEvents = trophyEvents
        self.nearestTrophyProgress = nearestTrophyProgress
        self.coachInsight = coachInsight
        self.onDone = onDone
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                statGrid
                trophySection
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
        .sheet(item: $selectedInsightEvidence) { insight in
            InsightEvidenceSheetView(
                insight: insight,
                summaries: evidenceSummaries
            ) { kind in
                insightStore.recordEngagement(insight, kind: kind)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
    private var trophySection: some View {
        if !trophyEvents.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Trophies Earned")
                    .font(.system(size: 18, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textPrimary)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(trophyEvents) { event in
                        TrophyUnlockEventCard(event: event)
                    }
                }
            }
        } else if let nearestTrophyProgress,
                  let definition = TrophyDefinitionCatalog.definition(for: nearestTrophyProgress.trophyId) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Closest Trophy")
                    .font(.system(size: 18, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textPrimary)

                TrophyProgressCard(
                    definition: definition,
                    progress: nearestTrophyProgress,
                    isFeatured: true
                )
            }
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

            Text(recap.headline)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(recap.bodyMessage)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if recap.highlightStat != nil || recap.nextStep != nil {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if let highlightStat = recap.highlightStat {
                        RecapEvidenceRow(icon: "chart.bar.fill", text: highlightStat)
                    }
                    if let nextStep = recap.nextStep {
                        RecapEvidenceRow(icon: "arrow.forward.circle.fill", text: "Next: \(nextStep)")
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }

            if let coachInsight {
                Divider()
                    .background(Theme.Colors.accent.opacity(0.35))
                    .padding(.vertical, Theme.Spacing.xs)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(coachInsight.headline)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(coachInsight.message)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    InsightEvidenceButton {
                        insightStore.recordEngagement(coachInsight, kind: .opened)
                        selectedInsightEvidence = coachInsight
                    }
                    InsightEngagementPrompt { kind in
                        insightStore.recordEngagement(coachInsight, kind: kind)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.accent.opacity(0.35), lineWidth: 1)
        )
        .id(coachInsight?.id ?? "summary-coach-recap")
        .onAppear {
            if let coachInsight {
                insightStore.recordImpression(coachInsight, on: .workoutSummary)
            }
        }
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

    private var evidenceSummaries: [WorkoutSessionSummary] {
        var summaries = historyStore.summaries
        if let historySummary,
           !summaries.contains(where: { $0.id == historySummary.id }) {
            summaries.append(historySummary)
        }
        return summaries
    }
}

private struct RecapEvidenceRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 18, alignment: .leading)

            Text(text)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

private struct TrophyUnlockEventCard: View {
    let event: TrophyUnlockEvent

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(Theme.Colors.background)
                .frame(width: 54, height: 54)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(event.title)
                    .font(.system(size: 19, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.accent)
                Text(event.reason)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Colors.accent.opacity(0.45), lineWidth: 1)
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
    let now = Date(timeIntervalSince1970: 1_776_400_000)
    let previewPlanId = UUID()
    let repEvents = [90, 91, 92, 93].enumerated().map { index, score in
        RepQualityEvent(
            exerciseType: .squat,
            setIndex: 0,
            repIndex: index + 1,
            timestamp: now.addingTimeInterval(TimeInterval(index)),
            secondsIntoSet: TimeInterval((index + 1) * 5),
            formScore: score,
            formGrade: FormScore.Grade.from(score: score).rawValue
        )
    }
    let qualitySummary = SetQualitySummary.build(repQualityEvents: repEvents)
    let historySummary = WorkoutSessionSummary(
        mode: .plannedWorkout,
        planId: previewPlanId,
        planTitle: "Preview Strength",
        title: "Preview Strength",
        goal: "Build clean strength.",
        coach: .good,
        startedAt: now.addingTimeInterval(-1_420),
        endedAt: now,
        durationSeconds: 1_420,
        totalReps: 42,
        totalHoldSeconds: 45,
        averageFormScore: 88,
        completionPercent: 1,
        exerciseSummaries: [
            ExerciseSetSummary(
                exerciseType: .squat,
                setIndex: 0,
                target: .reps(12),
                achievedReps: 24,
                achievedHoldSeconds: 0,
                averageFormScore: qualitySummary.averageFormScore,
                qualitySummary: qualitySummary,
                repQualityEvents: repEvents
            ),
            ExerciseSetSummary(
                exerciseType: .plank,
                setIndex: 1,
                target: .hold(seconds: 45),
                achievedReps: 0,
                achievedHoldSeconds: 45,
                averageFormScore: nil
            )
        ],
        topCue: nil,
        effortSummary: "Peak effort reached 50%. Solid working intensity.",
        createdAt: now
    )

    WorkoutSummaryView(
        summary: WorkoutSummary(
            planId: previewPlanId,
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
        historySummary: historySummary,
        recap: WorkoutRecapBuilder().build(summary: historySummary),
        onDone: {}
    )
    .environmentObject(InsightStore())
    .environmentObject(WorkoutHistoryStore())
}
