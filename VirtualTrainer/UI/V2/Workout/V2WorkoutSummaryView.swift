import SwiftUI

nonisolated enum V2WorkoutSummaryPresentation {
    static func eyebrow(isFreeAnalysis: Bool) -> String {
        isFreeAnalysis ? "FREE ANALYSIS" : "MISSION COMPLETE"
    }

    static func showsTrophyStack(isFreeAnalysis: Bool) -> Bool {
        !isFreeAnalysis
    }

    static func showsPlanCompletion(isFreeAnalysis: Bool) -> Bool {
        !isFreeAnalysis
    }

    static func syncBannerLabel(for summary: WorkoutSessionSummary?) -> String? {
        summary?.syncMetadata.syncState == .pendingUpload ? "Saving to cloud…" : nil
    }

    static func workoutSummary(from freeAnalysis: FreeAnalysisSummary) -> WorkoutSummary {
        let qualitySummary = freeAnalysis.qualitySummary ?? SetQualitySummary.build(
            repQualityEvents: freeAnalysis.repQualityEvents,
            cueEvents: freeAnalysis.cueEvents
        )

        return WorkoutSummary(
            planId: freeAnalysis.id,
            planTitle: freeAnalysis.exerciseType.displayName,
            duration: freeAnalysis.duration,
            exercisesCompleted: 1,
            totalExercises: 1,
            completedSets: freeAnalysis.reps > 0 || freeAnalysis.holdDuration > 0 ? 1 : 0,
            totalSets: 1,
            totalReps: freeAnalysis.reps,
            totalHoldSeconds: freeAnalysis.holdDuration,
            averageFormScore: qualitySummary.averageFormScore ?? freeAnalysis.latestFormScore.map { Double($0.score) },
            completionPercentage: 1,
            exerciseSummaries: [
                WorkoutExerciseSummary(
                    exerciseIndex: 0,
                    exerciseType: freeAnalysis.exerciseType,
                    setsCompleted: 1,
                    totalReps: freeAnalysis.reps,
                    totalHoldSeconds: freeAnalysis.holdDuration
                )
            ]
        )
    }
}

