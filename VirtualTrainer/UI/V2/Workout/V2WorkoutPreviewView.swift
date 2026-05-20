import SwiftUI

nonisolated enum V2WorkoutPreviewPresentation {
    static let supportedActionTitles = [
        "Adjust",
        "Start Workout",
        "Coach Bennett",
        "Coach Fletcher"
    ]

    static func targetChip(for exercise: PlannedExercise) -> String {
        guard let firstTarget = exercise.sets.first?.target else { return "No target" }
        if exercise.sets.allSatisfy({ $0.target == firstTarget }) {
            return "\(max(exercise.sets.count, 0)) x \(firstTarget.formattedText)"
        }

        return exercise.sets
            .map { "Set \($0.setIndex): \($0.target.formattedText)" }
            .joined(separator: " / ")
    }

    static func cameraText(for position: CameraPosition) -> String {
        WorkoutPreviewState.cameraText(for: position)
    }
}

struct V2WorkoutPreviewView: View {
    let theme: SpotterThemeOption
    let plan: WorkoutPlanV2
    let selectedCoach: CoachPersonality
    let hasUserEdits: Bool
    let exerciseCount: Int
    let cameraSequenceText: String
    let cameraSwitchCount: Int
    let cameraSwitchLimit: Int
    let statusMessage: String?
    let planInsight: AIInsight?
    let canSaveDefaultCoach: Bool
    let canAdjust: (PlanExerciseIdentifier) -> Bool
    let onAdjust: (PlanExerciseIdentifier) -> Void
    let onSelectCoach: (CoachPersonality) -> Void
    let onSaveDefaultCoach: () -> Void
    let onPlanInsightAppeared: (AIInsight) -> Void
    let onOpenInsightEvidence: (AIInsight) -> Void
    let onInsightEngagement: (AIInsight, InsightEngagementKind) -> Void
    let onStart: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                hero
                coachSelector
                planInsightSection
                cameraSetupCard
                exerciseSection
            }
            .padding(SpotterV2.Spacing.xl)
            .padding(.bottom, 112)
        }
        .background(SpotterV2.Tokens.background.ignoresSafeArea())
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.lg) {
            HStack(alignment: .center, spacing: SpotterV2.Spacing.sm) {
                V2StatusPill(
                    theme: theme,
                    label: selectedCoach.coachName.replacingOccurrences(of: "Coach ", with: "")
                )

                V2StatusPill(theme: theme, label: "\(plan.estimatedMinutes) min")

                if hasUserEdits {
                    V2StatusPill(theme: theme, label: "Adjusted")
                }
            }

            VStack(alignment: .leading, spacing: SpotterV2.Spacing.sm) {
                Text(plan.title)
                    .font(SpotterV2Typography.display(size: 44))
                    .fontWidth(.compressed)
                    .italic()
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(3)
                    .minimumScaleFactor(0.58)

                Text(plan.subtitle)
                    .font(SpotterV2Typography.body(size: 16, weight: .semibold))
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SpotterV2.Spacing.sm),
                    GridItem(.flexible(), spacing: SpotterV2.Spacing.sm)
                ],
                spacing: SpotterV2.Spacing.sm
            ) {
                V2PreviewChip(theme: theme, title: "Duration", value: "\(plan.estimatedMinutes) min", systemImage: "clock.fill")
                V2PreviewChip(theme: theme, title: "Focus", value: plan.goal, systemImage: "scope")
                V2PreviewChip(theme: theme, title: "Difficulty", value: plan.difficulty.rawValue.capitalized, systemImage: "chart.bar.fill")
                V2PreviewChip(theme: theme, title: "Moves", value: "\(exerciseCount)", systemImage: "figure.strengthtraining.traditional")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coachSelector: some View {
        V2Card(
            theme: theme,
            radius: SpotterV2.Radius.lg,
            borderColor: SpotterV2.Tokens.border.opacity(0.72)
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                V2SectionHeader(
                    title: "Coach",
                    trailingTitle: canSaveDefaultCoach ? "Save default" : nil,
                    trailingSystemImage: "checkmark.circle",
                    trailingAction: canSaveDefaultCoach ? onSaveDefaultCoach : nil
                )

                HStack(spacing: SpotterV2.Spacing.sm) {
                    ForEach(CoachPersonality.allCases) { coach in
                        Button {
                            onSelectCoach(coach)
                        } label: {
                            V2CoachPill(
                                theme: theme,
                                coach: coach,
                                isSelected: selectedCoach == coach
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use \(coach.coachName)")
                        .accessibilityValue(selectedCoach == coach ? "Selected" : "")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var planInsightSection: some View {
        if let planInsight {
            V2InsightCard(
                theme: theme,
                eyebrow: "Plan insight",
                headline: planInsight.headline,
                bodyText: planInsight.message,
                onOpenEvidence: {
                    onOpenInsightEvidence(planInsight)
                },
                onHelpful: {
                    onInsightEngagement(planInsight, .helpful)
                },
                onNotHelpful: {
                    onInsightEngagement(planInsight, .notHelpful)
                }
            )
            .onAppear {
                onPlanInsightAppeared(planInsight)
            }
        } else {
            V2InsightCard(
                theme: theme,
                eyebrow: "Why this plan",
                headline: "Built for your next session.",
                bodyText: plan.planReason
            )
        }
    }

    private var cameraSetupCard: some View {
        V2Card(
            theme: theme,
            radius: SpotterV2.Radius.lg,
            borderColor: SpotterV2.Tokens.border.opacity(0.62)
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                V2SectionHeader(
                    title: "Camera Setup",
                    trailingTitle: "\(cameraSwitchCount)/\(cameraSwitchLimit) switches",
                    trailingSystemImage: "arrow.triangle.2.circlepath.camera"
                )

                HStack(alignment: .center, spacing: SpotterV2.Spacing.md) {
                    Image(systemName: cameraSwitchCount > 0 ? "arrow.triangle.2.circlepath.camera" : "camera.viewfinder")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(SpotterV2.Tokens.primary(theme))
                        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))

                    VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                        Text("Session Order")
                            .font(SpotterV2Typography.caption())
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        Text(cameraSequenceText)
                            .font(SpotterV2Typography.heading(size: 18))
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.foreground)
                            .lineLimit(2)
                            .minimumScaleFactor(0.68)
                    }

                    Spacer(minLength: SpotterV2.Spacing.xs)

                    V2StatusPill(
                        theme: theme,
                        label: cameraSwitchCount > 0 ? "Mixed Views" : "Single View"
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera setup, \(cameraSequenceText), \(cameraSwitchCount) of \(cameraSwitchLimit) switches")
    }

    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            V2SectionHeader(
                title: "Workout Plan",
                trailingTitle: "\(exerciseCount) moves",
                trailingSystemImage: "list.bullet"
            )

            ForEach(Array(plan.blocks.enumerated()), id: \.offset) { blockIndex, block in
                VStack(alignment: .leading, spacing: SpotterV2.Spacing.sm) {
                    Text(block.title)
                        .font(SpotterV2Typography.caption())
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.primary(theme))

                    VStack(spacing: SpotterV2.Spacing.sm) {
                        ForEach(Array(block.exercises.enumerated()), id: \.offset) { exerciseIndex, exercise in
                            let exerciseId = PlanExerciseIdentifier(
                                blockIndex: blockIndex,
                                exerciseIndex: exerciseIndex
                            )
                            let rowIndex = rowNumber(blockIndex: blockIndex, exerciseIndex: exerciseIndex)
                            Button {
                                onAdjust(exerciseId)
                            } label: {
                                V2ExerciseRow(
                                    theme: theme,
                                    index: rowIndex,
                                    name: exercise.exerciseType.displayName,
                                    target: V2WorkoutPreviewPresentation.targetChip(for: exercise),
                                    subtitle: exercise.coachingFocus,
                                    ctaTitle: canAdjust(exerciseId) ? "Adjust" : "Locked",
                                    systemImage: "slider.horizontal.3"
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!canAdjust(exerciseId))
                            .accessibilityLabel("Adjust \(exercise.exerciseType.displayName)")
                            .accessibilityHint(targetAccessibilityText(for: exercise))
                        }
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: SpotterV2.Spacing.sm) {
            if let statusMessage {
                Text(statusMessage)
                    .font(SpotterV2Typography.body(size: 12, weight: .bold))
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            V2CTAButton(
                title: "Start Workout",
                systemImage: "play.fill",
                theme: theme,
                action: onStart
            )
        }
        .padding(.horizontal, SpotterV2.Spacing.xl)
        .padding(.top, SpotterV2.Spacing.md)
        .padding(.bottom, SpotterV2.Spacing.sm)
        .background(SpotterV2.Tokens.background)
    }

    private func rowNumber(blockIndex: Int, exerciseIndex: Int) -> Int {
        var count = 0
        for index in plan.blocks.indices {
            if index == blockIndex { return count + exerciseIndex + 1 }
            count += plan.blocks[index].exercises.count
        }
        return exerciseIndex + 1
    }

    private func targetAccessibilityText(for exercise: PlannedExercise) -> String {
        "Target \(V2WorkoutPreviewPresentation.targetChip(for: exercise)), camera \(V2WorkoutPreviewPresentation.cameraText(for: exercise.cameraPosition))"
    }
}

private struct V2PreviewChip: View {
    let theme: SpotterThemeOption
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: SpotterV2.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.primary(theme))
                .frame(width: 32, height: 32)
                .background(SpotterV2.Tokens.secondary)
                .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xs))

            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                Text(title)
                    .font(SpotterV2Typography.caption())
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                Text(value)
                    .font(SpotterV2Typography.body(size: 13, weight: .black))
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: SpotterV2.Spacing.xs)
        }
        .padding(SpotterV2.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(SpotterV2.Tokens.card)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                .stroke(SpotterV2.Tokens.border.opacity(0.48), lineWidth: 1)
        )
    }
}

private struct V2CoachPill: View {
    let theme: SpotterThemeOption
    let coach: CoachPersonality
    let isSelected: Bool

    var body: some View {
        HStack(spacing: SpotterV2.Spacing.sm) {
            Image(coach.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.border.opacity(0.45),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                Text(coach.coachName.replacingOccurrences(of: "Coach ", with: ""))
                    .font(SpotterV2Typography.heading(size: 14))
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                Text(coach.displayName)
                    .font(SpotterV2Typography.caption(weight: .bold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: SpotterV2.Spacing.xs)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
            }
        }
        .padding(SpotterV2.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(isSelected ? SpotterV2.Tokens.primary(theme).opacity(0.14) : SpotterV2.Tokens.secondary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.border.opacity(0.45),
                    lineWidth: isSelected ? 2 : 1
                )
        )
    }
}

#if DEBUG
private struct V2WorkoutPreviewContentPreview: View {
    let theme: SpotterThemeOption

    private var plan: WorkoutPlanV2 {
        WorkoutPlan.MockData.fullBody.convertedToV2(
            goal: "Full-body control with clean depth.",
            difficulty: .intermediate,
            coach: .good,
            planReason: "You have enough recent lower-body work to push volume while keeping movement quality visible.",
            source: .generatedLocal
        )
    }

    var body: some View {
        NavigationStack {
            V2WorkoutPreviewView(
                theme: theme,
                plan: plan,
                selectedCoach: .good,
                hasUserEdits: true,
                exerciseCount: plan.blocks.flatMap(\.exercises).count,
                cameraSequenceText: "Front -> Side",
                cameraSwitchCount: 1,
                cameraSwitchLimit: 2,
                statusMessage: "Squat target updated.",
                planInsight: nil,
                canSaveDefaultCoach: true,
                canAdjust: { _ in true },
                onAdjust: { _ in },
                onSelectCoach: { _ in },
                onSaveDefaultCoach: {},
                onPlanInsightAppeared: { _ in },
                onOpenInsightEvidence: { _ in },
                onInsightEngagement: { _, _ in },
                onStart: {}
            )
        }
    }
}

private struct V2WorkoutPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2WorkoutPreviewContentPreview(theme: theme)
                    .previewDisplayName("\(theme.displayName) - SE")
                    .previewDevice("iPhone SE (3rd generation)")
                V2WorkoutPreviewContentPreview(theme: theme)
                    .previewDisplayName("\(theme.displayName) - Pro Max")
                    .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}
#endif
