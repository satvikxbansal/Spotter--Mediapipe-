import SwiftUI
import Combine

struct RestScreenView: View {
    let restContext: PlannedWorkoutRestContext
    let onStartNext: (PlannedWorkoutRestResult) -> Void

    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var designSystemV2Toggle: DesignSystemV2ToggleStore

    @State private var secondsRemaining: Int
    @State private var totalRestSeconds: Int
    @State private var didSignalRestComplete: Bool = false
    @State private var didExtendRest: Bool = false

    init(
        restContext: PlannedWorkoutRestContext,
        onStartNext: @escaping (PlannedWorkoutRestResult) -> Void
    ) {
        self.restContext = restContext
        self.onStartNext = onStartNext

        let initialRest = max(restContext.restSeconds, 0)
        _secondsRemaining = State(initialValue: initialRest)
        _totalRestSeconds = State(initialValue: max(initialRest, 1))
    }

    var body: some View {
        Group {
            if designSystemV2Toggle.isEffectivelyEnabled {
                V2RestScreenView(
                    theme: themeStore.selectedTheme,
                    restContext: restContext,
                    secondsRemaining: secondsRemaining,
                    totalRestSeconds: totalRestSeconds,
                    onSkipRest: startNextSet,
                    onAddRest: addRest,
                    onStartSet: startNextSet
                )
            } else {
                v1Body
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            signalRestCompleteIfNeeded()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard secondsRemaining > 0 else {
                signalRestCompleteIfNeeded()
                return
            }
            secondsRemaining -= 1
            signalRestCompleteIfNeeded()
        }
    }

    private var v1Body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                skipRestHeader
                countdownSection
                lastSetCard
                upNextSection
            }
            .padding(Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private var skipRestHeader: some View {
        HStack {
            Spacer()
            Button(restHeaderActionTitle) {
                startNextSet()
            }
            .font(.system(size: 12, weight: .black))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var countdownSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(Theme.Colors.surfaceRaised, lineWidth: 8)

                Circle()
                    .trim(from: 0, to: countdownProgress)
                    .stroke(
                        Theme.Colors.accent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: countdownProgress)

                VStack(spacing: Theme.Spacing.xs) {
                    Text("\(secondsRemaining)")
                        .font(.system(size: 92, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .contentTransition(.numericText(value: Double(secondsRemaining)))

                    Text(countdownStatusText)
                        .font(.system(size: 11, weight: .black))
                        .tracking(2.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(width: 248, height: 248)
            .frame(maxWidth: .infinity)

            Button {
                addRest()
            } label: {
                Label("+15 sec", systemImage: "plus")
            }
            .buttonStyle(SecondaryCTAStyle())
        }
        .frame(maxWidth: .infinity)
    }

    private var countdownProgress: Double {
        guard totalRestSeconds > 0 else { return 0 }
        return min(max(Double(secondsRemaining) / Double(totalRestSeconds), 0), 1)
    }

    private var countdownStatusText: String {
        if secondsRemaining == 0 {
            return "Rest Complete"
        }
        return secondsRemaining == 1 ? "Second Left" : "Seconds Left"
    }

    private var restHeaderActionTitle: String {
        secondsRemaining == 0 ? "Start Now" : "Skip Rest"
    }

    private var lastSetCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Last Set")
                        .caption()
                    Text(restContext.lastSummary.exerciseType.displayName)
                        .font(.system(size: 28, weight: .black))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Spacer()

                RestMetricCard(
                    value: lastSetResultText,
                    label: lastSetResultLabel
                )
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                RestReviewRow(
                    systemImage: "checkmark.seal.fill",
                    title: "Last form score",
                    detail: formScoreText,
                    tint: formScoreTint
                )

                RestReviewRow(
                    systemImage: "sparkles",
                    title: "Best cue",
                    detail: bestCueText,
                    tint: Theme.Colors.positive
                )

                RestReviewRow(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Worst cue",
                    detail: worstCueText,
                    tint: Theme.Colors.danger
                )
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

    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                    Text("Up Next")
                        .caption()
                    Text(upNextTitle)
                        .font(.system(size: 22, weight: .black))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(upNextDetail)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()
            }

            Button {
                startNextSet()
            } label: {
                Label(startButtonTitle, systemImage: "play.fill")
            }
            .buttonStyle(PrimaryCTAStyle())
        }
    }

    private var lastSetResultText: String {
        let summary = restContext.lastSummary
        switch summary.target {
        case .reps:
            return "\(summary.reps)"
        case .hold:
            return Self.durationText(summary.holdDuration)
        case .timed:
            return Self.durationText(summary.duration)
        case .amrap, .open:
            if summary.reps > 0 {
                return "\(summary.reps)"
            }
            return Self.durationText(summary.duration)
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
        guard let score = restContext.lastSummary.latestFormScore else {
            return "No completed rep score yet."
        }
        return "\(score.grade.rawValue) \(score.score)%"
    }

    private var formScoreTint: Color {
        guard let score = restContext.lastSummary.latestFormScore else {
            return Theme.Colors.textSecondary
        }
        switch score.grade {
        case .A:
            return Theme.Colors.positive
        case .B, .C:
            return Theme.Colors.accent
        case .D, .F:
            return Theme.Colors.danger
        }
    }

    private var bestCueText: String {
        if let cue = restContext.lastSummary.bestCue {
            return cue.message
        }
        if let score = restContext.lastSummary.latestFormScore, score.score >= 80 {
            return "Form stayed in a strong range."
        }
        return "No positive cue captured yet."
    }

    private var worstCueText: String {
        if let cue = restContext.lastSummary.worstCue ?? restContext.lastSummary.lastCue {
            return cue.message
        }
        return "No correction cue logged."
    }

    private var upNextTitle: String {
        restContext.upNextContext.exerciseType.displayName
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

    private func addRest() {
        HapticsEngine.shared.buttonTap()
        didExtendRest = true
        if secondsRemaining == 0 {
            didSignalRestComplete = false
        }
        secondsRemaining += 15
        totalRestSeconds += 15
    }

    private func startNextSet() {
        HapticsEngine.shared.buttonTap()
        onStartNext(
            PlannedWorkoutRestResult(
                restExtended: didExtendRest,
                skipped: secondsRemaining > 0
            )
        )
    }

    private func signalRestCompleteIfNeeded() {
        guard secondsRemaining == 0, !didSignalRestComplete else { return }
        didSignalRestComplete = true
        HapticsEngine.shared.successRipple()
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        guard seconds >= 60 else { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct RestMetricCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: Theme.Spacing.xxxs) {
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .black))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(minWidth: 86)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

private struct RestReviewRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    RestScreenView(
        restContext: PlannedWorkoutRestContext(
            lastSummary: PlannedWorkoutSetSummary(
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
                latestFormScore: nil,
                peakEffort: 0.42,
                lastCue: nil,
                completionSource: .targetMet
            ),
            upNextContext: WorkoutSessionContext(
                planId: UUID(),
                planTitle: "Preview Plan",
                exerciseType: .pushup,
                target: .reps(8),
                setIndex: 0,
                totalSets: 2,
                exerciseIndex: 1,
                totalExercises: 2,
                coach: .good,
                startsActive: false
            ),
            restSeconds: 45
        ),
        onStartNext: { _ in }
    )
    .environmentObject(ThemeStore())
    .environmentObject(DesignSystemV2ToggleStore(remoteFlagSnapshotProvider: { false }))
}
