import SwiftUI

nonisolated enum V2WorkoutEffortTrend: String, Equatable {
    case rising
    case steady
    case falling

    init(score: Double) {
        if score >= 0.66 {
            self = .rising
        } else if score >= 0.34 {
            self = .steady
        } else {
            self = .falling
        }
    }

    var label: String {
        switch self {
        case .rising:
            return "Rising"
        case .steady:
            return "Steady"
        case .falling:
            return "Falling"
        }
    }

    var systemImage: String {
        switch self {
        case .rising:
            return "arrow.up.right"
        case .steady:
            return "arrow.right"
        case .falling:
            return "arrow.down.right"
        }
    }
}

struct V2LiveWorkoutShell: View {
    let theme: SpotterThemeOption
    let eyebrow: String
    let exerciseName: String
    let setText: String?
    let heroValue: String
    let heroCaption: String
    let targetText: String?
    let cameraViewText: String?
    let formScoreText: String?
    let cueText: String
    let effortTrend: V2WorkoutEffortTrend
    let effortValueText: String?
    let elapsedText: String?
    let visibilityWarning: String?
    let isLive: Bool
    let showsSkipButton: Bool
    let showsFinishButton: Bool
    let onSkip: () -> Void
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: SpotterV2.Spacing.md) {
            topBar
            warningBanner
            heroCounter
            Spacer(minLength: SpotterV2.Spacing.lg)
            bottomCueCard
        }
        .padding(.top, 58)
        .padding(.horizontal, SpotterV2.Spacing.lg)
        .padding(.bottom, 38)
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: SpotterV2.Spacing.sm) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xs) {
                Text(eyebrow)
                    .font(SpotterV2Typography.caption())
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
                    .shadow(color: .black.opacity(0.7), radius: 6, x: 0, y: 2)

                Text(exerciseName)
                    .font(SpotterV2Typography.display(size: 28))
                    .fontWidth(.compressed)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)
                    .shadow(color: .black.opacity(0.75), radius: 8, x: 0, y: 2)

                HStack(spacing: SpotterV2.Spacing.xs) {
                    if let setText {
                        V2GlassPill(theme: theme, label: setText, systemImage: "number")
                    }
                    if let targetText {
                        V2GlassPill(theme: theme, label: targetText, systemImage: "scope")
                    }
                    if let cameraViewText {
                        V2GlassPill(theme: theme, label: cameraViewText, systemImage: "rotate.3d.fill")
                    }
                }
            }

            Spacer(minLength: SpotterV2.Spacing.sm)

            HStack(spacing: SpotterV2.Spacing.xs) {
                if showsSkipButton {
                    V2LiveHUDButton(
                        theme: theme,
                        title: "Skip",
                        systemImage: "forward.fill",
                        reduceTransparency: reduceTransparency,
                        action: onSkip
                    )
                }

                if showsFinishButton {
                    V2LiveHUDButton(
                        theme: theme,
                        title: "Finish",
                        systemImage: "xmark",
                        reduceTransparency: reduceTransparency,
                        action: onFinish
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var warningBanner: some View {
        if let visibilityWarning {
            HStack(spacing: SpotterV2.Spacing.sm) {
                Image(systemName: "camera.metering.unknown")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
                Text(visibilityWarning)
                    .font(SpotterV2Typography.body(size: 13, weight: .black))
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .padding(SpotterV2.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                    .stroke(SpotterV2.Tokens.primary(theme).opacity(0.6), lineWidth: 1)
            )
        }
    }

    private var heroCounter: some View {
        HStack {
            Spacer()
            VStack(spacing: SpotterV2.Spacing.xxs) {
                Text(heroValue)
                    .font(SpotterV2Typography.mono(size: 92))
                    .italic()
                    .monospacedDigit()
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.44)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .shadow(color: .black.opacity(0.82), radius: 14, x: 0, y: 5)

                Text(heroCaption)
                    .font(SpotterV2Typography.caption())
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
                    .shadow(color: .black.opacity(0.75), radius: 6, x: 0, y: 2)
            }
            .padding(.horizontal, SpotterV2.Spacing.lg)
            .padding(.vertical, SpotterV2.Spacing.sm)
            .background(glassBackground)
            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl))
            .overlay(
                RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl)
                    .stroke(SpotterV2.Tokens.border.opacity(0.44), lineWidth: 1)
            )
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(heroCaption) \(heroValue)")
    }

    private var bottomCueCard: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            HStack(spacing: SpotterV2.Spacing.sm) {
                liveStatusPill
                V2GlassPill(theme: theme, label: "Effort \(effortTrend.label)", systemImage: effortTrend.systemImage)
                if let effortValueText {
                    V2GlassPill(theme: theme, label: effortValueText, systemImage: "face.smiling")
                }
                if let elapsedText {
                    V2GlassPill(theme: theme, label: elapsedText, systemImage: "timer")
                }
            }

            Text(cueText)
                .font(SpotterV2Typography.heading(size: 24))
                .fontWidth(.compressed)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .lineLimit(3)
                .minimumScaleFactor(0.58)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SpotterV2.Spacing.sm) {
                if let formScoreText {
                    V2LiveMetricTile(
                        theme: theme,
                        title: "Form",
                        value: formScoreText,
                        systemImage: "checkmark.seal.fill",
                        tint: SpotterV2.Tokens.chart1
                    )
                } else {
                    V2LiveMetricTile(
                        theme: theme,
                        title: "Form",
                        value: "Tracking",
                        systemImage: "waveform.path.ecg",
                        tint: SpotterV2.Tokens.chart1
                    )
                }

                V2LiveMetricTile(
                    theme: theme,
                    title: "Effort",
                    value: effortTrend.label,
                    systemImage: effortTrend.systemImage,
                    tint: SpotterV2.Tokens.primary(theme)
                )
            }
        }
        .padding(SpotterV2.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.xl)
                .stroke(SpotterV2.Tokens.border.opacity(0.42), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var liveStatusPill: some View {
        V2GlassPill(
            theme: theme,
            label: isLive ? "Live" : "Starting",
            systemImage: isLive ? "record.circle" : "hourglass"
        )
    }

    private var glassBackground: Color {
        reduceTransparency
            ? SpotterV2.Tokens.card
            : Color.black.opacity(0.62)
    }
}

