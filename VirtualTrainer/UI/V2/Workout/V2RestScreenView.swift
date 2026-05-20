import SwiftUI

struct V2RestScreenView: View {
    let theme: SpotterThemeOption
    let restContext: PlannedWorkoutRestContext
    let secondsRemaining: Int
    let totalRestSeconds: Int
    let onSkipRest: () -> Void
    let onAddRest: () -> Void
    let onStartSet: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                topBar
                countdownSection
                lastSetCard
                coachNoteCard
                upNextCard
            }
            .padding(SpotterV2.Spacing.xl)
            .padding(.bottom, 112)
        }
        .background(SpotterV2.Tokens.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                Text("Rest")
                    .font(SpotterV2Typography.caption())
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
                Text(restStatusText)
                    .font(SpotterV2Typography.heading(size: 24))
                    .fontWidth(.compressed)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
            }

            Spacer()

            Button(action: onSkipRest) {
                Label(skipTitle, systemImage: "forward.fill")
                    .font(SpotterV2Typography.caption(weight: .black))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .padding(.horizontal, SpotterV2.Spacing.sm)
                    .frame(minHeight: 40)
                    .background(SpotterV2.Tokens.secondary)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(SpotterV2.Tokens.border.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(skipTitle)
        }
    }

    private var countdownSection: some View {
        VStack(spacing: SpotterV2.Spacing.lg) {
            ZStack {
                Circle()
                    .stroke(SpotterV2.Tokens.secondary, lineWidth: 12)

                Circle()
                    .trim(from: 0, to: countdownProgress)
                    .stroke(
                        SpotterV2.Tokens.primary(theme),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: SpotterV2.Spacing.xxxs) {
                    Text(Self.timerText(secondsRemaining))
                        .font(SpotterV2Typography.mono(size: 72))
                        .monospacedDigit()
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(reduceMotion ? .identity : .numericText())

                    Text(secondsRemaining == 0 ? "Rest complete" : "Seconds left")
                        .font(SpotterV2Typography.caption())
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                }
            }
            .frame(width: 244, height: 244)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(secondsRemaining) seconds remaining")

            V2SecondaryButton(
                title: "+15 sec",
                systemImage: "plus",
                theme: theme,
                action: onAddRest
            )
        }
    }

    private var lastSetCard: some View {
        V2Card(
            theme: theme,
            radius: SpotterV2.Radius.xl,
            borderColor: SpotterV2.Tokens.border.opacity(0.68)
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                        V2SectionHeader(title: "Last Set")
                        Text(restContext.lastSummary.exerciseType.displayName)
                            .font(SpotterV2Typography.display(size: 30))
                            .fontWidth(.compressed)
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.foreground)
                            .lineLimit(2)
                            .minimumScaleFactor(0.62)
                    }

                    Spacer()

                    V2RestResultBadge(
                        theme: theme,
                        value: lastSetResultText,
                        label: lastSetResultLabel
                    )
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: SpotterV2.Spacing.sm),
                        GridItem(.flexible(), spacing: SpotterV2.Spacing.sm)
                    ],
                    spacing: SpotterV2.Spacing.sm
                ) {
                    V2RestMetric(theme: theme, title: "Reps", value: lastSetResultText, systemImage: "repeat")
                    V2RestMetric(theme: theme, title: "Form", value: formScoreText, systemImage: "checkmark.seal.fill")
                    V2RestMetric(theme: theme, title: "Range", value: rangeText, systemImage: "ruler")
                    V2RestMetric(theme: theme, title: "Cue", value: cueText, systemImage: "quote.bubble.fill")
                }
            }
        }
    }

    private var coachNoteCard: some View {
        V2InsightCard(
            theme: theme,
            eyebrow: "Coach note",
            headline: coachHeadline,
            bodyText: coachNote
        )
    }

    private var upNextCard: some View {
        V2Card(
            theme: theme,
            radius: SpotterV2.Radius.lg,
            borderColor: SpotterV2.Tokens.primary(theme).opacity(0.62)
        ) {
            HStack(alignment: .center, spacing: SpotterV2.Spacing.md) {
                Image(systemName: restContext.upNextContext.exerciseType.cameraPosition == .side ? "rotate.3d.fill" : "camera.viewfinder")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 48)
                    .background(SpotterV2.Tokens.primary(theme))
                    .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                    Text("Up Next")
                        .font(SpotterV2Typography.caption())
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    Text(restContext.upNextContext.exerciseType.displayName)
                        .font(SpotterV2Typography.heading(size: 20))
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(upNextDetail)
                        .font(SpotterV2Typography.caption(weight: .bold))
                        .tracking(0.7)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: SpotterV2.Spacing.xs)
            }
        }
    }

    private var bottomBar: some View {
        V2CTAButton(
            title: startButtonTitle,
            systemImage: "play.fill",
            theme: theme,
            action: onStartSet
        )
        .padding(.horizontal, SpotterV2.Spacing.xl)
        .padding(.top, SpotterV2.Spacing.md)
        .padding(.bottom, SpotterV2.Spacing.sm)
        .background(SpotterV2.Tokens.background)
    }

    private var countdownProgress: Double {
        guard totalRestSeconds > 0 else { return 0 }
        return min(max(Double(secondsRemaining) / Double(totalRestSeconds), 0), 1)
    }

    private var restStatusText: String {
        secondsRemaining == 0 ? "Ready for the next set" : "Breathe, reset, go again"
    }

    private var skipTitle: String {
        secondsRemaining == 0 ? "Start Now" : "Skip Rest"
    }

    private var lastSetResultText: String {
        let summary = restContext.lastSummary
        switch summary.target {
        case .reps:
            return "\(summary.reps)"
        case .hold:
            return Self.timerText(Int(summary.holdDuration.rounded()))
        case .timed:
            return Self.timerText(Int(summary.duration.rounded()))
        case .amrap, .open:
            return summary.reps > 0 ? "\(summary.reps)" : Self.timerText(Int(summary.duration.rounded()))
        }
    }

    private var lastSetResultLabel: String {
        switch restContext.lastSummary.target {
        case .reps, .amrap, .open:
            return restContext.lastSummary.reps == 1 ? "Rep" : "Reps"
        case .hold:
            return "Hold"
        case .timed:
            return "Work"
        }
    }

    private var formScoreText: String {
        if let average = restContext.lastSummary.qualitySummary?.averageFormScore {
            return "\(Int(average.rounded()))%"
        }
        if let score = restContext.lastSummary.latestFormScore {
            return "\(score.score)%"
        }
        return "No score"
    }

    private var rangeText: String {
        guard let qualitySummary = restContext.lastSummary.qualitySummary else {
            return "Not tracked"
        }
        switch qualitySummary.qualityTrend {
        case .improved:
            return "Improved"
        case .faded:
            return "Faded"
        case .stable:
            return "Stable"
        case .unknown:
            return "Not tracked"
        }
    }

    private var cueText: String {
        if let cue = restContext.lastSummary.bestCue ?? restContext.lastSummary.lastCue {
            return cue.message
        }
        if let mostRepeatedCue = restContext.lastSummary.qualitySummary?.mostRepeatedCue {
            return mostRepeatedCue
        }
        return "No cue"
    }

    private var coachHeadline: String {
        if let score = restContext.lastSummary.qualitySummary?.averageFormScore, score >= 85 {
            return "Quality held up under fatigue."
        }
        if restContext.lastSummary.qualitySummary?.qualityTrend == .improved {
            return "You cleaned it up as the set went on."
        }
        return "Use this rest to reset your next rep."
    }

    private var coachNote: String {
        if let cue = restContext.lastSummary.worstCue ?? restContext.lastSummary.lastCue {
            return "Next set: \(cue.message)"
        }
        return "Start the next set smooth, then build pace once the camera has clean form evidence."
    }

    private var upNextDetail: String {
        [
            "Exercise \(restContext.upNextContext.exerciseIndex + 1) of \(restContext.upNextContext.totalExercises)",
            "Set \(restContext.upNextContext.setIndex + 1) of \(restContext.upNextContext.totalSets)",
            restContext.upNextContext.targetText
        ].joined(separator: " / ")
    }

    private var startButtonTitle: String {
        if restContext.upNextContext.setIndex == 0 {
            return "Start Next Exercise"
        }
        return "Start Set \(restContext.upNextContext.setIndex + 1)"
    }

    private static func timerText(_ seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        guard safeSeconds >= 60 else { return "\(safeSeconds)" }
        return String(format: "%d:%02d", safeSeconds / 60, safeSeconds % 60)
    }
}

