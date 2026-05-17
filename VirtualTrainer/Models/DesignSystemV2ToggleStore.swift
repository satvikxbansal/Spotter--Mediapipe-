import Combine
import Foundation

enum DesignSystemV2Override: String, Codable, CaseIterable, Identifiable {
    case systemDefault
    case forceOff
    case forceOn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemDefault:
            return "System default"
        case .forceOff:
            return "Force off"
        case .forceOn:
            return "Force on"
        }
    }
}

@MainActor
final class DesignSystemV2ToggleStore: ObservableObject {
    static let userDefaultsKey = "spotter.designSystemV2Override"

    @Published private(set) var override: DesignSystemV2Override

    private let remoteFlagSnapshotProvider: () -> Bool
    private let userDefaults: UserDefaults

    init(
        remoteFlagSnapshotProvider: @escaping () -> Bool,
        userDefaults: UserDefaults = .standard
    ) {
        self.remoteFlagSnapshotProvider = remoteFlagSnapshotProvider
        self.userDefaults = userDefaults

#if DEBUG
        if let rawValue = userDefaults.string(forKey: Self.userDefaultsKey),
           let storedOverride = DesignSystemV2Override(rawValue: rawValue) {
            self.override = storedOverride
        } else {
            self.override = .systemDefault
        }
#else
        self.override = .systemDefault
#endif
    }

    nonisolated deinit {}

    var isEffectivelyEnabled: Bool {
#if DEBUG
        switch override {
        case .forceOn:
            return true
        case .forceOff:
            return false
        case .systemDefault:
            return remoteFlagSnapshotProvider()
        }
#else
        return remoteFlagSnapshotProvider()
#endif
    }

    func setOverride(_ override: DesignSystemV2Override) {
        self.override = override
#if DEBUG
        if override == .systemDefault {
            userDefaults.removeObject(forKey: Self.userDefaultsKey)
        } else {
            userDefaults.set(override.rawValue, forKey: Self.userDefaultsKey)
        }
#endif
    }
}