struct V2WorkoutSummaryView: View {
    let theme: SpotterThemeOption
    let summary: WorkoutSummary
    let historySummary: WorkoutSessionSummary?
    let recap: WorkoutRecap
    let trophyEvents: [TrophyUnlockEvent]
    let nearestTrophyProgress: TrophyProgress?
    let coachInsight: AIInsight?
    let isFreeAnalysis: Bool
    var currentStreakDayCount: Int?
    var persistenceError: String?
    var auxiliaryActionTitle: String?
    var auxiliarySystemImage: String?
    var isAuxiliaryActionDisabled = false
    var onAuxiliaryAction: (() -> Void)?
    var detailActionTitle: String?
    var onDetailAction: (() -> Void)?
    var onCoachInsightAppeared: ((AIInsight) -> Void)?
    var onOpenInsightEvidence: ((AIInsight) -> Void)?
    var onInsightEngagement: ((AIInsight, InsightEngagementKind) -> Void)?
    let onDone: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                header
                heroStats
                if isFreeAnalysis {
                    singleExerciseBlock
                }
                formQualityCard
                exerciseList
                coachInsightCard
                streakCard
                trophySection
                errorCard
            }
            .padding(SpotterV2.Spacing.xl)
            .padding(.top, SpotterV2.Spacing.lg)
            .padding(.bottom, 132)
        }
        .background(SpotterV2.Tokens.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            HStack(alignment: .center, spacing: SpotterV2.Spacing.sm) {
                V2StatusPill(
                    theme: theme,
                    label: V2WorkoutSummaryPresentation.eyebrow(isFreeAnalysis: isFreeAnalysis)
                )

                if let banner = V2WorkoutSummaryPresentation.syncBannerLabel(for: historySummary) {
                    V2StatusPill(theme: theme, label: banner, pulsingDot: true)
                }
            }

            HStack(alignment: .top, spacing: SpotterV2.Spacing.md) {
                Image(systemName: isFreeAnalysis ? "camera.viewfinder" : "trophy.fill")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(SpotterV2.Tokens.primary(theme))
                    .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xs) {
                    Text(summary.planTitle)
                        .font(SpotterV2Typography.display(size: 40))
                        .fontWidth(.compressed)
                        .italic()
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(3)
                        .minimumScaleFactor(0.56)

                    if let historySummary {
                        Text(historySummary.authoritativeEndedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(SpotterV2Typography.caption(weight: .bold))
                            .tracking(1.0)
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    }
                }
            }
        }
    }

    private var heroStats: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: SpotterV2.Spacing.sm),
                GridItem(.flexible(), spacing: SpotterV2.Spacing.sm),
                GridItem(.flexible(), spacing: SpotterV2.Spacing.sm)
            ],
            spacing: SpotterV2.Spacing.sm
        ) {
            V2MetricPill(
                theme: theme,
                eyebrow: "Duration",
                value: durationText(summary.duration),
                detail: "Total time",
                systemImage: "timer"
            )
            V2MetricPill(
                theme: theme,
                eyebrow: summary.totalReps > 0 ? "Reps" : "Hold",
                value: summary.totalReps > 0 ? "\(summary.totalReps)" : durationText(summary.totalHoldSeconds),
                detail: summary.totalReps > 0 ? "Total reps" : "Total hold",
                systemImage: "repeat"
            )
            if V2WorkoutSummaryPresentation.showsPlanCompletion(isFreeAnalysis: isFreeAnalysis) {
                V2MetricPill(
                    theme: theme,
                    eyebrow: "Complete",
                    value: completionText,
                    detail: "\(summary.completedSets)/\(summary.totalSets) sets",
                    systemImage: "checkmark.seal.fill"
                )
            } else {
                V2MetricPill(
                    theme: theme,
                    eyebrow: "Form",
                    value: averageFormText,
                    detail: "Quality",
                    systemImage: "waveform.path.ecg"
                )
            }
        }
    }

    @ViewBuilder
    private var singleExerciseBlock: some View {
        if let exercise = summary.exerciseSummaries.first {
            V2Card(
                theme: theme,
                radius: SpotterV2.Radius.lg,
                borderColor: SpotterV2.Tokens.primary(theme).opacity(0.55)
            ) {
                VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                    V2SectionHeader(title: "Single Exercise")
                    HStack(spacing: SpotterV2.Spacing.md) {
                        Text("01")
                            .font(SpotterV2Typography.mono(size: 16))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(SpotterV2.Tokens.primary(theme))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                            Text(exercise.exerciseType.displayName)
                                .font(SpotterV2Typography.heading(size: 20))
                                .textCase(.uppercase)
                                .foregroundStyle(SpotterV2.Tokens.foreground)
                            Text(exerciseDetailText(exercise))
                                .font(SpotterV2Typography.caption(weight: .bold))
                                .tracking(0.8)
                                .textCase(.uppercase)
                                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var formQualityCard: some View {
        V2Card(
            theme: theme,
            radius: SpotterV2.Radius.lg,
            borderColor: SpotterV2.Tokens.chart1.opacity(0.62),
            hardShadowColor: SpotterV2.Tokens.chart1.opacity(0.18)
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                        Text("Form Quality")
                            .font(SpotterV2Typography.caption())
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.chart1)
                        Text(averageFormText)
                            .font(SpotterV2Typography.mono(size: 42))
                            .monospacedDigit()
                            .foregroundStyle(SpotterV2.Tokens.foreground)
                    }

                    Spacer()

                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 26, weight: .black))
                        .foregroundStyle(SpotterV2.Tokens.chart1)
                        .frame(width: 54, height: 54)
                        .background(SpotterV2.Tokens.chart1.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
                }

                HStack(alignment: .bottom, spacing: SpotterV2.Spacing.xs) {
                    ForEach(Array(formChartValues.enumerated()), id: \.offset) { _, value in
                        Capsule()
                            .fill(SpotterV2.Tokens.chart1)
                            .frame(height: max(CGFloat(value) * 72, 8))
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(SpotterV2.Tokens.secondary)
                            )
                    }
                }
                .frame(height: 78)
                .accessibilityHidden(true)

                Text(recap.highlightStat ?? "Form evidence is saved with this workout summary.")
                    .font(SpotterV2Typography.body(size: 13, weight: .bold))
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var exerciseList: some View {
        if !summary.exerciseSummaries.isEmpty {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                V2SectionHeader(
                    title: isFreeAnalysis ? "Exercise" : "Exercises Completed",
                    trailingTitle: "\(summary.exerciseSummaries.count)",
                    trailingSystemImage: "list.bullet"
                )

                VStack(spacing: SpotterV2.Spacing.sm) {
                    ForEach(Array(summary.exerciseSummaries.enumerated()), id: \.element.id) { index, exercise in
                        V2SummaryExerciseRow(
                            theme: theme,
                            index: index + 1,
                            summary: exercise,
                            formText: formText(for: exercise)
                        )
                    }
                }
            }
        }
    }

    private var coachInsightCard: some View {
        V2InsightCard(
            theme: theme,
            eyebrow: coachInsight == nil ? "Coach Insight" : "Coach AI",
            headline: coachInsight?.headline ?? recap.headline,
            bodyText: coachInsight?.message ?? recap.bodyMessage,
            onOpenEvidence: coachInsight.map { insight in
                {
                    onOpenInsightEvidence?(insight)
                }
            },
            onHelpful: coachInsight.map { insight in
                {
                    onInsightEngagement?(insight, .helpful)
                }
            },
            onNotHelpful: coachInsight.map { insight in
                {
                    onInsightEngagement?(insight, .notHelpful)
                }
            }
        )
        .id(coachInsight?.id ?? "v2-summary-recap")
        .onAppear {
            if let coachInsight {
                onCoachInsightAppeared?(coachInsight)
            }
        }
    }

    private var streakCard: some View {
        V2Card(theme: theme, radius: SpotterV2.Radius.lg) {
            HStack(spacing: SpotterV2.Spacing.md) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 52)
                    .background(SpotterV2.Tokens.primary(theme))
                    .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                    Text("Streak")
                        .font(SpotterV2Typography.caption())
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    Text(streakTitle)
                        .font(SpotterV2Typography.heading(size: 18))
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                    Text(streakSubtitle)
                        .font(SpotterV2Typography.body(size: 12, weight: .bold))
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: SpotterV2.Spacing.xs)
            }
        }
    }

    @ViewBuilder
    private var trophySection: some View {
        if V2WorkoutSummaryPresentation.showsTrophyStack(isFreeAnalysis: isFreeAnalysis) {
            if !trophyEvents.isEmpty {
                VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                    V2SectionHeader(title: "New Trophies")
                    ForEach(trophyEvents) { event in
                        V2TrophyCard(
                            theme: theme,
                            systemImage: TrophyDefinitionCatalog.definition(for: event.trophyId)?.iconName ?? "trophy.fill",
                            title: event.title,
                            subtitle: event.reason,
                            rarity: TrophyDefinitionCatalog.definition(for: event.trophyId)?.rarity.displayName ?? "Earned",
                            progress: 1
                        )
                    }
                }
            } else if let nearestTrophyProgress,
                      let definition = TrophyDefinitionCatalog.definition(for: nearestTrophyProgress.trophyId) {
                VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                    V2SectionHeader(title: "Closest Trophy")
                    V2TrophyCard(
                        theme: theme,
                        systemImage: definition.iconName,
                        title: definition.title,
                        subtitle: nearestTrophyProgress.progressLabel,
                        rarity: definition.rarity.displayName,
                        progress: nearestTrophyProgress.progressFraction,
                        isLocked: nearestTrophyProgress.confidence == .unavailable
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var errorCard: some View {
        if let persistenceError, !persistenceError.isEmpty {
            V2Card(
                theme: theme,
                radius: SpotterV2.Radius.md,
                borderColor: SpotterV2.Tokens.destructive
            ) {
                Text(persistenceError)
                    .font(SpotterV2Typography.body(size: 13, weight: .bold))
                    .foregroundStyle(SpotterV2.Tokens.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: SpotterV2.Spacing.sm) {
            if let auxiliaryActionTitle, let onAuxiliaryAction {
                V2SecondaryButton(
                    title: auxiliaryActionTitle,
                    systemImage: auxiliarySystemImage,
                    theme: theme,
                    isDisabled: isAuxiliaryActionDisabled,
                    action: onAuxiliaryAction
                )
            }

            if let detailActionTitle, let onDetailAction {
                V2SecondaryButton(
                    title: detailActionTitle,
                    systemImage: "arrow.right",
                    theme: theme,
                    action: onDetailAction
                )
            }

            V2CTAButton(
                title: "Done",
                systemImage: "checkmark",
                theme: theme,
                action: onDone
            )
        }
        .padding(.horizontal, SpotterV2.Spacing.xl)
        .padding(.top, SpotterV2.Spacing.md)
        .padding(.bottom, SpotterV2.Spacing.sm)
        .background(SpotterV2.Tokens.background)
    }

    private var averageFormText: String {
        guard let average = summary.averageFormScore else { return "N/A" }
        return "\(Int(average.rounded()))%"
    }

    private var completionText: String {
        "\(Int((summary.completionPercentage * 100).rounded()))%"
    }

    private var formChartValues: [Double] {
        let historyScores = historySummary?.exerciseSummaries
            .compactMap(\.averageFormScore)
            .map { min(max($0 / 100, 0.1), 1) } ?? []
        if !historyScores.isEmpty {
            return Array(historyScores.prefix(6))
        }

        let score = summary.averageFormScore.map { min(max($0 / 100, 0.1), 1) } ?? 0.5
        return [0.42, 0.52, score, max(score - 0.08, 0.22), min(score + 0.04, 1)]
    }

    private var streakTitle: String {
        if let currentStreakDayCount, currentStreakDayCount > 0 {
            let unit = currentStreakDayCount == 1 ? "day" : "days"
            return "\(currentStreakDayCount) \(unit) strong"
        }
        if historySummary != nil {
            return "Logged today"
        }
        return "Ready to save"
    }

    private var streakSubtitle: String {
        if let currentStreakDayCount, currentStreakDayCount > 0 {
            return isFreeAnalysis
                ? "This analysis counts toward your current training streak."
                : "This workout counts toward your current training streak."
        }
        if isFreeAnalysis {
            return historySummary == nil
                ? "Save this analysis to keep it in history."
                : "This free analysis is now part of your training history."
        }
        return "Planned workout evidence is saved for trends, insights, and trophy progress."
    }

    private func formText(for exercise: WorkoutExerciseSummary) -> String {
        let exerciseScores = historySummary?.exerciseSummaries
            .filter { $0.exerciseType == exercise.exerciseType }
            .compactMap(\.averageFormScore) ?? []
        guard !exerciseScores.isEmpty else { return "Form N/A" }
        let average = exerciseScores.reduce(0, +) / Double(exerciseScores.count)
        return "\(Int(average.rounded()))% form"
    }

    private func exerciseDetailText(_ exercise: WorkoutExerciseSummary) -> String {
        var pieces = ["\(exercise.setsCompleted) \(exercise.setsCompleted == 1 ? "set" : "sets")"]
        if exercise.totalReps > 0 {
            pieces.append("\(exercise.totalReps) reps")
        }
        if exercise.totalHoldSeconds > 0 {
            pieces.append("\(durationText(exercise.totalHoldSeconds)) hold")
        }
        return pieces.joined(separator: " / ")
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        guard seconds >= 60 else { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct V2SummaryExerciseRow: View {
    let theme: SpotterThemeOption
    let index: Int
    let summary: WorkoutExerciseSummary
    let formText: String

    var body: some View {
        HStack(spacing: SpotterV2.Spacing.md) {
            Text(String(format: "%02d", index))
                .font(SpotterV2Typography.mono(size: 14))
                .foregroundStyle(.black)
                .frame(width: 42, height: 42)
                .background(SpotterV2.Tokens.primary(theme))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                Text(summary.exerciseType.displayName)
                    .font(SpotterV2Typography.heading(size: 16))
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detailText)
                    .font(SpotterV2Typography.caption(weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: SpotterV2.Spacing.xs)

            V2StatusPill(theme: theme, label: formText)
        }
        .padding(SpotterV2.Spacing.md)
        .background(SpotterV2.Tokens.card)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                .stroke(SpotterV2.Tokens.border.opacity(0.6), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        var pieces = ["\(summary.setsCompleted) \(summary.setsCompleted == 1 ? "set" : "sets")"]
        if summary.totalReps > 0 {
            pieces.append("\(summary.totalReps) reps")
        }
        if summary.totalHoldSeconds > 0 {
            pieces.append("\(Self.durationText(summary.totalHoldSeconds)) hold")
        }
        return pieces.joined(separator: " / ")
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        guard seconds >= 60 else { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#if DEBUG
private struct V2WorkoutSummaryPreviewContent: View {
    let theme: SpotterThemeOption
    let isFreeAnalysis: Bool

    var body: some View {
        V2WorkoutSummaryView(
            theme: theme,
            summary: isFreeAnalysis ? Self.freeSummary : Self.plannedSummary,
            historySummary: isFreeAnalysis ? Self.freeHistorySummary : Self.plannedHistorySummary,
            recap: WorkoutRecap(
                headline: "Depth improved late.",
                bodyMessage: "You finished the final sets with cleaner reps after the first cue landed.",
                highlightStat: "8 excellent-form reps captured.",
                nextStep: "Keep the first two reps slower next time."
            ),
            trophyEvents: isFreeAnalysis ? [] : [Self.trophyEvent],
            nearestTrophyProgress: nil,
            coachInsight: nil,
            isFreeAnalysis: isFreeAnalysis,
            currentStreakDayCount: isFreeAnalysis ? 2 : 5,
            auxiliaryActionTitle: isFreeAnalysis ? "Saved to History" : nil,
            auxiliarySystemImage: "checkmark",
            isAuxiliaryActionDisabled: true,
            onAuxiliaryAction: {},
            detailActionTitle: "View Detail",
            onDetailAction: {},
            onDone: {}
        )
    }

    private static var plannedSummary: WorkoutSummary {
        WorkoutSummary(
            planId: UUID(),
            planTitle: "Lower Body Engine",
            duration: 1_420,
            exercisesCompleted: 2,
            totalExercises: 2,
            completedSets: 4,
            totalSets: 4,
            totalReps: 42,
            totalHoldSeconds: 30,
            averageFormScore: 89,
            completionPercentage: 1,
            exerciseSummaries: [
                WorkoutExerciseSummary(exerciseIndex: 0, exerciseType: .squat, setsCompleted: 2, totalReps: 24, totalHoldSeconds: 0),
                WorkoutExerciseSummary(exerciseIndex: 1, exerciseType: .plank, setsCompleted: 2, totalReps: 0, totalHoldSeconds: 30)
            ]
        )
    }

    private static var freeSummary: WorkoutSummary {
        WorkoutSummary(
            planId: UUID(),
            planTitle: "Air Squat",
            duration: 330,
            exercisesCompleted: 1,
            totalExercises: 1,
            completedSets: 1,
            totalSets: 1,
            totalReps: 18,
            totalHoldSeconds: 0,
            averageFormScore: 91,
            completionPercentage: 1,
            exerciseSummaries: [
                WorkoutExerciseSummary(exerciseIndex: 0, exerciseType: .squat, setsCompleted: 1, totalReps: 18, totalHoldSeconds: 0)
            ]
        )
    }

    private static var plannedHistorySummary: WorkoutSessionSummary {
        WorkoutSessionSummary(
            mode: .plannedWorkout,
            planId: plannedSummary.planId,
            planTitle: plannedSummary.planTitle,
            title: plannedSummary.planTitle,
            goal: "Build clean strength.",
            coach: .good,
            startedAt: Date().addingTimeInterval(-1_420),
            endedAt: Date(),
            durationSeconds: 1_420,
            totalReps: 42,
            totalHoldSeconds: 30,
            averageFormScore: 89,
            completionPercent: 1,
            exerciseSummaries: [
                ExerciseSetSummary(exerciseType: .squat, target: .reps(12), achievedReps: 24, achievedHoldSeconds: 0, averageFormScore: 90),
                ExerciseSetSummary(exerciseType: .plank, target: .hold(seconds: 30), achievedReps: 0, achievedHoldSeconds: 30, averageFormScore: 88)
            ],
            topCue: nil,
            effortSummary: "Steady effort."
        )
    }

    private static var freeHistorySummary: WorkoutSessionSummary {
        WorkoutSessionSummary(
            mode: .freeAnalysis,
            title: "Air Squat",
            coach: .good,
            startedAt: Date().addingTimeInterval(-330),
            endedAt: Date(),
            durationSeconds: 330,
            totalReps: 18,
            totalHoldSeconds: 0,
            averageFormScore: 91,
            exerciseSummaries: [
                ExerciseSetSummary(exerciseType: .squat, achievedReps: 18, achievedHoldSeconds: 0, averageFormScore: 91)
            ],
            topCue: nil,
            effortSummary: "Peak effort reached 55%."
        )
    }

    private static var trophyEvent: TrophyUnlockEvent {
        TrophyUnlockEvent(
            trophyId: "first-saved-workout",
            title: "First Save",
            subtitle: "Saved your first workout.",
            earnedAt: Date(),
            reason: "You logged a complete workout summary.",
            celebrationStyle: .standard
        )
    }
}

private struct V2WorkoutSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2WorkoutSummaryPreviewContent(theme: theme, isFreeAnalysis: false)
                    .previewDisplayName("\(theme.displayName) Planned - SE")
                    .previewDevice("iPhone SE (3rd generation)")
                V2WorkoutSummaryPreviewContent(theme: theme, isFreeAnalysis: true)
                    .previewDisplayName("\(theme.displayName) Free - Pro Max")
                    .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}
#endif
