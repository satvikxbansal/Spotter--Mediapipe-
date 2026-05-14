import Foundation

nonisolated struct BackendConfiguration {
    static let userDefaultsKey = "spotter.backendMode"

    /// Reads the desired backend mode from DEBUG-only overrides and build
    /// settings. Non-DEBUG builds stay local until Phase 19 promotes the
    /// production backend switch.
    static func desiredMode(
        bundle: Bundle = .main,
        userDefaults: UserDefaults = .standard
    ) -> BackendMode {
#if DEBUG
        if let raw = userDefaults.string(forKey: userDefaultsKey),
           let mode = BackendMode(rawValue: raw) {
            return mode
        }

        if let raw = bundle.object(forInfoDictionaryKey: "SPOTTER_BACKEND_MODE") as? String,
           let mode = BackendMode(rawValue: raw) {
            return mode
        }
#endif

        return .local
    }

#if DEBUG
    static func setDesiredMode(
        _ mode: BackendMode,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(mode.rawValue, forKey: userDefaultsKey)
    }
#endif
}