private struct V2GlassPill: View {
    let theme: SpotterThemeOption
    let label: String
    let systemImage: String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: SpotterV2.Spacing.xxs) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.primary(theme))
            Text(label)
                .font(SpotterV2Typography.caption())
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, SpotterV2.Spacing.sm)
        .padding(.vertical, SpotterV2.Spacing.xs)
        .background(reduceTransparency ? SpotterV2.Tokens.card : Color.black.opacity(0.38))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(SpotterV2.Tokens.border.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

private struct V2LiveHUDButton: View {
    let theme: SpotterThemeOption
    let title: String
    let systemImage: String
    let reduceTransparency: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(SpotterV2Typography.caption(weight: .black))
                .tracking(1.0)
                .textCase(.uppercase)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(title == "Skip" ? .black : SpotterV2.Tokens.foreground)
                .padding(.horizontal, SpotterV2.Spacing.sm)
                .frame(minWidth: 76, minHeight: 40)
                .background(title == "Skip" ? SpotterV2.Tokens.primary(theme) : buttonBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(title == "Skip" ? Color.clear : SpotterV2.Tokens.border.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var buttonBackground: Color {
        reduceTransparency
            ? SpotterV2.Tokens.card
            : Color.black.opacity(0.58)
    }
}

private struct V2LiveMetricTile: View {
    let theme: SpotterThemeOption
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: SpotterV2.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                Text(title)
                    .font(SpotterV2Typography.caption())
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                Text(value)
                    .font(SpotterV2Typography.heading(size: 15))
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: SpotterV2.Spacing.xxs)
        }
        .padding(SpotterV2.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(SpotterV2.Tokens.secondary.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
private struct V2LiveWorkoutShellPreviewContent: View {
    let theme: SpotterThemeOption

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SpotterV2.Tokens.secondary,
                    SpotterV2.Tokens.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            V2LiveWorkoutShell(
                theme: theme,
                eyebrow: "Lower Body Engine",
                exerciseName: "Air Squat",
                setText: "Set 2 of 3",
                heroValue: "07",
                heroCaption: "Reps of 12",
                targetText: "12 reps",
                cameraViewText: "Side view",
                formScoreText: "92%",
                cueText: "Go deeper and keep your chest tall.",
                effortTrend: .rising,
                effortValueText: "74%",
                elapsedText: "1:22",
                visibilityWarning: nil,
                isLive: true,
                showsSkipButton: true,
                showsFinishButton: true,
                onSkip: {},
                onFinish: {}
            )
        }
    }
}

private struct V2LiveWorkoutShell_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2LiveWorkoutShellPreviewContent(theme: theme)
                    .previewDisplayName("\(theme.displayName) - SE")
                    .previewDevice("iPhone SE (3rd generation)")
                V2LiveWorkoutShellPreviewContent(theme: theme)
                    .previewDisplayName("\(theme.displayName) - Pro Max")
                    .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}
#endif
