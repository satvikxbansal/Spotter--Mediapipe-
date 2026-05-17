import SwiftUI

struct V2Card<Content: View>: View {
    let theme: SpotterThemeOption
    let radius: CGFloat
    let padding: CGFloat
    let borderColor: Color
    let lineWidth: CGFloat
    let hardShadowColor: Color?
    let content: Content

    init(
        theme: SpotterThemeOption,
        radius: CGFloat = SpotterV2.Radius.md,
        padding: CGFloat = SpotterV2.Spacing.md,
        borderColor: Color = SpotterV2.Tokens.border,
        lineWidth: CGFloat = SpotterV2.BorderWidth.standard,
        hardShadowColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.radius = radius
        self.padding = padding
        self.borderColor = borderColor
        self.lineWidth = lineWidth
        self.hardShadowColor = hardShadowColor
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let hardShadowColor {
                RoundedRectangle(cornerRadius: radius)
                    .fill(hardShadowColor)
                    .offset(x: 4, y: 4)
            }

            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SpotterV2.Tokens.card)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(borderColor, lineWidth: lineWidth)
                )
        }
    }
}

private struct V2ButtonStyle: ButtonStyle {
    let fill: Color
    let foreground: Color
    let borderColor: Color?
    let reduceMotion: Bool
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SpotterV2Typography.heading(size: 16, weight: .black))
            .tracking(1.0)
            .textCase(.uppercase)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xl))
            .overlay {
                if let borderColor {
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.xl)
                        .stroke(borderColor, lineWidth: SpotterV2.BorderWidth.standard)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isDisabled ? 0.45 : 1)
            .animation(reduceMotion ? nil : SpotterV2.Motion.press, value: configuration.isPressed)
    }
}

struct V2CTAButton: View {
    let title: String
    let systemImage: String?
    let theme: SpotterThemeOption
    var isDisabled = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            buttonLabel
        }
        .buttonStyle(
            V2ButtonStyle(
                fill: SpotterV2.Tokens.primary(theme),
                foreground: .black,
                borderColor: nil,
                reduceMotion: reduceMotion,
                isDisabled: isDisabled
            )
        )
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var buttonLabel: some View {
        HStack(spacing: SpotterV2.Spacing.sm) {
            Text(title)
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
    }
}

struct V2SecondaryButton: View {
    let title: String
    let systemImage: String?
    let theme: SpotterThemeOption
    var isDisabled = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpotterV2.Spacing.sm) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
        }
        .buttonStyle(
            V2ButtonStyle(
                fill: .clear,
                foreground: SpotterV2.Tokens.foreground,
                borderColor: SpotterV2.Tokens.border,
                reduceMotion: reduceMotion,
                isDisabled: isDisabled
            )
        )
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

struct V2DestructiveButton: View {
    let title: String
    let systemImage: String?
    var isDisabled = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpotterV2.Spacing.sm) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
        }
        .buttonStyle(
            V2ButtonStyle(
                fill: SpotterV2.Tokens.destructive,
                foreground: .white,
                borderColor: nil,
                reduceMotion: reduceMotion,
                isDisabled: isDisabled
            )
        )
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

struct V2MetricPill: View {
    let theme: SpotterThemeOption
    let eyebrow: String
    let value: String
    var detail: String?
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.xs) {
            HStack(spacing: SpotterV2.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(SpotterV2.Tokens.primary(theme))
                }
                Text(eyebrow)
                    .font(SpotterV2Typography.caption())
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
            }

            Text(value)
                .font(SpotterV2Typography.mono(size: 32))
                .monospacedDigit()
                .foregroundStyle(SpotterV2.Tokens.primary(theme))
                .lineLimit(1)
                .minimumScaleFactor(0.58)

            if let detail {
                Text(detail)
                    .font(SpotterV2Typography.caption(weight: .bold))
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .padding(SpotterV2.Spacing.md)
        .background(SpotterV2.Tokens.secondary)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                .stroke(SpotterV2.Tokens.border.opacity(0.42), lineWidth: SpotterV2.BorderWidth.standard)
        )
    }
}

