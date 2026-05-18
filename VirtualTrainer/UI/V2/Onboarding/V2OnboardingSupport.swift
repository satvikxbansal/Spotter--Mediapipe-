import SwiftUI

struct V2OnboardingFlowView: View {
    @EnvironmentObject private var store: OnboardingStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStore.Step = .welcome
    @State private var direction: V2OnboardingTransitionDirection = .push

    var body: some View {
        ZStack {
            SpotterV2.Tokens.background.ignoresSafeArea()

            screen(for: step)
                .id(step)
                .transition(transition)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: step)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func screen(for step: OnboardingStore.Step) -> some View {
        switch step {
        case .welcome:
            V2WelcomeView(onStart: advance)
        case .identity:
            V2OnboardingIdentityView(onBack: back, onNext: advance)
        case .stats:
            V2OnboardingStatsView(onBack: back, onNext: advance)
        case .goalEquipment:
            V2OnboardingObjectiveView(onBack: back, onNext: advance)
        case .coachTheme:
            OnboardingCoachThemeView(store: store, onBack: back, onNext: advance)
        case .completion:
            OnboardingCompletionView(store: store, onBack: back)
        }
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let fadeAndTrail = AnyTransition.opacity.combined(with: .move(edge: .trailing))
        let fadeAndLead = AnyTransition.opacity.combined(with: .move(edge: .leading))
        switch direction {
        case .push:
            return .asymmetric(insertion: fadeAndTrail, removal: fadeAndLead)
        case .pop:
            return .asymmetric(insertion: fadeAndLead, removal: fadeAndTrail)
        }
    }

    private func advance() {
        guard let next = OnboardingStore.Step(rawValue: step.rawValue + 1) else { return }
        direction = .push
        step = next
    }

    private func back() {
        guard let previous = OnboardingStore.Step(rawValue: step.rawValue - 1) else { return }
        direction = .pop
        step = previous
    }
}

private enum V2OnboardingTransitionDirection {
    case push
    case pop
}

struct V2OnboardingPage<Content: View>: View {
    let theme: SpotterThemeOption
    let activeStep: Int
    let stepText: String
    let title: String
    let accentTitle: String
    let subtitle: String
    let canContinue: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        theme: SpotterThemeOption,
        activeStep: Int,
        stepText: String,
        title: String,
        accentTitle: String,
        subtitle: String,
        canContinue: Bool,
        onBack: @escaping () -> Void,
        onNext: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.activeStep = activeStep
        self.stepText = stepText
        self.title = title
        self.accentTitle = accentTitle
        self.subtitle = subtitle
        self.canContinue = canContinue
        self.onBack = onBack
        self.onNext = onNext
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                progressHeader
                    .padding(.top, max(proxy.safeAreaInsets.top + SpotterV2.Spacing.lg, SpotterV2.Spacing.xxxl))

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.sm) {
                    Text(title.uppercased())
                        .font(SpotterV2Typography.display(size: 42))
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.60)

                    Text(accentTitle.uppercased())
                        .font(SpotterV2Typography.display(size: 42))
                        .italic()
                        .foregroundStyle(SpotterV2.Tokens.primary(theme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)

                    Text(subtitle)
                        .font(SpotterV2Typography.body(size: 17, weight: .semibold))
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, SpotterV2.Spacing.xs)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    content
                        .padding(.bottom, SpotterV2.Spacing.xl)
                }

                HStack(spacing: SpotterV2.Spacing.lg) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(SpotterV2.Tokens.foreground)
                            .frame(width: 56, height: 56)
                            .background(SpotterV2.Tokens.card)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
                            )
                    }
                    .buttonStyle(V2PlainPressStyle(reduceMotion: reduceMotion))
                    .accessibilityLabel("Back")

                    V2CTAButton(
                        title: "Continue",
                        systemImage: "arrow.right",
                        theme: theme,
                        isDisabled: !canContinue,
                        action: onNext
                    )
                }
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, SpotterV2.Spacing.lg))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, SpotterV2.Spacing.xl)
            .background(SpotterV2.Tokens.background)
        }
    }

    private var progressHeader: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { index in
                    Capsule()
                        .fill(index <= activeStep ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.secondary)
                        .frame(width: 40, height: 6)
                        .shadow(
                            color: index <= activeStep ? SpotterV2.Tokens.primary(theme).opacity(0.35) : .clear,
                            radius: 8
                        )
                }
            }

            Spacer(minLength: SpotterV2.Spacing.md)

            Text(stepText)
                .font(SpotterV2Typography.mono(size: 13, weight: .bold))
                .tracking(2.0)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding step \(stepText)")
    }
}

