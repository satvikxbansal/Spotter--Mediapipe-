import SwiftUI

struct WorkoutDetailSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @EnvironmentObject private var trophyStore: TrophyStore
    @EnvironmentObject private var insightStore: InsightStore
    @State private var evidenceRequest: EvidenceSheetRequest?
    @State private var isShowingDeleteConfirmation = false
    @State private var detailedSummary: WorkoutSessionSummary?

    let summary: WorkoutSessionSummary

    private var displayedSummary: WorkoutSessionSummary {
        detailedSummary ?? summary
    }

    private var evidenceModel: WorkoutDetailEvidenceModel {
        WorkoutDetailEvidenceModel(summary: displayedSummary)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                statGrid
                effortCard
                topCueCard
                setList
                deleteWorkoutButton
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
        .sheet(item: $evidenceRequest) { request in
            WorkoutEvidenceTimelineSheet(
                request: request,
                model: evidenceModel
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete Workout?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Workout", role: .destructive) {
                deleteWorkout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the workout from your visible history.")
        }
        .preferredColorScheme(.dark)
        .task(id: summary.id) {
            await loadDetailIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(displayedSummary.mode.displayName.uppercased())
                .font(.system(size: 12, weight: .black))
                .tracking(1.4)
                .foregroundStyle(Theme.Colors.accent)

            Text(displayedSummary.title)
                .header(size: 34)

            HStack(spacing: Theme.Spacing.sm) {
                Text(displayedSummary.endedAt, style: .date)
                Text(displayedSummary.endedAt, style: .time)
                Text(displayedSummary.coach.coachName)
            }
            .font(.system(size: 12, weight: .heavy))
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.textSecondary)

            if let goal = displayedSummary.goal {
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
            DetailStatCard(label: "Duration", value: durationText(displayedSummary.durationSeconds))
            DetailStatCard(label: "Reps", value: "\(displayedSummary.totalReps)")
            DetailStatCard(label: "Hold", value: durationText(displayedSummary.totalHoldSeconds))
            DetailStatCard(label: "Avg Form", value: formText)
            if let completionPercent = displayedSummary.completionPercent {
                DetailStatCard(
                    label: "Complete",
                    value: "\(Int((completionPercent * 100).rounded()))%"
                )
            }
        }
    }

    private var effortCard: some View {
        Button {
            HapticsEngine.shared.buttonTap()
            evidenceRequest = .effort
        } label: {
            DetailInfoCard(
                systemImage: "bolt.heart.fill",
                title: "Effort",
                tint: Theme.Colors.accent,
                bodyText: displayedSummary.effortSummary,
                footerText: "Tap for evidence"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show effort evidence")
    }

    @ViewBuilder
    private var topCueCard: some View {
        if let cue = displayedSummary.topCue {
            Button {
                HapticsEngine.shared.buttonTap()
                evidenceRequest = .topCue
            } label: {
                DetailInfoCard(
                    systemImage: "lightbulb.fill",
                    title: "Top Cue",
                    tint: cueTint(cue.severity),
                    bodyText: cue.cueMessage,
                    footerText: "Tap for evidence"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show top cue evidence")
        }
    }

    private var setList: some View {
        let sets = evidenceModel.setEvidence
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Exercises Logged")
                .font(.system(size: 18, weight: .black))
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textPrimary)

            if sets.isEmpty {
                Text("No exercise evidence was saved for this session.")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(sets.enumerated()), id: \.element.id) { index, setEvidence in
                        ExerciseSetDetailRow(evidence: setEvidence)

                        if index < sets.count - 1 {
                            Divider()
                                .background(Theme.Colors.divider)
                        }
                    }
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

    private var deleteWorkoutButton: some View {
        Button(role: .destructive) {
            HapticsEngine.shared.buttonTap()
            isShowingDeleteConfirmation = true
        } label: {
            Label("Delete Workout", systemImage: "trash.fill")
        }
        .buttonStyle(PrimaryCTAStyle(destructive: true))
        .accessibilityLabel("Delete workout")
    }

    private var formText: String {
        guard let average = displayedSummary.averageFormScore else { return "N/A" }
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

    private func deleteWorkout() {
        Task {
            guard await historyStore.deleteSummary(id: displayedSummary.id) else { return }
            _ = await insightStore.invalidateInsightsReferencingWorkout(id: displayedSummary.id)
            await trophyStore.updateAll(
                history: historyStore.summaries,
                calibrationStatus: calibrationStore.status
            )
            HapticsEngine.shared.successRipple()
            dismiss()
        }
    }

    private func loadDetailIfNeeded() async {
        guard displayedSummary.exerciseSummaries.isEmpty else { return }
        detailedSummary = await historyStore.loadDetailedSummaryIfNeeded(id: summary.id)
    }
}

private enum EvidenceSheetRequest: String, Identifiable {
    case effort
    case topCue

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .effort:
            return "Effort Evidence"
        case .topCue:
            return "Top Cue Evidence"
        }
    }

    var subtitle: String {
        switch self {
        case .effort:
            return "Cue and rep-quality events behind the session effort read."
        case .topCue:
            return "The chronological cue and rep-quality trail behind the top cue."
        }
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
    let footerText: String?

    init(
        systemImage: String,
        title: String,
        tint: Color,
        bodyText: String,
        footerText: String? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.tint = tint
        self.bodyText = bodyText
        self.footerText = footerText
    }

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

            if let footerText {
                Label(footerText, systemImage: "chevron.right.circle.fill")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(tint.opacity(0.9))
                    .padding(.top, Theme.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let evidence: WorkoutDetailEvidenceModel.SetEvidence

    private var summary: ExerciseSetSummary {
        evidence.summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            topCueBlock

            if evidence.hasRepEvidence {
                RepFormSparklineView(samples: evidence.formSamples)
                    .accessibilityIdentifier("workout-detail-sparkline-\(evidence.id)")
                trendBadges
            }

            EvidenceMetricPillRow(evidence: evidence)
            cueComparison
            restIndicators
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var header: some View {
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
    }

    @ViewBuilder
    private var topCueBlock: some View {
        if let topCue = evidence.topCue {
            Label {
                Text(topCue)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "megaphone.fill")
                    .foregroundStyle(Theme.Colors.accent)
            }
            .accessibilityLabel("Most repeated cue: \(topCue)")
        }
    }

    @ViewBuilder
    private var trendBadges: some View {
        let badges = trendBadgeData
        if !badges.isEmpty {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(badges) { badge in
                    TrendBadge(label: badge.label, systemImage: badge.systemImage, tint: badge.tint)
                        .accessibilityIdentifier(badge.accessibilityIdentifier)
                }
            }
        }
    }

    @ViewBuilder
    private var cueComparison: some View {
        if evidence.hasCueComparison {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                spacing: Theme.Spacing.sm
            ) {
                if let worstCue = evidence.worstCue {
                    CueComparisonChip(
                        label: "Worst cue",
                        value: worstCue,
                        tint: Theme.Colors.danger
                    )
                }
                if let bestCue = evidence.bestCue {
                    CueComparisonChip(
                        label: "Best cue",
                        value: bestCue,
                        tint: Theme.Colors.positive
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var restIndicators: some View {
        if !evidence.restIndicators.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(evidence.restIndicators) { indicator in
                    RestIndicatorRow(indicator: indicator)
                }
            }
        }
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
        if let score = evidence.averageFormScore {
            pieces.append("\(Int(score.rounded()))% form")
        }
        return pieces.isEmpty ? "Logged" : pieces.joined(separator: " / ")
    }

    private var trendBadgeData: [SetTrendBadgeData] {
        var badges: [SetTrendBadgeData] = []
        if let breakdownRepIndex = evidence.breakdownRepIndex {
            badges.append(
                SetTrendBadgeData(
                    label: "Drop after rep \(breakdownRepIndex)",
                    systemImage: "arrow.down.right.circle.fill",
                    tint: Theme.Colors.danger,
                    accessibilityIdentifier: "workout-detail-breakdown-badge-\(evidence.id)"
                )
            )
        }
        if let improvementRepIndex = evidence.improvementRepIndex {
            badges.append(
                SetTrendBadgeData(
                    label: "Improved after rep \(improvementRepIndex)",
                    systemImage: "arrow.up.right.circle.fill",
                    tint: Theme.Colors.positive,
                    accessibilityIdentifier: "workout-detail-improvement-badge-\(evidence.id)"
                )
            )
        }
        return badges
    }

    private var statusIcon: String {
        if summary.skipped {
            return "forward.fill"
        }
        switch evidence.qualityTrend {
        case .improved:
            return "arrow.up"
        case .faded:
            return "arrow.down"
        case .stable, .unknown:
            return "checkmark"
        }
    }

    private var statusTint: Color {
        if summary.skipped {
            return Theme.Colors.accent
        }
        switch evidence.qualityTrend {
        case .improved:
            return Theme.Colors.positive
        case .faded:
            return Theme.Colors.danger
        case .stable, .unknown:
            return Theme.Colors.positive
        }
    }
}

private struct SetTrendBadgeData: Identifiable {
    let label: String
    let systemImage: String
    let tint: Color
    let accessibilityIdentifier: String

    var id: String {
        label
    }
}

private struct RepFormSparklineView: View {
    let samples: [WorkoutDetailEvidenceModel.FormSample]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Per-Rep Form")
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Spacer()

                if let first = samples.first,
                   let last = samples.last {
                    Text("Rep \(first.repIndex) - Rep \(last.repIndex)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            Canvas { context, size in
                guard !samples.isEmpty,
                      size.width > 0,
                      size.height > 0
                else { return }

                let count = CGFloat(samples.count)
                let gap = count > 1 ? min(8, size.width / count * 0.22) : 0
                let totalGap = gap * max(count - 1, 0)
                let barWidth = max((size.width - totalGap) / count, 3)
                let maxHeight = size.height
                var trendPath = Path()

                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) * (barWidth + gap)
                    let normalizedScore = CGFloat(max(0, min(sample.score, 100))) / 100
                    let barHeight = max(maxHeight * normalizedScore, 5)
                    let rect = CGRect(
                        x: x,
                        y: maxHeight - barHeight,
                        width: barWidth,
                        height: barHeight
                    )
                    let path = Path(
                        roundedRect: rect,
                        cornerRadius: min(barWidth / 2, 5)
                    )
                    context.fill(path, with: .color(Self.scoreColor(sample.score)))

                    let point = CGPoint(
                        x: rect.midX,
                        y: maxHeight - barHeight
                    )
                    if index == 0 {
                        trendPath.move(to: point)
                    } else {
                        trendPath.addLine(to: point)
                    }
                }

                if samples.count > 1 {
                    context.stroke(
                        trendPath,
                        with: .color(Theme.Colors.textPrimary.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .frame(height: 72)
            .accessibilityLabel("Per-rep form sparkline")
            .accessibilityValue(samples.map { "Rep \($0.repIndex), \($0.score)%" }.joined(separator: ", "))
        }
    }

    private static func scoreColor(_ score: Int) -> Color {
        switch score {
        case 90...:
            return Theme.Colors.positive
        case 80..<90:
            return Theme.Colors.accent
        case 70..<80:
            return Theme.Colors.textSecondary
        default:
            return Theme.Colors.danger
        }
    }
}

private struct EvidenceMetricPillRow: View {
    let evidence: WorkoutDetailEvidenceModel.SetEvidence

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                EvidenceMetricPill(
                    label: "Avg form",
                    value: averageText,
                    tint: Theme.Colors.accent
                )
                EvidenceMetricPill(
                    label: "Excellent",
                    value: "\(evidence.excellentFormReps) reps",
                    tint: Theme.Colors.positive
                )
                EvidenceMetricPill(
                    label: "Good",
                    value: "\(evidence.goodFormReps) reps",
                    tint: Theme.Colors.accent
                )
                EvidenceMetricPill(
                    label: "Total scored",
                    value: "\(evidence.totalScoredReps) reps",
                    tint: Theme.Colors.textSecondary
                )
            }
            .padding(.vertical, Theme.Spacing.xxs)
        }
    }

    private var averageText: String {
        guard let average = evidence.averageFormScore else { return "N/A" }
        return "\(Int(average.rounded()))%"
    }
}

private struct EvidenceMetricPill: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text(value)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 92, alignment: .leading)
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.34), lineWidth: 1)
        )
    }
}