struct V2StatusPill: View {
    let theme: SpotterThemeOption
    let label: String
    var pulsingDot = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: SpotterV2.Spacing.xs) {
            Circle()
                .fill(SpotterV2.Tokens.primary(theme))
                .frame(width: 8, height: 8)
                .scaleEffect(pulsingDot && isPulsing && !reduceMotion ? 1.45 : 1)
                .opacity(pulsingDot && isPulsing && !reduceMotion ? 0.42 : 1)
                .animation(pulsingDot && !reduceMotion ? SpotterV2.Motion.pulse : nil, value: isPulsing)

            Text(label)
                .font(SpotterV2Typography.caption())
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, SpotterV2.Spacing.sm)
        .padding(.vertical, SpotterV2.Spacing.xs)
        .background(SpotterV2.Tokens.secondary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(SpotterV2.Tokens.primary(theme).opacity(0.5), lineWidth: 1)
        )
        .onAppear {
            guard pulsingDot, !reduceMotion else { return }
            isPulsing = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

struct V2SectionHeader: View {
    let title: String
    var trailingTitle: String?
    var trailingSystemImage: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(SpotterV2Typography.caption())
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: SpotterV2.Spacing.sm)

            if let trailingTitle {
                if let trailingAction {
                    Button(action: trailingAction) {
                        trailingLabel(title: trailingTitle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(trailingTitle)
                } else {
                    trailingLabel(title: trailingTitle)
                }
            }
        }
    }

    private func trailingLabel(title: String) -> some View {
        HStack(spacing: SpotterV2.Spacing.xxs) {
            Text(title)
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
            }
        }
        .font(SpotterV2Typography.caption())
        .tracking(1.2)
        .textCase(.uppercase)
        .foregroundStyle(SpotterV2.Tokens.foreground)
    }
}

struct V2ProgressRing: View {
    let theme: SpotterThemeOption
    let progress: Double
    let value: String
    var caption: String?
    var size: CGFloat = 112

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(SpotterV2.Tokens.secondary, lineWidth: 10)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    SpotterV2.Tokens.primary(theme),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: SpotterV2.Spacing.xxxs) {
                Text(value)
                    .font(SpotterV2Typography.mono(size: 24))
                    .monospacedDigit()
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                if let caption {
                    Text(caption)
                        .font(SpotterV2Typography.caption(weight: .bold))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(caption ?? "progress")")
    }
}

struct V2HeroNumber: View {
    let value: String
    var caption: String?
    var theme: SpotterThemeOption = .hyper
    var size: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
            Text(value)
                .font(SpotterV2Typography.mono(size: size))
                .italic()
                .monospacedDigit()
                .foregroundStyle(SpotterV2.Tokens.primary(theme))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            if let caption {
                Text(caption)
                    .font(SpotterV2Typography.caption())
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct V2InsightCard: View {
    let theme: SpotterThemeOption
    let eyebrow: String
    let headline: String
    let bodyText: String
    var onOpenEvidence: (() -> Void)?
    var onHelpful: (() -> Void)?
    var onNotHelpful: (() -> Void)?

    var body: some View {
        V2Card(
            theme: theme,
            radius: SpotterV2.Radius.lg,
            borderColor: SpotterV2.Tokens.primary(theme).opacity(0.62),
            hardShadowColor: SpotterV2.Tokens.primary(theme).opacity(0.22)
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                HStack(spacing: SpotterV2.Spacing.xs) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(SpotterV2.Tokens.chart1)
                    Text(eyebrow)
                        .font(SpotterV2Typography.caption())
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.chart1)
                }

                Text(headline)
                    .font(SpotterV2Typography.heading(size: 20))
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                Text(bodyText)
                    .font(SpotterV2Typography.body(size: 14))
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SpotterV2.Spacing.sm) {
                    if let onOpenEvidence {
                        V2InsightControlButton(
                            title: "Evidence",
                            systemImage: "doc.text.magnifyingglass",
                            tint: SpotterV2.Tokens.primary(theme),
                            action: onOpenEvidence
                        )
                    }
                    if let onHelpful {
                        V2InsightControlButton(
                            title: "Helpful",
                            systemImage: "hand.thumbsup.fill",
                            tint: SpotterV2.Tokens.primary(theme),
                            action: onHelpful
                        )
                    }
                    if let onNotHelpful {
                        V2InsightControlButton(
                            title: "Not helpful",
                            systemImage: "hand.thumbsdown.fill",
                            tint: SpotterV2.Tokens.destructive,
                            action: onNotHelpful
                        )
                    }
                }
            }
        }
    }
}