private struct V2RestResultBadge: View {
    let theme: SpotterThemeOption
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: SpotterV2.Spacing.xxxs) {
            Text(value)
                .font(SpotterV2Typography.mono(size: 24))
                .monospacedDigit()
                .foregroundStyle(SpotterV2.Tokens.primary(theme))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(label)
                .font(SpotterV2Typography.caption())
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
        }
        .frame(minWidth: 76, minHeight: 66)
        .background(SpotterV2.Tokens.secondary)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
    }
}

private struct V2RestMetric: View {
    let theme: SpotterThemeOption
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.primary(theme))
                .frame(width: 32, height: 32)
                .background(SpotterV2.Tokens.primary(theme).opacity(0.14))
                .clipShape(Circle())

            Text(title)
                .font(SpotterV2Typography.caption())
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)

            Text(value)
                .font(SpotterV2Typography.heading(size: 14))
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(SpotterV2.Spacing.sm)
        .background(SpotterV2.Tokens.secondary)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}

#if DEBUG
private struct V2RestScreenPreviewContent: View {
    let theme: SpotterThemeOption

    var body: some View {
        V2RestScreenView(
            theme: theme,
            restContext: Self.sampleRestContext,
            secondsRemaining: 45,
            totalRestSeconds: 60,
            onSkipRest: {},
            onAddRest: {},
            onStartSet: {}
        )
    }

