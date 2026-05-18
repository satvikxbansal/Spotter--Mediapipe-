import SwiftUI

struct V2RootView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var calibrationStore: CalibrationStore
#if DEBUG
    @EnvironmentObject private var designSystemV2Toggle: DesignSystemV2ToggleStore
#endif

    private let routeOverride: V2RootRoute?
    private let navStyleOverride: V2NavStyle?

    init(routeOverride: V2RootRoute? = nil, navStyleOverride: V2NavStyle? = nil) {
        self.routeOverride = routeOverride
        self.navStyleOverride = navStyleOverride
    }

    var body: some View {
        Group {
            switch resolvedRoute {
            case .onboarding:
                V2OnboardingFlowView()
                    .accessibilityIdentifier("V2RootView.OnboardingGate")
            case .calibration:
                V2CalibrationIntroView()
                    .accessibilityIdentifier("V2RootView.CalibrationGate")
            case .mainShell:
                mainShell
                    .accessibilityIdentifier("V2RootView.MainShell")
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var mainShell: some View {
#if DEBUG
        V2MainShellView(
            navStyleOverride: navStyleOverride,
            onStartFirstRunDebug: resetFirstRunForDebug
        )
#else
        V2MainShellView(navStyleOverride: navStyleOverride)
#endif
    }

    private var resolvedRoute: V2RootRoute {
        routeOverride ?? V2RootRoute.resolve(
            hasCompletedOnboarding: onboardingStore.hasCompletedOnboarding,
            shouldShowCalibrationGate: calibrationStore.shouldShowCalibrationGate
        )
    }

#if DEBUG
    private func resetFirstRunForDebug() {
        Task { @MainActor in
            designSystemV2Toggle.setOverride(.forceOn)
            await calibrationStore.resetForDebug()
            await onboardingStore.resetOnboarding()
        }
    }
#endif
}

private struct V2RootView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2RootPreviewHost(theme: theme, route: .mainShell, reduceTransparency: false)
                    .previewDisplayName("\(theme.displayName) Root Glass SE")
                    .previewDevice("iPhone SE (3rd generation)")
                V2RootPreviewHost(theme: theme, route: .mainShell, reduceTransparency: true)
                    .previewDisplayName("\(theme.displayName) Root Solid Pro Max")
                    .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}

private struct V2RootPreviewHost: View {
    let theme: SpotterThemeOption
    let route: V2RootRoute
    let reduceTransparency: Bool
    @State private var appPresentation = AppLevelPresentationState()

    var body: some View {
        let dependencies = AppDependencies.local()
        V2RootView(routeOverride: route, navStyleOverride: reduceTransparency ? .solid : .liquidGlass)
            .environmentObject(AccountContext())
            .environmentObject(OnboardingStore())
            .environmentObject(CalibrationStore())
            .environmentObject(WorkoutHistoryStore())
            .environmentObject(TrophyStore())
            .environmentObject(ThemeStore(defaultTheme: theme))
            .environmentObject(InsightStore())
            .environmentObject(BackendStatusStore())
            .environmentObject(dependencies)
            .environmentObject(SyncOrchestrator(dependencies: dependencies))
            .environmentObject(RemoteFeatureFlagService.local())
            .environmentObject(
                DesignSystemV2ToggleStore(
                    remoteFlagSnapshotProvider: { true },
                    userDefaults: UserDefaults(suiteName: "V2RootPreview.DesignSystemV2.\(theme.rawValue)") ?? .standard
                )
            )
            .environment(\.appLevelPresenter, $appPresentation)
    }
}