private struct V2InsightControlButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(SpotterV2Typography.caption(weight: .black))
                .tracking(0.8)
                .textCase(.uppercase)
                .labelStyle(.iconOnly)
                .foregroundStyle(tint)
                .frame(width: 42, height: 34)
                .background(tint.opacity(0.14))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct V2WorkoutHistoryRow: View {
    let theme: SpotterThemeOption
    let date: Date
    let title: String
    let mode: String
    let metrics: [String]
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(mode)")
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: SpotterV2.Spacing.md) {
            VStack(spacing: SpotterV2.Spacing.xxxs) {
                Text(date, format: .dateTime.month(.abbreviated))
                Text(date, format: .dateTime.day())
            }
            .font(SpotterV2Typography.caption())
            .textCase(.uppercase)
            .foregroundStyle(.black)
            .frame(width: 54, height: 54)
            .background(SpotterV2.Tokens.primary(theme))
            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.sm))

            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                Text(title)
                    .font(SpotterV2Typography.heading(size: 15))
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                HStack(spacing: SpotterV2.Spacing.xs) {
                    Text(mode)
                        .font(SpotterV2Typography.caption(weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.primary(theme))
                    Text(metrics.joined(separator: " / "))
                        .font(SpotterV2Typography.caption(weight: .bold))
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
            }

            Spacer(minLength: SpotterV2.Spacing.xs)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
        }
        .padding(SpotterV2.Spacing.md)
        .background(SpotterV2.Tokens.secondary)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                .stroke(SpotterV2.Tokens.border.opacity(0.35), lineWidth: 1)
        )
    }
}

struct V2ExerciseRow: View {
    let theme: SpotterThemeOption
    let index: Int
    let name: String
    let target: String
    var isDisabled = false

    var body: some View {
        HStack(spacing: SpotterV2.Spacing.md) {
            Text(String(format: "%02d", index))
                .font(SpotterV2Typography.mono(size: 14))
                .foregroundStyle(isDisabled ? SpotterV2.Tokens.mutedForeground : .black)
                .frame(width: 42, height: 42)
                .background(isDisabled ? SpotterV2.Tokens.secondary : SpotterV2.Tokens.primary(theme))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                Text(name)
                    .font(SpotterV2Typography.heading(size: 16))
                    .textCase(.uppercase)
                    .foregroundStyle(isDisabled ? SpotterV2.Tokens.mutedForeground : SpotterV2.Tokens.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(isDisabled ? "Coming soon" : target)
                    .font(SpotterV2Typography.caption(weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(isDisabled ? SpotterV2.Tokens.destructive : SpotterV2.Tokens.mutedForeground)
            }

            Spacer()

            V2StatusPill(
                theme: theme,
                label: isDisabled ? "Locked" : target,
                pulsingDot: false
            )
        }
        .padding(SpotterV2.Spacing.md)
        .background(SpotterV2.Tokens.card)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                .stroke(
                    isDisabled ? SpotterV2.Tokens.destructive.opacity(0.55) : SpotterV2.Tokens.border.opacity(0.7),
                    lineWidth: SpotterV2.BorderWidth.standard
                )
        )
        .opacity(isDisabled ? 0.72 : 1)
        .accessibilityElement(children: .combine)
    }
}

struct V2TrophyCard: View {
    let theme: SpotterThemeOption
    let systemImage: String
    let title: String
    let subtitle: String
    let rarity: String
    let progress: Double
    var isLocked = false

    var body: some View {
        V2Card(
            theme: theme,
            radius: SpotterV2.Radius.lg,
            hardShadowColor: isLocked ? nil : SpotterV2.Tokens.primary(theme).opacity(0.35)
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(isLocked ? SpotterV2.Tokens.mutedForeground : .black)
                        .frame(width: 52, height: 52)
                        .background(isLocked ? SpotterV2.Tokens.secondary : SpotterV2.Tokens.primary(theme))
                        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))

                    Spacer()

                    Text(rarity)
                        .font(SpotterV2Typography.caption())
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(isLocked ? SpotterV2.Tokens.mutedForeground : SpotterV2.Tokens.primary(theme))
                        .padding(.horizontal, SpotterV2.Spacing.sm)
                        .padding(.vertical, SpotterV2.Spacing.xs)
                        .overlay(Capsule().stroke(SpotterV2.Tokens.border.opacity(0.45), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                    Text(title)
                        .font(SpotterV2Typography.heading(size: 18))
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                    Text(subtitle)
                        .font(SpotterV2Typography.body(size: 13))
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ProgressView(value: min(max(progress, 0), 1))
                    .tint(isLocked ? SpotterV2.Tokens.mutedForeground : SpotterV2.Tokens.primary(theme))
                    .accessibilityLabel("\(title) progress")
            }
        }
        .opacity(isLocked ? 0.72 : 1)
    }
}

