import Foundation

nonisolated enum SpotterAppRootRoute: Equatable {
    case v2Root
    case v1Onboarding
    case v1Calibration
    case v1MainTabs

    static func resolve(
        isDesignSystemV2Enabled: Bool,
        hasCompletedOnboarding: Bool,
        shouldShowCalibrationGate: Bool
    ) -> SpotterAppRootRoute {
        if isDesignSystemV2Enabled {
            return .v2Root
        }
        if !hasCompletedOnboarding {
            return .v1Onboarding
        }
        if shouldShowCalibrationGate {
            return .v1Calibration
        }
        return .v1MainTabs
    }
}

nonisolated enum V2RootRoute: Equatable {
    case onboarding
    case calibration
    case mainShell

    static func resolve(
        hasCompletedOnboarding: Bool,
        shouldShowCalibrationGate: Bool
    ) -> V2RootRoute {
        if !hasCompletedOnboarding {
            return .onboarding
        }
        if shouldShowCalibrationGate {
            return .calibration
        }
        return .mainShell
    }
}
