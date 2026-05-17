import SwiftUI

struct V2RootView: View {
    @EnvironmentObject private var themeStore: ThemeStore
#if DEBUG
    @EnvironmentObject private var designSystemV2Toggle: DesignSystemV2ToggleStore
#endif

    var body: some View {
        ZStack {
            SpotterV2.Tokens.background
                .ignoresSafeArea()

            VStack(spacing: SpotterV2.Spacing.lg) {
                VStack(spacing: SpotterV2.Spacing.lg) {
                    Text("V2 Design System")
                        .font(SpotterV2Typography.display(size: 40))
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.primary(themeStore.selectedTheme))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.62)

                    Text("placeholder")
                        .font(SpotterV2Typography.caption())
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("V2 Design System placeholder")

#if DEBUG
                Button {
                    designSystemV2Toggle.setOverride(.forceOff)
                } label: {
                    Label("Return to V1", systemImage: "arrow.uturn.backward")
                        .font(SpotterV2Typography.caption())
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .padding(.horizontal, SpotterV2.Spacing.md)
                        .padding(.vertical, SpotterV2.Spacing.sm)
                        .background(SpotterV2.Tokens.secondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(SpotterV2.Tokens.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Return to V1")
                .accessibilityHint("Forces Design System V2 off in this debug build.")
#endif
            }
            .padding(SpotterV2.Spacing.xl)
        }
        .preferredColorScheme(.dark)
    }
}

private struct V2RootView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2RootPreviewHost(theme: theme)
                    .previewDisplayName("\(theme.displayName) - SE")
                    .previewDevice("iPhone SE (3rd generation)")
                V2RootPreviewHost(theme: theme)
                    .previewDisplayName("\(theme.displayName) - Pro Max")
                    .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}

private struct V2RootPreviewHost: View {
    let theme: SpotterThemeOption

    var body: some View {
        V2RootView()
            .environmentObject(ThemeStore(defaultTheme: theme))
            .environmentObject(
                DesignSystemV2ToggleStore(
                    remoteFlagSnapshotProvider: { true },
                    userDefaults: UserDefaults(suiteName: "V2RootPreview.DesignSystemV2.\(theme.rawValue)") ?? .standard
                )
            )
    }
}