struct V2ThemeOptionCard: View {
    let theme: SpotterThemeOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SpotterV2.Spacing.sm) {
                LazyVGrid(
                    columns: [GridItem(.fixed(20)), GridItem(.fixed(20))],
                    spacing: SpotterV2.Spacing.xxs
                ) {
                    Circle().fill(theme.accentColor)
                    Circle().fill(theme.secondaryAccentColor)
                    Circle().fill(SpotterV2.Tokens.border)
                    Circle().fill(SpotterV2.Tokens.secondary)
                }
                .frame(width: 44, height: 44)
                .padding(SpotterV2.Spacing.xs)
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? SpotterV2.Tokens.ring(theme) : SpotterV2.Tokens.border.opacity(0.35),
                            lineWidth: isSelected ? 3 : 1
                        )
                )

                Text(theme.displayName)
                    .font(SpotterV2Typography.caption())
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(isSelected ? SpotterV2.Tokens.primary(theme) : SpotterV2.Tokens.mutedForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 94)
            .padding(SpotterV2.Spacing.xs)
            .background(SpotterV2.Tokens.card)
            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                    .stroke(
                        isSelected ? SpotterV2.Tokens.ring(theme) : SpotterV2.Tokens.border,
                        lineWidth: isSelected ? SpotterV2.BorderWidth.standard : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}

struct V2EmptyState: View {
    let theme: SpotterThemeOption
    let title: String
    let bodyText: String
    var ctaTitle: String?
    var ctaAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.lg) {
            Text(title)
                .font(SpotterV2Typography.display(size: 40))
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .lineLimit(3)
                .minimumScaleFactor(0.62)

            Text(bodyText)
                .font(SpotterV2Typography.body())
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            if let ctaTitle, let ctaAction {
                V2CTAButton(
                    title: ctaTitle,
                    systemImage: "arrow.right",
                    theme: theme,
                    action: ctaAction
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SpotterV2.Spacing.xl)
        .background(SpotterV2.Tokens.background)
    }
}

struct V2BottomSheetShell<Content: View>: View {
    let theme: SpotterThemeOption
    let title: String?
    let onClose: () -> Void
    let content: Content

    init(
        theme: SpotterThemeOption,
        title: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.title = title
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.lg) {
            HStack {
                Capsule()
                    .fill(SpotterV2.Tokens.mutedForeground.opacity(0.7))
                    .frame(width: 48, height: 5)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .frame(width: 40, height: 40)
                        .background(SpotterV2.Tokens.secondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            if let title {
                Text(title)
                    .font(SpotterV2Typography.heading(size: 28))
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(SpotterV2.Spacing.xl)
        .background(SpotterV2.Tokens.background)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl)
                .stroke(SpotterV2.Tokens.primary(theme), lineWidth: SpotterV2.BorderWidth.standard)
        )
    }
}

#if DEBUG
struct V2BackendStatusChip: View {
    let mode: BackendMode
    let theme: SpotterThemeOption

    var body: some View {
        HStack(spacing: SpotterV2.Spacing.xs) {
            Text("DEBUG")
                .font(SpotterV2Typography.caption())
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.black)
                .padding(.horizontal, SpotterV2.Spacing.xs)
                .padding(.vertical, SpotterV2.Spacing.xxxs)
                .background(SpotterV2.Tokens.primary(theme))
                .clipShape(Capsule())

            Text(mode.displayName)
                .font(SpotterV2Typography.caption())
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.foreground)
        }
        .padding(.horizontal, SpotterV2.Spacing.sm)
        .padding(.vertical, SpotterV2.Spacing.xs)
        .background(SpotterV2.Tokens.secondary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(SpotterV2.Tokens.border.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Debug backend mode \(mode.displayName)")
    }
}

private struct SpotterV2ComponentPreviewContent: View {
    let theme: SpotterThemeOption

    private let columns = [
        GridItem(.flexible(), spacing: SpotterV2.Spacing.sm),
        GridItem(.flexible(), spacing: SpotterV2.Spacing.sm)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                V2SectionHeader(title: "Theme", trailingTitle: theme.displayName)

                V2Card(
                    theme: theme,
                    radius: SpotterV2.Radius.lg,
                    hardShadowColor: SpotterV2.Tokens.primary(theme)
                ) {
                    VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                        V2StatusPill(theme: theme, label: "Training active", pulsingDot: true)
                        Text("V2 Design System")
                            .font(SpotterV2Typography.display(size: 38))
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.foreground)
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                        V2CTAButton(title: "Start Training", systemImage: "bolt.fill", theme: theme) {}
                        V2SecondaryButton(title: "Secondary", systemImage: "arrow.right", theme: theme) {}
                        V2DestructiveButton(title: "Delete", systemImage: "trash.fill") {}
                    }
                }

