import Combine
import Foundation

nonisolated private func defaultFirebaseBootstrapState(in bundle: Bundle) -> FirebaseBootstrapState {
    AppRuntime.isRunningUnitTests
        ? .notAttempted
        : FirebaseBootstrap.configureIfAvailable(in: bundle)
}

@MainActor
final class BackendStatusStore: ObservableObject {
    @Published private(set) var desiredBackendMode: BackendMode
    @Published private(set) var activeBackendMode: BackendMode
    @Published private(set) var firebaseBootstrapState: FirebaseBootstrapState
    @Published private(set) var userFacingMessage: String?

    private let userDefaults: UserDefaults
    private let launchDesiredBackendMode: BackendMode
    private var didChangeDesiredModeInSession = false

    var requiresRestartToApplyDesiredMode: Bool {
        didChangeDesiredModeInSession &&
            desiredBackendMode != activeBackendMode &&
            desiredBackendMode != launchDesiredBackendMode
    }

    init(
        bundle: Bundle = .main,
        userDefaults: UserDefaults = .standard,
        firebaseBootstrapper: (Bundle) -> FirebaseBootstrapState = defaultFirebaseBootstrapState
    ) {
        self.userDefaults = userDefaults

        let desired = BackendConfiguration.desiredMode(
            bundle: bundle,
            userDefaults: userDefaults
        )
        launchDesiredBackendMode = desired
        desiredBackendMode = desired

        let bootstrapState: FirebaseBootstrapState = desired == .firebase
            ? firebaseBootstrapper(bundle)
            : .notAttempted
        let active = Self.activeMode(
            desired: desired,
            firebaseBootstrapState: bootstrapState
        )
        firebaseBootstrapState = bootstrapState
        activeBackendMode = active
        userFacingMessage = Self.message(
            for: bootstrapState,
            desired: desired,
            active: active,
            requiresRestart: false
        )
    }

#if DEBUG
    func setDesiredMode(_ mode: BackendMode) {
        BackendConfiguration.setDesiredMode(mode, userDefaults: userDefaults)
        didChangeDesiredModeInSession = true
        desiredBackendMode = mode
        userFacingMessage = Self.message(
            for: firebaseBootstrapState,
            desired: mode,
            active: activeBackendMode,
            requiresRestart: requiresRestartToApplyDesiredMode
        )
    }
#endif

    private static func activeMode(
        desired: BackendMode,
        firebaseBootstrapState: FirebaseBootstrapState
    ) -> BackendMode {
        guard desired == .firebase else { return .local }
        switch firebaseBootstrapState {
        case .configured, .alreadyConfigured:
            return .firebase
        case .notAttempted, .missingConfig, .failed:
            return .local
        }
    }

    private static func message(
        for state: FirebaseBootstrapState,
        desired: BackendMode,
        active: BackendMode,
        requiresRestart: Bool
    ) -> String? {
        if requiresRestart {
            return "Restart Spotter to apply \(desired.displayName) mode. This session is still using \(active.displayName) mode."
        }

        switch desired {
        case .local:
            return nil
        case .firebase:
            switch state {
            case .configured, .alreadyConfigured:
                return nil
            case .missingConfig:
                return "Firebase mode was requested, but GoogleService-Info.plist is not bundled. Spotter is staying in local mode."
            case .failed(let reason):
                return "Firebase mode was requested, but setup failed: \(reason) Spotter is staying in local mode."
            case .notAttempted:
                return active == .firebase ? nil : "Firebase mode was requested, but setup has not run. Spotter is staying in local mode."
            }
        case .supabase:
            return "Supabase mode is not implemented in this build. Spotter is staying in local mode."
        }
    }
}

nonisolated extension BackendMode {
    var displayName: String {
        switch self {
        case .local:
            return "local"
        case .firebase:
            return "firebase"
        case .supabase:
            return "supabase"
        }
    }
}

nonisolated extension FirebaseBootstrapState {
    var displayName: String {
        switch self {
        case .notAttempted:
            return "not attempted"
        case .configured:
            return "configured"
        case .missingConfig:
            return "missing config"
        case .alreadyConfigured:
            return "already configured"
        case .failed:
            return "failed"
        }
    }
}
