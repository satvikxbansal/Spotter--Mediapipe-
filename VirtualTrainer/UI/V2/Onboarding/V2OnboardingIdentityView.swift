import SwiftUI
import UIKit

struct V2OnboardingIdentityView: View {
    let onBack: () -> Void
    let onNext: () -> Void

    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var themeStore: ThemeStore

    private var canContinue: Bool {
        onboardingStore.canContinue(from: .identity)
            && onboardingStore.draft.ageValue != nil
            && onboardingStore.ageValidationMessage == nil
    }

    private var ageMessage: String? {
        if onboardingStore.draft.age.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Age is required to personalize coaching."
        }
        return onboardingStore.ageValidationMessage
    }

    var body: some View {
        V2OnboardingPage(
            theme: themeStore.selectedTheme,
            activeStep: 1,
            stepText: "01 / 04",
            title: "Who are we",
            accentTitle: "training?",
            subtitle: "Spotter customizes coaching to your body.",
            canContinue: canContinue,
            onBack: onBack,
            onNext: onNext
        ) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                nameField
                genderSelector
                ageCard
            }
        }
        .accessibilityIdentifier("V2OnboardingIdentityView")
    }

    private var nameField: some View {
        HStack(spacing: SpotterV2.Spacing.md) {
            TextField("Satvik Bansal", text: $onboardingStore.draft.displayName)
                .font(SpotterV2Typography.heading(size: 25, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .accessibilityLabel("Display name")

            Image(systemName: "person.fill")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.mutedForeground.opacity(0.45))
        }
        .padding(.horizontal, SpotterV2.Spacing.lg)
        .frame(minHeight: 72)
        .background(SpotterV2.Tokens.card)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.xl)
                .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
        )
        .accessibilityLabel("Display name")
    }

    private var genderSelector: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SpotterV2.Spacing.md),
                    GridItem(.flexible(), spacing: SpotterV2.Spacing.md),
                    GridItem(.flexible(), spacing: SpotterV2.Spacing.md)
                ],
                spacing: SpotterV2.Spacing.md
            ) {
                V2CompactSelectorTile(
                    theme: themeStore.selectedTheme,
                    title: GenderIdentity.male.displayName,
                    systemImage: "person.fill",
                    isSelected: onboardingStore.draft.genderIdentity == .male
                ) {
                    onboardingStore.draft.genderIdentity = .male
                }

                V2CompactSelectorTile(
                    theme: themeStore.selectedTheme,
                    title: GenderIdentity.female.displayName,
                    systemImage: "person.fill",
                    isSelected: onboardingStore.draft.genderIdentity == .female
                ) {
                    onboardingStore.draft.genderIdentity = .female
                }

                V2CompactSelectorTile(
                    theme: themeStore.selectedTheme,
                    title: GenderIdentity.other.displayName,
                    systemImage: "person.crop.circle",
                    isSelected: onboardingStore.draft.genderIdentity == .other
                ) {
                    onboardingStore.draft.genderIdentity = .other
                }
            }

            V2TagToggle(
                theme: themeStore.selectedTheme,
                title: GenderIdentity.preferNotToSay.displayName,
                isSelected: onboardingStore.draft.genderIdentity == .preferNotToSay
            ) {
                onboardingStore.draft.genderIdentity = .preferNotToSay
            }
        }
    }

    private var ageCard: some View {
        V2ValueEntryCard(
            theme: themeStore.selectedTheme,
            title: "How many years young?",
            value: $onboardingStore.draft.age,
            unit: "yrs",
            keyboardType: .numberPad,
            validationMessage: ageMessage
        )
    }
}

struct V2ValueEntryCard: View {
    let theme: SpotterThemeOption
    let title: String
    @Binding var value: String
    let unit: String
    var keyboardType: UIKeyboardType = .decimalPad
    var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.lg) {
            V2FieldLabel(title: title)

            HStack(alignment: .lastTextBaseline, spacing: SpotterV2.Spacing.xs) {
                TextField("24", text: $value)
                    .font(SpotterV2Typography.display(size: 72))
                    .italic()
                    .multilineTextAlignment(.center)
                    .keyboardType(keyboardType)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .accessibilityLabel(title)
                    .accessibilityValue(value.isEmpty ? "Empty" : value)

                Text(unit.uppercased())
                    .font(SpotterV2Typography.mono(size: 18, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
            }
            .frame(maxWidth: .infinity)

            V2RulerStrip(theme: theme, value: value)

            V2ValidationMessage(message: validationMessage)
        }
        .padding(SpotterV2.Spacing.lg)
        .background(SpotterV2.Tokens.card)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.xl)
                .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
        )
        .accessibilityElement(children: .contain)
    }
}

struct V2RulerStrip: View {
    let theme: SpotterThemeOption
    let value: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                .fill(SpotterV2.Tokens.foreground.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                        .stroke(SpotterV2.Tokens.border.opacity(0.10), lineWidth: 1)
                )

            HStack(spacing: SpotterV2.Spacing.md) {
                Text(neighbor(-1))
                ticks
                Text(displayValue)
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
                ticks
                Text(neighbor(1))
            }
            .font(SpotterV2Typography.heading(size: 22, weight: .black))
            .foregroundStyle(SpotterV2.Tokens.foreground.opacity(0.22))
            .lineLimit(1)
            .minimumScaleFactor(0.70)

            Rectangle()
                .fill(SpotterV2.Tokens.primary(theme))
                .frame(width: 3, height: 54)
                .shadow(color: SpotterV2.Tokens.primary(theme).opacity(0.8), radius: 14)
        }
        .frame(height: 82)
        .accessibilityHidden(true)
    }

    private var displayValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "24" : trimmed
    }

    private var parsed: Double? {
        Double(displayValue)
    }

    private func neighbor(_ delta: Double) -> String {
        guard let parsed else { return delta < 0 ? "23" : "25" }
        let rounded = parsed + delta
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    private var ticks: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(SpotterV2.Tokens.foreground.opacity(index == 0 ? 0.45 : 0.18))
                    .frame(width: 1, height: index == 0 ? 18 : 9)
            }
        }
    }
}

#if DEBUG
private struct V2OnboardingIdentityView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2D3PreviewEnvironment(theme: theme) {
                    V2OnboardingIdentityView(onBack: {}, onNext: {})
                }
                .previewDisplayName("\(theme.displayName) Identity SE")
                .previewDevice("iPhone SE (3rd generation)")

                V2D3PreviewEnvironment(theme: theme) {
                    V2OnboardingIdentityView(onBack: {}, onNext: {})
                }
                .previewDisplayName("\(theme.displayName) Identity Pro Max")
                .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}
#endif
