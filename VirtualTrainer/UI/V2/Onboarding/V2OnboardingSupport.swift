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
    let titleSize: CGFloat
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
        titleSize: CGFloat = 38,
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
        self.titleSize = titleSize
        self.canContinue = canContinue
        self.onBack = onBack
        self.onNext = onNext
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760
            let resolvedTitleSize = isCompact ? min(titleSize, 36) : titleSize

            VStack(alignment: .leading, spacing: isCompact ? SpotterV2.Spacing.md : SpotterV2.Spacing.lg) {
                progressHeader(compact: isCompact)
                    .padding(.top, topPadding(for: proxy, compact: isCompact))

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xs) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title.uppercased())
                            .font(SpotterV2Typography.display(size: resolvedTitleSize))
                            .fontWidth(.compressed)
                            .foregroundStyle(SpotterV2.Tokens.foreground)
                            .lineLimit(2)
                            .minimumScaleFactor(0.60)

                        Text(accentTitle.uppercased())
                            .font(SpotterV2Typography.display(size: resolvedTitleSize))
                            .fontWidth(.compressed)
                            .italic()
                            .foregroundStyle(SpotterV2.Tokens.primary(theme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                    }

                    Text(subtitle)
                        .font(SpotterV2Typography.body(size: isCompact ? 15 : 16, weight: .semibold))
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    content
                        .padding(.bottom, isCompact ? SpotterV2.Spacing.sm : SpotterV2.Spacing.md)
                }

                HStack(spacing: isCompact ? SpotterV2.Spacing.md : SpotterV2.Spacing.lg) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: isCompact ? 20 : 22, weight: .black))
                            .foregroundStyle(SpotterV2.Tokens.foreground)
                            .frame(width: isCompact ? 52 : 56, height: isCompact ? 52 : 56)
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
                .padding(.bottom, isCompact ? SpotterV2.Spacing.xs : SpotterV2.Spacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, isCompact ? SpotterV2.Spacing.lg : SpotterV2.Spacing.xl)
            .background(SpotterV2.Tokens.background)
        }
    }

    private func topPadding(for _: GeometryProxy, compact: Bool) -> CGFloat {
        compact ? SpotterV2.Spacing.xxs : SpotterV2.Spacing.xs
    }

    private func progressHeader(compact: Bool) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { index in
                    Capsule()
                        .fill(index <= activeStep ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.secondary)
                        .frame(width: compact ? 34 : 40, height: 6)
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
                            .fontWidth(.compressed)
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
    let systemImage: String?
    let symbolText: String?
    let isSelected: Bool
    let action: () -> Void

    init(
        theme: SpotterThemeOption,
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.theme = theme
        self.title = title
        self.systemImage = systemImage
        self.symbolText = nil
        self.isSelected = isSelected
        self.action = action
    }

    init(
        theme: SpotterThemeOption,
        title: String,
        symbolText: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.theme = theme
        self.title = title
        self.systemImage = nil
        self.symbolText = symbolText
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                        .fill(SpotterV2.Tokens.primary(theme))
                        .offset(x: 6, y: 6)
                }

                VStack(spacing: SpotterV2.Spacing.sm) {
                    icon
                    Text(title)
                        .font(SpotterV2Typography.caption())
                        .fontWidth(.compressed)
                        .italic()
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .lineLimit(2)
                        .minimumScaleFactor(0.62)
                }
                .foregroundStyle(isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.mutedForeground)
                .frame(maxWidth: .infinity, minHeight: 88)
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

    @ViewBuilder
    private var icon: some View {
        if let symbolText {
            Text(symbolText)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .fontWidth(.compressed)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 25, weight: .black))
        }
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
                    .fontWidth(.compressed)
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

struct V2ScaleConfiguration: Equatable {
    let lowerBound: Double
    let upperBound: Double
    let step: Double
    let defaultValue: Double
    let labelStride: Int
    let decimalPlaces: Int
    let tickWidth: CGFloat

    var stepCount: Int {
        max(0, Int(((upperBound - lowerBound) / step).rounded()))
    }

    func value(for index: Int) -> Double {
        lowerBound + (Double(clampedIndex(index)) * step)
    }

    func index(for rawValue: Double) -> Int {
        let clampedValue = min(max(rawValue, lowerBound), upperBound)
        return clampedIndex(Int(((clampedValue - lowerBound) / step).rounded()))
    }

    func formattedValue(for index: Int) -> String {
        formattedValue(value(for: index))
    }

    func formattedValue(_ value: Double) -> String {
        let multiplier = pow(10.0, Double(decimalPlaces))
        let rounded = (value * multiplier).rounded() / multiplier
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.\(decimalPlaces)f", rounded)
    }

    func parsedIndex(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(trimmed), parsed.isFinite else { return nil }
        return index(for: parsed)
    }

    private func clampedIndex(_ index: Int) -> Int {
        min(max(index, 0), stepCount)
    }

    static let age = V2ScaleConfiguration(
        lowerBound: 13,
        upperBound: 100,
        step: 1,
        defaultValue: 34,
        labelStride: 1,
        decimalPlaces: 0,
        tickWidth: 58
    )

    static let heightMetric = V2ScaleConfiguration(
        lowerBound: 120,
        upperBound: 230,
        step: 1,
        defaultValue: 178,
        labelStride: 5,
        decimalPlaces: 0,
        tickWidth: 54
    )

