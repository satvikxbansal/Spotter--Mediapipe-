import SwiftUI
import UIKit

struct V2OnboardingStatsView: View {
    let onBack: () -> Void
    let onNext: () -> Void

    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        V2OnboardingPage(
            theme: themeStore.selectedTheme,
            activeStep: 2,
            stepText: "02 / 04",
            title: "Enter your",
            accentTitle: "vitals",
            subtitle: "Used to personalize your daily coaching.",
            titleSize: 32,
            canContinue: onboardingStore.canContinue(from: .stats),
            onBack: onBack,
            onNext: onNext
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.lg) {
                V2MeasurementEntryCard(
                    theme: themeStore.selectedTheme,
                    title: "Height",
                    value: $onboardingStore.draft.height,
                    unit: Binding(
                        get: { onboardingStore.draft.heightUnit },
                        set: { onboardingStore.updateHeightUnit($0) }
                    ),
                    measurementKind: .height,
                    validationMessage: onboardingStore.heightValidationMessage
                )

                V2MeasurementEntryCard(
                    theme: themeStore.selectedTheme,
                    title: "Weight",
                    value: $onboardingStore.draft.weight,
                    unit: Binding(
                        get: { onboardingStore.draft.weightUnit },
                        set: { onboardingStore.updateWeightUnit($0) }
                    ),
                    measurementKind: .weight,
                    validationMessage: onboardingStore.weightValidationMessage
                )
            }
        }
        .accessibilityIdentifier("V2OnboardingStatsView")
    }
}

private enum V2MeasurementKind {
    case height
    case weight

    func unitLabel(for unit: UnitPreference) -> String {
        switch self {
        case .height:
            return unit.heightLabel
        case .weight:
            return unit.weightLabel
        }
    }

    var metricLabel: String {
        switch self {
        case .height:
            return "CM"
        case .weight:
            return "KG"
        }
    }

    var imperialLabel: String {
        switch self {
        case .height:
            return "IN"
        case .weight:
            return "LB"
        }
    }

    func scaleConfiguration(for unit: UnitPreference) -> V2ScaleConfiguration {
        switch (self, unit) {
        case (.height, .metric):
            return .heightMetric
        case (.height, .imperial):
            return .heightImperial
        case (.weight, .metric):
            return .weightMetric
        case (.weight, .imperial):
            return .weightImperial
        }
    }
}

private struct V2MeasurementEntryCard: View {
    let theme: SpotterThemeOption
    let title: String
    @Binding var value: String
    @Binding var unit: UnitPreference
    let measurementKind: V2MeasurementKind
    let validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            HStack(alignment: .center) {
                V2FieldLabel(title: title)
                Spacer(minLength: SpotterV2.Spacing.md)
                unitToggle
            }

            HStack(alignment: .lastTextBaseline, spacing: SpotterV2.Spacing.xs) {
                TextField(sampleValue, text: $value)
                    .font(SpotterV2Typography.display(size: 68))
                    .fontWidth(.compressed)
                    .italic()
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.42)
                    .accessibilityLabel(title)
                    .accessibilityValue(value.isEmpty ? "Empty" : value)

                Text(measurementKind.unitLabel(for: unit).uppercased())
                    .font(SpotterV2Typography.mono(size: 17, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
            }
            .frame(maxWidth: .infinity)

            V2ScrollableScalePicker(
                theme: theme,
                title: title,
                value: $value,
                configuration: measurementKind.scaleConfiguration(for: unit)
            )
            .id("\(measurementKind)-\(unit.rawValue)")

            V2ValidationMessage(message: validationMessage)
        }
        .padding(SpotterV2.Spacing.md)
        .background(SpotterV2.Tokens.card)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.xl)
                .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
        )
        .accessibilityElement(children: .contain)
    }

    private var sampleValue: String {
        switch measurementKind {
        case .height:
            return unit == .metric ? "178" : "70"
        case .weight:
            return unit == .metric ? "84.5" : "186"
        }
    }

    private var unitToggle: some View {
        HStack(spacing: SpotterV2.Spacing.xxs) {
            unitButton(label: measurementKind.metricLabel, unitValue: .metric)
            unitButton(label: measurementKind.imperialLabel, unitValue: .imperial)
        }
        .padding(SpotterV2.Spacing.xxs)
        .background(SpotterV2.Tokens.card)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(SpotterV2.Tokens.border.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) unit")
    }

    private func unitButton(label: String, unitValue: UnitPreference) -> some View {
        Button {
            unit = unitValue
        } label: {
            Text(label)
                .font(SpotterV2Typography.caption())
                .fontWidth(.compressed)
                .italic()
                .foregroundStyle(unit == unitValue ? .black : SpotterV2.Tokens.mutedForeground)
                .frame(minWidth: 48, minHeight: 32)
                .background(unit == unitValue ? SpotterV2.Tokens.primary(theme) : .clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(unit == unitValue ? "Selected" : "Not selected")
    }
}

#if DEBUG
private struct V2OnboardingStatsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2D3PreviewEnvironment(theme: theme) {
                    V2OnboardingStatsView(onBack: {}, onNext: {})
                }
                .previewDisplayName("\(theme.displayName) Stats SE")
                .previewDevice("iPhone SE (3rd generation)")

                V2D3PreviewEnvironment(theme: theme) {
                    V2OnboardingStatsView(onBack: {}, onNext: {})
                }
                .previewDisplayName("\(theme.displayName) Stats Pro Max")
                .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}
#endif