    private static var sampleRestContext: PlannedWorkoutRestContext {
        let quality = SetQualitySummary.build(
            repQualityEvents: (1...10).map { index in
                RepQualityEvent(
                    exerciseType: .squat,
                    setIndex: 0,
                    repIndex: index,
                    secondsIntoSet: TimeInterval(index * 4),
                    formScore: 84 + index,
                    formGrade: "A"
                )
            }
        )
        let last = PlannedWorkoutSetSummary(
            planId: UUID(),
            exerciseType: .squat,
            target: .reps(12),
            setIndex: 0,
            totalSets: 3,
            exerciseIndex: 0,
            totalExercises: 2,
            duration: 42,
            reps: 12,
            holdDuration: 0,
            latestFormScore: FormScore(score: 91, grade: .A, romPenalty: 0, tempoPenalty: 0, feedbackPenalty: 0),
            peakEffort: 0.62,
            lastCue: CoachCue(message: "Keep your chest tall.", severity: .info),
            bestCue: CoachCue(message: "Depth looked strong.", severity: .info),
            completionSource: .targetMet,
            qualitySummary: quality
        )
        let next = WorkoutSessionContext(
            planId: UUID(),
            planTitle: "Lower Body Engine",
            exerciseType: .pushup,
            target: .reps(10),
            setIndex: 1,
            totalSets: 3,
            exerciseIndex: 1,
            totalExercises: 2,
            coach: .good,
            startsActive: false
        )
        return PlannedWorkoutRestContext(
            lastSummary: last,
            upNextContext: next,
            restSeconds: 60
        )
    }
}

private struct V2RestScreenView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2RestScreenPreviewContent(theme: theme)
                    .previewDisplayName("\(theme.displayName) - SE")
                    .previewDevice("iPhone SE (3rd generation)")
                V2RestScreenPreviewContent(theme: theme)
                    .previewDisplayName("\(theme.displayName) - Pro Max")
                    .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}
#endif