    static let heightImperial = V2ScaleConfiguration(
        lowerBound: 48,
        upperBound: 90,
        step: 1,
        defaultValue: 70,
        labelStride: 2,
        decimalPlaces: 0,
        tickWidth: 58
    )

    static let weightMetric = V2ScaleConfiguration(
        lowerBound: 30,
        upperBound: 250,
        step: 0.5,
        defaultValue: 84.5,
        labelStride: 10,
        decimalPlaces: 1,
        tickWidth: 48
    )

    static let weightImperial = V2ScaleConfiguration(
        lowerBound: 66,
        upperBound: 550,
        step: 1,
        defaultValue: 186,
        labelStride: 10,
        decimalPlaces: 0,
        tickWidth: 46
    )
}

struct V2ScrollableScalePicker: View {
    let theme: SpotterThemeOption
    let title: String
    @Binding var value: String
    let configuration: V2ScaleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollIndex: Int?
    @State private var hapticTrigger = 0
    @State private var didAppear = false
    @State private var isSynchronizingFromText = false

    private var currentIndex: Int {
        scrollIndex ?? resolvedIndex
    }

    private var resolvedIndex: Int {
        configuration.parsedIndex(from: value)
            ?? configuration.index(for: configuration.defaultValue)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                    .fill(SpotterV2.Tokens.foreground.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                            .stroke(SpotterV2.Tokens.border.opacity(0.10), lineWidth: 1)
                    )

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .center, spacing: 0) {
                        ForEach(0...configuration.stepCount, id: \.self) { index in
                            scaleTick(index)
                                .frame(width: configuration.tickWidth)
                                .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(
                    .horizontal,
                    max(0, (proxy.size.width - configuration.tickWidth) / 2),
                    for: .scrollContent
                )
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrollIndex, anchor: .center)
                .sensoryFeedback(.selection, trigger: hapticTrigger)

                Rectangle()
                    .fill(SpotterV2.Tokens.primary(theme))
                    .frame(width: 3, height: 56)
                    .shadow(color: SpotterV2.Tokens.primary(theme).opacity(0.8), radius: 14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))
            .onTapGesture {
                commit(index: currentIndex, playHaptic: true)
            }
            .onAppear {
                syncScrollFromText()
                DispatchQueue.main.async {
                    didAppear = true
                }
            }
            .onChange(of: value) {
                syncScrollFromText()
            }
            .onChange(of: configuration) {
                syncScrollFromText()
            }
            .onChange(of: scrollIndex) { _, newIndex in
                guard didAppear, !isSynchronizingFromText, let newIndex else { return }
                commit(index: newIndex, playHaptic: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) scale")
            .accessibilityValue(configuration.formattedValue(for: currentIndex))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    let next = min(currentIndex + 1, configuration.stepCount)
                    scrollIndex = next
                    commit(index: next, playHaptic: true)
                case .decrement:
                    let previous = max(currentIndex - 1, 0)
                    scrollIndex = previous
                    commit(index: previous, playHaptic: true)
                @unknown default:
                    break
                }
            }
        }
        .frame(height: 88)
    }

    private func scaleTick(_ index: Int) -> some View {
        let isSelected = index == currentIndex
        let isNeighbor = abs(index - currentIndex) <= 1
        let isMajor = index % configuration.labelStride == 0

        return VStack(spacing: SpotterV2.Spacing.xxs) {
            Text(configuration.formattedValue(for: index))
                .font(SpotterV2Typography.heading(size: isSelected ? 28 : 24, weight: .black))
                .fontWidth(.compressed)
                .italic()
                .foregroundStyle(
                    isSelected
                        ? SpotterV2.Tokens.primary(theme)
                        : SpotterV2.Tokens.foreground.opacity(isNeighbor || isMajor ? 0.32 : 0.0)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(height: 34)

            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<3, id: \.self) { tickIndex in
                    Capsule()
                        .fill(
                            isSelected
                                ? SpotterV2.Tokens.primary(theme).opacity(tickIndex == 1 ? 1 : 0.30)
                                : SpotterV2.Tokens.foreground.opacity(tickIndex == 1 ? 0.30 : 0.16)
                        )
                        .frame(width: tickIndex == 1 ? 2 : 1, height: tickHeight(index: index, tickIndex: tickIndex))
                }
            }
        }
        .scaleEffect(isSelected && !reduceMotion ? 1.06 : 1)
        .animation(reduceMotion ? nil : SpotterV2.Motion.snappy, value: currentIndex)
    }

    private func tickHeight(index: Int, tickIndex: Int) -> CGFloat {
        if index == currentIndex, tickIndex == 1 {
            return 52
        }
        if index % configuration.labelStride == 0, tickIndex == 1 {
            return 28
        }
        return tickIndex == 1 ? 18 : 10
    }

    private func commit(index: Int, playHaptic: Bool) {
        let formatted = configuration.formattedValue(for: index)
        if value != formatted {
            value = formatted
        }
        if playHaptic {
            hapticTrigger += 1
        }
    }

    private func syncScrollFromText() {
        isSynchronizingFromText = true
        scrollIndex = resolvedIndex
        DispatchQueue.main.async {
            isSynchronizingFromText = false
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