private struct TrendBadge: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.system(size: 11, weight: .black))
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.sm)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            )
    }
}

private struct CueComparisonChip: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label)
                .font(.system(size: 10, weight: .black))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

private struct RestIndicatorRow: View {
    let indicator: WorkoutDetailEvidenceModel.RestIndicator

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(indicator.title)
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(tint)
                Text(indicator.rationale)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(tint)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }

    private var icon: String {
        switch indicator.kind {
        case .extended:
            return "timer.circle.fill"
        case .skipped:
            return "forward.circle.fill"
        }
    }

    private var tint: Color {
        switch indicator.kind {
        case .extended:
            return Theme.Colors.accent
        case .skipped:
            return Theme.Colors.danger
        }
    }
}

private struct WorkoutEvidenceTimelineSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: EvidenceSheetRequest
    let model: WorkoutDetailEvidenceModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header

                if model.timelineEvents.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(model.timelineEvents) { event in
                            TimelineEventRow(event: event)
                        }
                    }
                }
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
                    Text("Done")
                        .font(.system(size: 12, weight: .black))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .background(Theme.Colors.background)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Evidence")
                .font(.system(size: 12, weight: .black))
                .tracking(1.3)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.accent)

            Text(request.title)
                .header(size: 32)

            Text(request.subtitle)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("No cue or rep-quality events were saved for this session.")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }
}