                LazyVGrid(columns: columns, spacing: SpotterV2.Spacing.sm) {
                    V2MetricPill(theme: theme, eyebrow: "Streak", value: "12", detail: "Active days", systemImage: "flame.fill")
                    V2MetricPill(theme: theme, eyebrow: "Form", value: "94%", detail: "Quality", systemImage: "brain.head.profile")
                }

                HStack(spacing: SpotterV2.Spacing.lg) {
                    V2ProgressRing(theme: theme, progress: 0.68, value: "68%", caption: "Ready")
                    V2HeroNumber(value: "07", caption: "Reps", theme: theme)
                }

                V2InsightCard(
                    theme: theme,
                    eyebrow: "Spotter insight",
                    headline: "Depth improved after rep four.",
                    bodyText: "Keep the first cue early, then hold the target steady before adding more reps.",
                    onOpenEvidence: {},
                    onHelpful: {},
                    onNotHelpful: {}
                )

                V2WorkoutHistoryRow(
                    theme: theme,
                    date: Date(timeIntervalSince1970: 1_778_067_200),
                    title: "Full Body Engine",
                    mode: "Planned",
                    metrics: ["34m", "48 reps", "94% form"],
                    action: {}
                )

                V2ExerciseRow(theme: theme, index: 1, name: "Air Squats", target: "3 x 12")
                V2ExerciseRow(theme: theme, index: 2, name: "Running Analysis", target: "Coming soon", isDisabled: true)

                V2TrophyCard(
                    theme: theme,
                    systemImage: "trophy.fill",
                    title: "Depth Charge",
                    subtitle: "Complete clean squat reps with reliable depth.",
                    rarity: "Rare",
                    progress: 0.72
                )

                LazyVGrid(columns: columns, spacing: SpotterV2.Spacing.sm) {
                    ForEach(SpotterThemeOption.allCases) { option in
                        V2ThemeOptionCard(theme: option, isSelected: option == theme) {}
                    }
                }

                V2EmptyState(
                    theme: theme,
                    title: "No history yet",
                    bodyText: "Planned workouts and free-analysis saves will appear here.",
                    ctaTitle: "Train now",
                    ctaAction: {}
                )

                V2BottomSheetShell(theme: theme, title: "Adjust Movement", onClose: {}) {
                    V2ExerciseRow(theme: theme, index: 1, name: "Push Ups", target: "3 x AMRAP")
                }

                V2BackendStatusChip(mode: .local, theme: theme)
            }
            .padding(SpotterV2.Spacing.xl)
        }
        .background(SpotterV2.Tokens.background)
        .preferredColorScheme(.dark)
    }
}

private struct SpotterV2Components_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SpotterV2ComponentPreviewContent(theme: .hyper)
                .previewDisplayName("Hyper - SE")
                .previewDevice("iPhone SE (3rd generation)")
            SpotterV2ComponentPreviewContent(theme: .hotGirl)
                .previewDisplayName("Hot Girl - SE")
                .previewDevice("iPhone SE (3rd generation)")
            SpotterV2ComponentPreviewContent(theme: .warm)
                .previewDisplayName("Warm - SE")
                .previewDevice("iPhone SE (3rd generation)")
            SpotterV2ComponentPreviewContent(theme: .spicy)
                .previewDisplayName("Spicy - SE")
                .previewDevice("iPhone SE (3rd generation)")
            SpotterV2ComponentPreviewContent(theme: .hyper)
                .previewDisplayName("Hyper - Pro Max")
                .previewDevice("iPhone 17 Pro Max")
            SpotterV2ComponentPreviewContent(theme: .hotGirl)
                .previewDisplayName("Hot Girl - Pro Max")
                .previewDevice("iPhone 17 Pro Max")
            SpotterV2ComponentPreviewContent(theme: .warm)
                .previewDisplayName("Warm - Pro Max")
                .previewDevice("iPhone 17 Pro Max")
            SpotterV2ComponentPreviewContent(theme: .spicy)
                .previewDisplayName("Spicy - Pro Max")
                .previewDevice("iPhone 17 Pro Max")
        }
    }
}
#endif
