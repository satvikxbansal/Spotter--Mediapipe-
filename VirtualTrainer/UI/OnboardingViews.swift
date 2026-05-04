import SwiftUI

// ────────────────────────────────────────────────────────────────────
// MARK: - Onboarding Flow
// ────────────────────────────────────────────────────────────────────

struct OnboardingFlowView: View {
    @EnvironmentObject private var store: OnboardingStore
    @State private var step: OnboardingStore.Step = .welcome

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                switch step {
                case .welcome:
                    WelcomeView(onStart: advance)
                case .identity:
                    OnboardingIdentityView(store: store, onBack: back, onNext: advance)
                case .stats:
                    OnboardingStatsView(store: store, onBack: back, onNext: advance)
                case .goalEquipment:
                    OnboardingGoalEquipmentView(store: store, onBack: back, onNext: advance)
                case .coachTheme:
                    OnboardingCoachThemeView(store: store, onBack: back, onNext: advance)
                case .completion:
                    OnboardingCompletionView(store: store, onBack: back)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func advance() {
        guard let next = OnboardingStore.Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(Theme.Motion.smooth) {
            step = next
        }
    }

    private func back() {
        guard let previous = OnboardingStore.Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(Theme.Motion.smooth) {
            step = previous
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Welcome
// ────────────────────────────────────────────────────────────────────

struct WelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Spacer(minLength: Theme.Spacing.xxl)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("SPOTTER AI")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.accent)

                Text("Your AI Form Coach")
                    .font(.system(size: 56, weight: .black))
                    .textCase(.uppercase)
                    .tracking(-2)
                    .lineLimit(nil)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Set up the basics now. We will polish the experience later.")
                    .bodyText()
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            VStack(spacing: Theme.Spacing.sm) {
                FeatureRow(title: "Live form feedback", icon: "figure.strengthtraining.traditional")
                FeatureRow(title: "Personalized coaching style", icon: "person.wave.2.fill")
                FeatureRow(title: "Equipment-aware plans", icon: "dumbbell.fill")
            }

            Spacer()

            Button("Start onboarding", action: onStart)
                .buttonStyle(PrimaryCTAStyle())
        }
        .padding(Theme.Spacing.lg)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Identity
// ────────────────────────────────────────────────────────────────────

struct OnboardingIdentityView: View {
    @ObservedObject var store: OnboardingStore
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(
            stepText: "01 / 04",
            title: "Who are we training?",
            subtitle: "Gender is stored for your profile only. It does not branch exercise selection in V1.",
            canContinue: store.canContinue(from: .identity),
            onBack: onBack,
            onNext: onNext
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    FieldLabel("Display name")
                    TextField("Optional", text: $store.draft.displayName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .spotterTextField()
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    FieldLabel("Gender identity")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                        ForEach(GenderIdentity.allCases) { gender in
                            OptionButton(
                                title: gender.displayName,
                                subtitle: nil,
                                isSelected: store.draft.genderIdentity == gender
                            ) {
                                store.draft.genderIdentity = gender
                            }
                        }
                    }
                }
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Stats
// ────────────────────────────────────────────────────────────────────

struct OnboardingStatsView: View {
    @ObservedObject var store: OnboardingStore
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(
            stepText: "02 / 04",
            title: "Enter your vitals",
            subtitle: "Age becomes an age bracket for future intensity and rest rules.",
            canContinue: store.canContinue(from: .stats),
            onBack: onBack,
            onNext: onNext
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    FieldLabel("Age")
                    TextField("Years", text: $store.draft.age)
                        .keyboardType(.numberPad)
                        .spotterTextField()
                }

                MeasurementInput(
                    title: "Height",
                    value: $store.draft.height,
                    unit: $store.draft.heightUnit,
                    label: store.draft.heightUnit.heightLabel
                )

                MeasurementInput(
                    title: "Weight",
                    value: $store.draft.weight,
                    unit: $store.draft.weightUnit,
                    label: store.draft.weightUnit.weightLabel
                )
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Goal + Equipment
// ────────────────────────────────────────────────────────────────────

struct OnboardingGoalEquipmentView: View {
    @ObservedObject var store: OnboardingStore
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(
            stepText: "03 / 04",
            title: "Define your objective",
            subtitle: "Pick a focus, your current level, and the gear you can use.",
            canContinue: store.canContinue(from: .goalEquipment),
            onBack: onBack,
            onNext: onNext
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    FieldLabel("Primary goal")
                    ForEach(FitnessGoal.allCases) { goal in
                        OptionButton(
                            title: goal.displayName,
                            subtitle: goal.subtitle,
                            isSelected: store.draft.primaryGoal == goal
                        ) {
                            store.draft.primaryGoal = goal
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    FieldLabel("Fitness level")
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(FitnessLevel.allCases) { level in
                            OptionButton(
                                title: level.displayName,
                                subtitle: nil,
                                isSelected: store.draft.fitnessLevel == level
                            ) {
                                store.draft.fitnessLevel = level
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    FieldLabel("Equipment available")
                    FlowLayout(spacing: Theme.Spacing.sm) {
                        ForEach(EquipmentOption.allCases) { option in
                            TagButton(
                                title: option.displayName,
                                isSelected: store.draft.equipment.contains(option)
                            ) {
                                store.toggleEquipment(option)
                            }
                        }
                    }
                }
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Coach + Theme
// ────────────────────────────────────────────────────────────────────

struct OnboardingCoachThemeView: View {
    @ObservedObject var store: OnboardingStore
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(
            stepText: "04 / 04",
            title: "Choose your vibe",
            subtitle: "Coach and theme are saved now. Final theme polish comes later.",
            canContinue: store.canContinue(from: .coachTheme),
            onBack: onBack,
            onNext: onNext
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    FieldLabel("Preferred coach")
                    ForEach(CoachPreference.allCases) { coach in
                        OptionButton(
                            title: coach.displayName,
                            subtitle: coach.subtitle,
                            isSelected: store.draft.preferredCoach == coach
                        ) {
                            store.draft.preferredCoach = coach
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    FieldLabel("Theme")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                        ForEach(SpotterThemeOption.allCases) { theme in
                            OptionButton(
                                title: theme.displayName,
                                subtitle: nil,
                                isSelected: store.draft.selectedTheme == theme
                            ) {
                                store.draft.selectedTheme = theme
                            }
                        }
                    }
                }
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Completion
// ────────────────────────────────────────────────────────────────────

struct OnboardingCompletionView: View {
    @ObservedObject var store: OnboardingStore
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Button("Back", action: onBack)
                .foregroundStyle(Theme.Colors.accent)
                .font(.system(size: 14, weight: .bold))

            Spacer()

            Text("Ready for calibration")
                .header(size: 42)

            Text("Your profile will be saved locally. Main tabs unlock after this step.")
                .bodyText()
                .foregroundStyle(Theme.Colors.textSecondary)

            if let error = store.persistenceError {
                Text(error)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.danger)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }

            Button("Enter Spotter") {
                store.completeOnboarding()
            }
            .buttonStyle(PrimaryCTAStyle())
            .disabled(!store.canContinue(from: .completion))
            .opacity(store.canContinue(from: .completion) ? 1 : 0.45)

            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Shared Building Blocks
// ────────────────────────────────────────────────────────────────────

private struct OnboardingPage<Content: View>: View {
    let stepText: String
    let title: String
    let subtitle: String
    let canContinue: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Button("Back", action: onBack)
                    .foregroundStyle(Theme.Colors.accent)
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(stepText)
                    .caption()
                    .tracking(1.5)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(title)
                    .header(size: 36)
                Text(subtitle)
                    .bodyText()
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            ScrollView(.vertical, showsIndicators: false) {
                content
                    .padding(.bottom, Theme.Spacing.xl)
            }

            Button("Continue", action: onNext)
                .buttonStyle(PrimaryCTAStyle())
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.45)
        }
        .padding(Theme.Spacing.lg)
    }
}

private struct MeasurementInput: View {
    let title: String
    @Binding var value: String
    @Binding var unit: UnitPreference
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                FieldLabel(title)
                Spacer()
                Picker(title, selection: $unit) {
                    Text("Metric").tag(UnitPreference.metric)
                    Text("Imperial").tag(UnitPreference.imperial)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            HStack(spacing: Theme.Spacing.sm) {
                TextField(label, text: $value)
                    .keyboardType(.decimalPad)
                    .spotterTextField()
                Text(label.uppercased())
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 32)
            }
        }
    }
}

private struct OptionButton: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(isSelected ? Theme.Colors.background : Theme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.Colors.background.opacity(0.75) : Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(isSelected ? Theme.Colors.accent : Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? Theme.Colors.accent : Theme.Colors.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TagButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(isSelected ? Theme.Colors.background : Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Colors.accent : Theme.Colors.surfaceRaised)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct FeatureRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 28)
            Text(title)
                .bodyText()
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

private struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.4)
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}

private struct SpotterTextFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 56)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Colors.divider, lineWidth: 1)
            )
    }
}

private extension View {
    func spotterTextField() -> some View {
        modifier(SpotterTextFieldModifier())
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? 0, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(in: bounds.width, subviews: subviews)
        for item in layout.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.frame.minX, y: bounds.minY + item.frame.minY),
                proposal: ProposedViewSize(item.frame.size)
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (items: [(index: Int, frame: CGRect)], size: CGSize) {
        guard width > 0 else { return ([], .zero) }

        var items: [(index: Int, frame: CGRect)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }

            items.append((index, CGRect(origin: CGPoint(x: x, y: y), size: size)))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (items, CGSize(width: width, height: y + lineHeight))
    }
}

#Preview {
    OnboardingFlowView()
        .environmentObject(OnboardingStore())
}
