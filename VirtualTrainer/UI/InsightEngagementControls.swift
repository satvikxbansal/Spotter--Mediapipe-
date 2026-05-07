import SwiftUI

struct InsightEngagementPrompt: View {
    let onSelect: (InsightEngagementKind) -> Void

    @State private var selectedKind: InsightEngagementKind?

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text("Was this helpful?")
                .font(.system(size: 11, weight: .black))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textTertiary)

            Spacer(minLength: Theme.Spacing.sm)

            engagementButton(kind: .helpful, systemImage: "hand.thumbsup.fill")
            engagementButton(kind: .notHelpful, systemImage: "hand.thumbsdown.fill")
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func engagementButton(
        kind: InsightEngagementKind,
        systemImage: String
    ) -> some View {
        Button {
            HapticsEngine.shared.buttonTap()
            selectedKind = kind
            onSelect(kind)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(selectedKind == kind ? Theme.Colors.background : Theme.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .background(selectedKind == kind ? Theme.Colors.accent : Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.Colors.divider, lineWidth: selectedKind == kind ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind == .helpful ? "Helpful" : "Not helpful")
    }
}
