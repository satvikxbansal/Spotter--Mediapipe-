import SwiftUI

struct InsightEvidenceSheetView: View {
    let insight: AIInsight
    let summaries: [WorkoutSessionSummary]
    let onEngagement: (InsightEngagementKind) -> Void

    @State private var selectedSummary: WorkoutSessionSummary?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                message
                basedOnSection
                InsightEngagementPrompt(onSelect: onEngagement)
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Colors.background)
        .sheet(item: $selectedSummary) { summary in
            WorkoutDetailSheetView(summary: summary)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                confidencePill
            }

            Text(insight.headline)
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var message: some View {
        Text(insight.message)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var basedOnSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Based on")
                .font(.system(size: 13, weight: .black))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textTertiary)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(insight.evidence) { evidence in
                    if let summary = summary(for: evidence) {
                        Button {
                            HapticsEngine.shared.buttonTap()
                            selectedSummary = summary
                        } label: {
                            InsightEvidenceRow(
                                evidence: evidence,
                                summary: summary,
                                isTappable: true
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        InsightEvidenceRow(
                            evidence: evidence,
                            summary: nil,
                            isTappable: false
                        )
                    }
                }
            }
        }
    }

    private var confidencePill: some View {
        Text("Confidence: \(confidenceLabel)")
            .font(.system(size: 11, weight: .black))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.background)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(tint)
            .clipShape(Capsule())
    }

    private var confidenceLabel: String {
        insight.confidence >= 0.82 ? "high" : "medium"
    }

    private var tint: Color {
        switch insight.severity {
        case .positive:
            return Theme.Colors.positive
        case .neutral:
            return Theme.Colors.accent
        case .caution, .important:
            return Theme.Colors.danger
        }
    }

    private var iconName: String {
        switch insight.type {
        case .growthCelebration, .dayOverDayTrend, .consistency:
            return "chart.line.uptrend.xyaxis"
        case .formCorrection, .safety:
            return "exclamationmark.triangle.fill"
        case .recovery:
            return "timer"
        case .trophyProgress:
            return "trophy.fill"
        default:
            return "brain.head.profile"
        }
    }

    private func summary(for evidence: InsightEvidence) -> WorkoutSessionSummary? {
        guard let workoutId = evidence.workoutId else { return nil }
        return summaries.first { $0.id == workoutId }
    }
}

struct InsightEvidenceButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            HapticsEngine.shared.buttonTap()
            action()
        } label: {
            Label("Evidence", systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 11, weight: .black))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.accent)
                .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open evidence")
    }
}

private struct InsightEvidenceRow: View {
    let evidence: InsightEvidence
    let summary: WorkoutSessionSummary?
    let isTappable: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: isTappable ? "chevron.right.circle.fill" : "info.circle.fill")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(isTappable ? Theme.Colors.accent : Theme.Colors.textTertiary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(rowTitle)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(rowDetail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var rowTitle: String {
        let exercise = evidence.exerciseType?.displayName ?? summary?.primaryExerciseType?.displayName ?? "Workout evidence"
        guard let summary else { return exercise }
        return "\(dateText(summary.endedAt)) · \(exercise)"
    }

    private var rowDetail: String {
        var pieces: [String] = []
        if let setIndex = evidence.setIndex {
            pieces.append("Set \(setIndex + 1)")
        }
        if let repIndex = evidence.repIndex {
            pieces.append("Rep \(repIndex)")
        }
        pieces.append(evidence.value)
        if let comparison = evidence.comparison {
            pieces.append(comparison)
        }
        return pieces.joined(separator: " / ")
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
