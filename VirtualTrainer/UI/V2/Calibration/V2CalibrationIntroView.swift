import SwiftUI

struct V2CalibrationIntroView: View {
    @EnvironmentObject private var appDependencies: AppDependencies
    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var themeStore: ThemeStore
    @State private var isStartingCalibration = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    backgroundIllustration

                    VStack(spacing: 0) {
                        Spacer()
                        sheetContent
                            .padding(.bottom, max(proxy.safeAreaInsets.bottom, SpotterV2.Spacing.xl))
                    }
                }
                .ignoresSafeArea(edges: .top)
                .background(SpotterV2.Tokens.background)
            }
            .navigationDestination(isPresented: $isStartingCalibration) {
                CalibrationSessionView()
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("V2CalibrationIntroView")
    }

    private var backgroundIllustration: some View {
        ZStack(alignment: .top) {
            SpotterV2.Tokens.background.ignoresSafeArea()

            Image(systemName: "iphone.gen3")
                .font(.system(size: 190, weight: .thin))
                .foregroundStyle(SpotterV2.Tokens.foreground.opacity(0.05))
                .rotationEffect(.degrees(-8))
                .offset(y: 110)
                .accessibilityHidden(true)

            VStack {
                HStack(spacing: SpotterV2.Spacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(SpotterV2.Tokens.primary(themeStore.selectedTheme))
                    Text("Position your phone")
                        .font(SpotterV2Typography.caption())
                        .italic()
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                }
                .padding(.horizontal, SpotterV2.Spacing.lg)
                .padding(.vertical, SpotterV2.Spacing.sm)
                .background(SpotterV2.Tokens.secondary.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                        .stroke(SpotterV2.Tokens.border.opacity(0.12), lineWidth: 1)
                )
                .padding(.top, 58)

                Spacer()
            }
        }
    }

    private var sheetContent: some View {
        VStack(spacing: SpotterV2.Spacing.xl) {
            Capsule()
                .fill(SpotterV2.Tokens.foreground.opacity(0.10))
                .frame(width: 64, height: 6)
                .accessibilityHidden(true)

            trophyIllustration

            VStack(spacing: SpotterV2.Spacing.md) {
                Text("Earn your")
                    .font(SpotterV2Typography.display(size: 45))
                    .italic()
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)

                Text("first trophy")
                    .font(SpotterV2Typography.display(size: 45))
                    .italic()
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.primary(themeStore.selectedTheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)

                Text("Track 3 air squats to proceed")
                    .font(SpotterV2Typography.caption())
                    .italic()
                    .tracking(2.2)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Earn your first trophy. Track 3 air squats to proceed.")

            if calibrationStore.status == .failed {
                failureNotice
            }

            if let error = calibrationStore.persistenceError {
                Text(error)
                    .font(SpotterV2Typography.body(size: 13, weight: .bold))
                    .foregroundStyle(SpotterV2.Tokens.destructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: SpotterV2.Spacing.lg) {
                V2CTAButton(
                    title: "Start Calibration",
                    systemImage: "arrow.right",
                    theme: themeStore.selectedTheme
                ) {
                    isStartingCalibration = true
                }

                V2SecondaryButton(
                    title: "Skip for now",
                    systemImage: nil,
                    theme: themeStore.selectedTheme
                ) {
                    Task {
                        if await calibrationStore.saveSkipped(notes: "Skipped during first-run calibration.") {
                            appDependencies.analytics.trackCalibrationCompleted(outcome: .skipped)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, SpotterV2.Spacing.xl)
        .padding(.top, SpotterV2.Spacing.md)
        .padding(.bottom, SpotterV2.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(SpotterV2.Tokens.background)
        .clipShape(RoundedRectangle(cornerRadius: 40))
        .overlay(
            RoundedRectangle(cornerRadius: 40)
                .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
        )
        .shadow(color: .black.opacity(0.80), radius: 28, y: -10)
    }

    private var trophyIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl)
                .fill(SpotterV2.Tokens.primary(themeStore.selectedTheme).opacity(0.16))
                .blur(radius: 26)
                .frame(width: 120, height: 120)

            Image(systemName: "trophy.fill")
                .font(.system(size: 58, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.primary(themeStore.selectedTheme))
                .frame(width: 98, height: 98)
                .background(SpotterV2.Tokens.card)
                .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl))
                .overlay(
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl)
                        .stroke(SpotterV2.Tokens.primary(themeStore.selectedTheme), lineWidth: SpotterV2.BorderWidth.standard)
                )
                .shadow(color: SpotterV2.Tokens.primary(themeStore.selectedTheme).opacity(0.28), radius: 18)
        }
        .accessibilityHidden(true)
    }

    private var failureNotice: some View {
        V2Card(
            theme: themeStore.selectedTheme,
            radius: SpotterV2.Radius.lg,
            borderColor: SpotterV2.Tokens.destructive.opacity(0.70)
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xs) {
                Text("Calibration did not finish")
                    .font(SpotterV2Typography.heading(size: 16))
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                Text(calibrationStore.record?.notes ?? "Retry now or skip and use Spotter without calibration.")
                    .font(SpotterV2Typography.body(size: 13, weight: .semibold))
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
private struct V2CalibrationIntroView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2D3PreviewEnvironment(theme: theme) {
                    V2CalibrationIntroView()
                }
                .previewDisplayName("\(theme.displayName) Calibration SE")
                .previewDevice("iPhone SE (3rd generation)")

                V2D3PreviewEnvironment(theme: theme) {
                    V2CalibrationIntroView()
                }
                .previewDisplayName("\(theme.displayName) Calibration Pro Max")
                .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}
#endif