private struct TimelineEventRow: View {
    let event: WorkoutDetailEvidenceModel.TimelineEvent

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            VStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Theme.Colors.background)
                    .frame(width: 28, height: 28)
                    .background(tint)
                    .clipShape(Circle())

                Rectangle()
                    .fill(Theme.Colors.divider)
                    .frame(width: 2, height: 52)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(elapsedText(event.secondsIntoSession))
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)

                    Text(kindLabel)
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(tint)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(event.title)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = event.detail {
                        Text(detail)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(contextText)
                        .font(.system(size: 11, weight: .heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Colors.divider, lineWidth: 1)
                )
            }
        }
    }

    private var icon: String {
        switch event.kind {
        case .cue:
            return "quote.bubble.fill"
        case .repQuality:
            return "figure.strengthtraining.traditional"
        }
    }

    private var kindLabel: String {
        switch event.kind {
        case .cue:
            return "Cue event"
        case .repQuality:
            return "Rep quality"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .cue(let severity):
            switch severity {
            case .info:
                return Theme.Colors.positive
            case .warning:
                return Theme.Colors.accent
            case .critical:
                return Theme.Colors.danger
            }
        case .repQuality(let score):
            guard let score else { return Theme.Colors.textSecondary }
            switch score {
            case 90...:
                return Theme.Colors.positive
            case 80..<90:
                return Theme.Colors.accent
            case 70..<80:
                return Theme.Colors.textSecondary
            default:
                return Theme.Colors.danger
            }
        }
    }

    private var contextText: String {
        var pieces = [event.exerciseType.displayName]
        if let setIndex = event.setIndex {
            pieces.append("Set \(setIndex + 1)")
        }
        if let repIndex = event.repIndex {
            pieces.append("Rep \(repIndex)")
        }
        if let secondsIntoSet = event.secondsIntoSet {
            pieces.append("\(elapsedText(secondsIntoSet)) into set")
        }
        return pieces.joined(separator: " / ")
    }

    private func elapsedText(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded()), 0)
        guard seconds >= 60 else { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private enum WorkoutDetailSheetPreviewData {
    static let now = Date(timeIntervalSince1970: 1_777_000_000)

    static var cleanSummary: WorkoutSessionSummary {
        let repEvents = makeRepEvents(
            scores: [92, 93, 94, 92, 95, 94],
            start: now.addingTimeInterval(-220)
        )
        let quality = SetQualitySummary.build(repQualityEvents: repEvents)
        let set = ExerciseSetSummary(
            exerciseType: .pushup,
            setIndex: 0,
            target: .reps(6),
            achievedReps: 6,
            achievedHoldSeconds: 0,
            averageFormScore: quality.averageFormScore,
            qualitySummary: quality,
            repQualityEvents: repEvents,
            completedAt: now.addingTimeInterval(-120),
            durationSeconds: 100,
            peakEffort: 0.52,
            bestCue: "Core stayed braced"
        )

        return WorkoutSessionSummary(
            mode: .plannedWorkout,
            planId: UUID(uuidString: "00000000-0000-0000-0000-000000000101"),
            title: "Clean Upper Session",
            goal: "Keep each rep crisp.",
            coach: .good,
            startedAt: now.addingTimeInterval(-360),
            endedAt: now,
            durationSeconds: 360,
            totalReps: 6,
            totalHoldSeconds: 0,
            averageFormScore: quality.averageFormScore,
            completionPercent: 1,
            exerciseSummaries: [set],
            topCue: nil,
            effortSummary: "Peak effort reached 52%. Solid working intensity.",
            structuredEffortSummary: StructuredEffortSummary.build(repQualityEvents: repEvents, peakEffort: 0.52),
            createdAt: now
        )
    }

    static var fadedSummary: WorkoutSessionSummary {
        let repEvents = makeRepEvents(
            scores: [94, 93, 91, 88, 76, 72],
            cueMessage: "Keep your chest up",
            cueSeverity: .warning,
            start: now.addingTimeInterval(-260)
        )
        let cueEvents = [
            CueEvent(
                timestamp: now.addingTimeInterval(-150),
                exerciseType: .squat,
                cueMessage: "Keep your chest up",
                severity: .warning,
                setIndex: 0,
                repIndex: 5,
                secondsIntoSet: 68,
                formScoreAtEvent: 76
            )
        ]
        let quality = SetQualitySummary.build(
            repQualityEvents: repEvents,
            cueEvents: cueEvents
        )
        let set = ExerciseSetSummary(
            exerciseType: .squat,
            setIndex: 0,
            target: .reps(6),
            achievedReps: 6,
            achievedHoldSeconds: 0,
            averageFormScore: quality.averageFormScore,
            cueEvents: cueEvents,
            restExtended: true,
            qualitySummary: quality,
            repQualityEvents: repEvents,
            completedAt: now.addingTimeInterval(-100),
            durationSeconds: 160,
            peakEffort: 0.84,
            bestCue: "Depth stayed strong early",
            worstCue: "Chest dropped late"
        )

        return WorkoutSessionSummary(
            mode: .plannedWorkout,
            planId: UUID(uuidString: "00000000-0000-0000-0000-000000000102"),
            title: "Faded Squat Session",
            goal: "Hold posture as fatigue rises.",
            coach: .good,
            startedAt: now.addingTimeInterval(-420),
            endedAt: now,
            durationSeconds: 420,
            totalReps: 6,
            totalHoldSeconds: 0,
            averageFormScore: quality.averageFormScore,
            completionPercent: 1,
            exerciseSummaries: [set],
            topCue: cueEvents.first,
            effortSummary: "Peak effort hit 84%. High strain captured near the end.",
            structuredEffortSummary: StructuredEffortSummary.build(repQualityEvents: repEvents, peakEffort: 0.84),
            createdAt: now
        )
    }

    private static func makeRepEvents(
        scores: [Int],
        cueMessage: String? = nil,
        cueSeverity: CoachCue.Severity? = nil,
        start: Date
    ) -> [RepQualityEvent] {
        scores.enumerated().map { index, score in
            RepQualityEvent(
                exerciseType: cueMessage == nil ? .pushup : .squat,
                setIndex: 0,
                repIndex: index + 1,
                timestamp: start.addingTimeInterval(TimeInterval((index + 1) * 10)),
                secondsIntoSet: TimeInterval((index + 1) * 10),
                formScore: score,
                formGrade: FormScore.Grade.from(score: score).rawValue,
                cueMessageNearRep: index >= 3 ? cueMessage : nil,
                cueSeverityNearRep: index >= 3 ? cueSeverity : nil,
                effortAtRep: Double(45 + index * 7) / 100
            )
        }
    }
}

#Preview("Clean Evidence") {
    WorkoutDetailSheetView(summary: WorkoutDetailSheetPreviewData.cleanSummary)
        .environmentObject(CalibrationStore())
        .environmentObject(WorkoutHistoryStore())
        .environmentObject(TrophyStore())
        .environmentObject(InsightStore())
}

#Preview("Faded Evidence") {
    WorkoutDetailSheetView(summary: WorkoutDetailSheetPreviewData.fadedSummary)
        .environmentObject(CalibrationStore())
        .environmentObject(WorkoutHistoryStore())
        .environmentObject(TrophyStore())
        .environmentObject(InsightStore())
}
