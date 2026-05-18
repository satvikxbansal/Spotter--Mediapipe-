import SwiftUI

struct V2OnboardingObjectiveView: View {
    let onBack: () -> Void
    let onNext: () -> Void

    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        V2OnboardingPage(
            theme: themeStore.selectedTheme,
            activeStep: 3,
            stepText: "03 / 04",
            title: "Define your",
            accentTitle: "objective",
            subtitle: "Your plan adjusts based on your focus.",
            titleSize: 38,
            canContinue: onboardingStore.canContinue(from: .goalEquipment),
            onBack: onBack,
            onNext: onNext
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxl) {
                primaryGoalSection
                fitnessLevelSection
                equipmentSection
                limitationsSection
                sessionLengthSection
                daysPerWeekSection
            }
        }
        .accessibilityIdentifier("V2OnboardingObjectiveView")
    }

    private var primaryGoalSection: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            V2FieldLabel(title: "Primary Focus")
            ForEach(FitnessGoal.allCases) { goal in
                V2SelectorTile(
                    theme: themeStore.selectedTheme,
                    title: goal.displayName,
                    subtitle: goal.subtitle,
                    systemImage: systemImage(for: goal),
                    isSelected: onboardingStore.draft.primaryGoal == goal,
                    minHeight: 96
                ) {
                    onboardingStore.draft.primaryGoal = goal
                }
            }
        }
    }

    private var fitnessLevelSection: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            V2FieldLabel(title: "Fitness Level")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SpotterV2.Spacing.md),
                    GridItem(.flexible(), spacing: SpotterV2.Spacing.md)
                ],
                spacing: SpotterV2.Spacing.md
            ) {
                ForEach(FitnessLevel.allCases) { level in
                    V2CompactSelectorTile(
                        theme: themeStore.selectedTheme,
                        title: level.displayName,
                        systemImage: level == .beginner ? "figure.walk" : "bolt.fill",
                        isSelected: onboardingStore.draft.fitnessLevel == level
                    ) {
                        onboardingStore.draft.fitnessLevel = level
                    }
                }
            }
        }
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            V2FieldLabel(title: "Equipment Available")
            V2FlowLayout(spacing: SpotterV2.Spacing.md) {
                ForEach(EquipmentOption.allCases) { option in
                    V2TagToggle(
                        theme: themeStore.selectedTheme,
                        title: option.displayName,
                        isSelected: onboardingStore.draft.equipment.contains(option)
                    ) {
                        onboardingStore.toggleEquipment(option)
                    }
                }
            }
        }
    }

    private var limitationsSection: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            V2FieldLabel(title: "Limitations")
            VStack(spacing: SpotterV2.Spacing.sm) {
                ForEach(PhysicalLimitation.allCases) { limitation in
                    V2CheckRow(
                        theme: themeStore.selectedTheme,
                        title: limitation.displayName,
                        subtitle: limitationSubtitle(limitation),
                        isSelected: onboardingStore.draft.limitations.contains(limitation)
                    ) {
                        onboardingStore.toggleLimitation(limitation)
                    }
                }
            }
        }
    }

    private var sessionLengthSection: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            V2FieldLabel(title: "Daily Plan Length")
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SpotterV2.Spacing.md),
                    GridItem(.flexible(), spacing: SpotterV2.Spacing.md),
                    GridItem(.flexible(), spacing: SpotterV2.Spacing.md)
                ],
                spacing: SpotterV2.Spacing.md
            ) {
                ForEach(PlanSessionLength.dailyPreferenceCases) { length in
                    V2CompactSelectorTile(
                        theme: themeStore.selectedTheme,
                        title: length.displayName,
                        systemImage: "clock.fill",
                        isSelected: onboardingStore.draft.preferredSessionLength == length
                    ) {
                        onboardingStore.draft.preferredSessionLength = length
                    }
                }
            }
        }
    }

    private var daysPerWeekSection: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            V2FieldLabel(title: "Workout Days Per Week")

            HStack(spacing: SpotterV2.Spacing.md) {
                stepperButton(systemImage: "minus") {
                    updateDays(delta: -1)
                }

                VStack(spacing: SpotterV2.Spacing.xxs) {
                    Text("\(currentWorkoutDays)")
                        .font(SpotterV2Typography.mono(size: 54, weight: .black))
                        .italic()
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .monospacedDigit()
                    Text(currentWorkoutDays == 1 ? "day" : "days")
                        .font(SpotterV2Typography.caption())
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.primary(themeStore.selectedTheme))
                }
                .frame(maxWidth: .infinity, minHeight: 116)
                .background(SpotterV2.Tokens.card)
                .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xl))
                .overlay(
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.xl)
                        .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(currentWorkoutDays) workout days per week")

                stepperButton(systemImage: "plus") {
                    updateDays(delta: 1)
                }
            }
        }
    }

    private var currentWorkoutDays: Int {
        min(max(onboardingStore.draft.workoutDaysPerWeek ?? UserProfile.defaultWorkoutDaysPerWeek, 1), 7)
    }

    private func updateDays(delta: Int) {
        onboardingStore.draft.workoutDaysPerWeek = min(max(currentWorkoutDays + delta, 1), 7)
    }

    private func stepperButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .frame(width: 58, height: 58)
                .background(SpotterV2.Tokens.card)
                .clipShape(Circle())
                .overlay(Circle().stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemImage == "plus" ? "Increase days per week" : "Decrease days per week")
    }

    private func systemImage(for goal: FitnessGoal) -> String {
        switch goal {
        case .strength:
            return "chair.fill"
        case .performance:
            return "bolt.fill"
        case .longevity:
            return "leaf.fill"
        }
    }

    private func limitationSubtitle(_ limitation: PhysicalLimitation) -> String {
        switch limitation {
        case .kneeSensitive:
            return "Keep knee-heavy moves conservative."
        case .shoulderSensitive:
            return "Limit aggressive overhead work."
        case .wristSensitive:
            return "Prefer wrist-friendly pressing angles."
        case .lowerBackSensitive:
            return "Favor neutral-spine and low-load patterns."
        case .balanceSensitive:
            return "Use stable stance options first."
        case .highImpactSensitive:
            return "Avoid jump-heavy conditioning."
        }
    }
}

private struct V2CheckRow: View {
    let theme: SpotterThemeOption
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpotterV2.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.mutedForeground)

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                    Text(title)
                        .font(SpotterV2Typography.heading(size: 16, weight: .black))
                        .fontWidth(.compressed)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                    Text(subtitle)
                        .font(SpotterV2Typography.body(size: 12, weight: .semibold))
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(SpotterV2.Spacing.md)
            .background(SpotterV2.Tokens.card)
            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                    .stroke(
                        isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.border.opacity(0.70),
                        lineWidth: SpotterV2.BorderWidth.standard
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

#if DEBUG
private struct V2OnboardingObjectiveView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2D3PreviewEnvironment(theme: theme) {
                    V2OnboardingObjectiveView(onBack: {}, onNext: {})
                }
                .previewDisplayName("\(theme.displayName) Objective SE")
                .previewDevice("iPhone SE (3rd generation)")

                V2D3PreviewEnvironment(theme: theme) {
                    V2OnboardingObjectiveView(onBack: {}, onNext: {})
                }
                .previewDisplayName("\(theme.displayName) Objective Pro Max")
                .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}
#endif