struct V2SelectorTile: View {
    let theme: SpotterThemeOption
    let title: String
    var subtitle: String?
    var systemImage: String?
    var isSelected: Bool
    var minHeight: CGFloat = 92
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                        .fill(SpotterV2.Tokens.primary(theme))
                        .offset(x: 6, y: 6)
                }

                HStack(spacing: SpotterV2.Spacing.md) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 27, weight: .black))
                            .foregroundStyle(isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.mutedForeground)
                            .frame(width: 50, height: 50)
                            .background((isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.foreground).opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                                    .stroke((isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.foreground).opacity(0.30), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                        Text(title)
                            .font(SpotterV2Typography.heading(size: 21))
                            .italic()
                            .textCase(.uppercase)
                            .foregroundStyle(isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.mutedForeground)
                            .lineLimit(2)
                            .minimumScaleFactor(0.62)

                        if let subtitle {
                            Text(subtitle)
                                .font(SpotterV2Typography.body(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? SpotterV2.Tokens.mutedForeground : SpotterV2.Tokens.mutedForeground.opacity(0.7))
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                        }
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26, weight: .black))
                            .foregroundStyle(SpotterV2.Tokens.primary(theme))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .padding(SpotterV2.Spacing.md)
                .background(SpotterV2.Tokens.card)
                .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                        .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct V2CompactSelectorTile: View {
    let theme: SpotterThemeOption
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                        .fill(SpotterV2.Tokens.primary(theme))
                        .offset(x: 6, y: 6)
                }

                VStack(spacing: SpotterV2.Spacing.sm) {
                    Image(systemName: systemImage)
                        .font(.system(size: 27, weight: .black))
                    Text(title)
                        .font(SpotterV2Typography.caption())
                        .italic()
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .lineLimit(2)
                        .minimumScaleFactor(0.62)
                }
                .foregroundStyle(isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.mutedForeground)
                .frame(maxWidth: .infinity, minHeight: 98)
                .background(SpotterV2.Tokens.card)
                .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                        .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct V2TagToggle: View {
    let theme: SpotterThemeOption
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                if isSelected {
                    Capsule()
                        .fill(SpotterV2.Tokens.primary(theme))
                        .offset(x: 5, y: 5)
                }

                Text(title)
                    .font(SpotterV2Typography.caption())
                    .italic()
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.mutedForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .padding(.horizontal, SpotterV2.Spacing.lg)
                    .padding(.vertical, SpotterV2.Spacing.sm)
                    .background(SpotterV2.Tokens.card)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct V2FieldLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(SpotterV2Typography.mono(size: 11, weight: .bold))
            .tracking(3.0)
            .textCase(.uppercase)
            .foregroundStyle(SpotterV2.Tokens.mutedForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.70)
    }
}

struct V2ValidationMessage: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(SpotterV2Typography.caption(weight: .bold))
                .foregroundStyle(SpotterV2.Tokens.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(message)
        }
    }
}

struct V2PlainPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : SpotterV2.Motion.press, value: configuration.isPressed)
    }
}

struct V2FlowLayout: Layout {
    var spacing: CGFloat = SpotterV2.Spacing.sm

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

#if DEBUG
@MainActor
struct V2D3PreviewEnvironment<Content: View>: View {
    let content: Content
    @StateObject private var onboardingStore: OnboardingStore
    @StateObject private var calibrationStore: CalibrationStore
    @StateObject private var themeStore: ThemeStore
    @StateObject private var appDependencies = AppDependencies.local()

    init(
        theme: SpotterThemeOption,
        draft: OnboardingDraft? = nil,
        calibrationStore: CalibrationStore? = nil,
        @ViewBuilder content: () -> Content
    ) {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("V2D3Preview-\(UUID().uuidString)", isDirectory: true)
        let onboarding = OnboardingStore(fileURL: baseURL.appendingPathComponent("UserProfile.json"))
        onboarding.draft = draft ?? .v2Preview
        _onboardingStore = StateObject(wrappedValue: onboarding)
        _calibrationStore = StateObject(
            wrappedValue: calibrationStore ?? CalibrationStore(fileURL: baseURL.appendingPathComponent("CalibrationRecord.json"))
        )
        _themeStore = StateObject(wrappedValue: ThemeStore(fileURL: baseURL.appendingPathComponent("Theme.json"), defaultTheme: theme))
        self.content = content()
    }

    var body: some View {
        content
            .environmentObject(onboardingStore)
            .environmentObject(calibrationStore)
            .environmentObject(themeStore)
            .environmentObject(appDependencies)
            .preferredColorScheme(.dark)
    }
}

extension OnboardingDraft {
    static var v2Preview: OnboardingDraft {
        var draft = OnboardingDraft()
        draft.displayName = "Satvik Bansal"
        draft.genderIdentity = .male
        draft.age = "24"
        draft.height = "178"
        draft.weight = "84.5"
        draft.primaryGoal = .strength
        draft.fitnessLevel = .beginner
        draft.equipment = [.bodyweight, .dumbbells]
        draft.limitations = [.kneeSensitive]
        draft.preferredSessionLength = .twentyFive
        draft.workoutDaysPerWeek = 4
        return draft
    }
}
#endif
