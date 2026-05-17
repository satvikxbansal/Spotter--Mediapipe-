import Combine
import FirebaseRemoteConfig
import Foundation

protocol RemoteConfigClient: AnyObject {
    func setDefaults(_ defaults: [String: NSObject])
    func fetchAndActivate() async throws
    func boolValue(forKey key: String) -> Bool?
    func stringValue(forKey key: String) -> String?
    func intValue(forKey key: String) -> Int?
}

@MainActor
final class RemoteFeatureFlagService: ObservableObject {
    @Published private(set) var flags: FeatureFlags
    @Published private(set) var hasCompletedInitialRefresh = false

    private let defaults: FeatureFlags
    private let client: (any RemoteConfigClient)?
    private let remoteEnabled: Bool
    private var hasFetchedRemoteValues = false

    var allowsBackendSync: Bool {
        hasCompletedInitialRefresh && flags.backendSyncEnabled
    }

    init(
        defaults: FeatureFlags = .default,
        client: (any RemoteConfigClient)? = nil,
        remoteEnabled: Bool = false
    ) {
        self.defaults = defaults
        self.flags = defaults
        self.client = client
        self.remoteEnabled = remoteEnabled
    }

    static func local(defaults: FeatureFlags = .default) -> RemoteFeatureFlagService {
        RemoteFeatureFlagService(defaults: defaults, remoteEnabled: false)
    }

    static func firebase(defaults: FeatureFlags = .default) -> RemoteFeatureFlagService {
        RemoteFeatureFlagService(
            defaults: defaults,
            client: FirebaseRemoteConfigClient(),
            remoteEnabled: true
        )
    }

    func snapshot() -> FeatureFlags {
        flags
    }

    func refresh() async {
        guard remoteEnabled, let client else {
            flags = defaults
            hasCompletedInitialRefresh = true
            return
        }

        defer {
            hasCompletedInitialRefresh = true
        }

        client.setDefaults(defaults.remoteConfigDefaults)

        do {
            try await client.fetchAndActivate()
            hasFetchedRemoteValues = true
            flags = defaults.applyingRemoteOverrides(from: client)
        } catch {
            if !hasFetchedRemoteValues {
                flags = defaults
            }
        }
    }
}

extension FeatureFlags {
    var remoteConfigDefaults: [String: NSObject] {
        [
            RemoteFeatureFlagKey.backendSyncEnabled.rawValue: NSNumber(value: backendSyncEnabled),
            RemoteFeatureFlagKey.coachInsightLLMRewrite.rawValue: NSNumber(value: coachInsightLLMRewrite),
            RemoteFeatureFlagKey.quickStartDeckVersion.rawValue: quickStartDeckVersion as NSString,
            RemoteFeatureFlagKey.trophyCatalogVersion.rawValue: NSNumber(value: trophyCatalogVersion),
            RemoteFeatureFlagKey.runningAnalysisEnabled.rawValue: NSNumber(value: runningAnalysisEnabled),
            RemoteFeatureFlagKey.designSystemV2Enabled.rawValue: NSNumber(value: designSystemV2Enabled)
        ]
    }

    func applyingRemoteOverrides(from client: any RemoteConfigClient) -> FeatureFlags {
        FeatureFlags(
            backendSyncEnabled: client.boolValue(forKey: RemoteFeatureFlagKey.backendSyncEnabled.rawValue) ?? backendSyncEnabled,
            coachInsightLLMRewrite: client.boolValue(forKey: RemoteFeatureFlagKey.coachInsightLLMRewrite.rawValue) ?? coachInsightLLMRewrite,
            quickStartDeckVersion: nonEmptyRemoteString(
                client.stringValue(forKey: RemoteFeatureFlagKey.quickStartDeckVersion.rawValue),
                fallback: quickStartDeckVersion
            ),
            trophyCatalogVersion: positiveRemoteInt(
                client.intValue(forKey: RemoteFeatureFlagKey.trophyCatalogVersion.rawValue),
                fallback: trophyCatalogVersion
            ),
            runningAnalysisEnabled: client.boolValue(forKey: RemoteFeatureFlagKey.runningAnalysisEnabled.rawValue) ?? runningAnalysisEnabled,
            designSystemV2Enabled: client.boolValue(forKey: RemoteFeatureFlagKey.designSystemV2Enabled.rawValue) ?? designSystemV2Enabled
        )
    }

    private func nonEmptyRemoteString(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return fallback
        }
        return value
    }

    private func positiveRemoteInt(_ value: Int?, fallback: Int) -> Int {
        guard let value, value > 0 else { return fallback }
        return value
    }
}

private enum RemoteFeatureFlagKey: String, CaseIterable {
    case backendSyncEnabled
    case coachInsightLLMRewrite
    case quickStartDeckVersion
    case trophyCatalogVersion
    case runningAnalysisEnabled
    case designSystemV2Enabled
}

private final class FirebaseRemoteConfigClient: RemoteConfigClient {
    private let remoteConfig: RemoteConfig

    init(remoteConfig: RemoteConfig = .remoteConfig()) {
        self.remoteConfig = remoteConfig

        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3_600
        remoteConfig.configSettings = settings
    }

    func setDefaults(_ defaults: [String: NSObject]) {
        remoteConfig.setDefaults(defaults)
    }

    func fetchAndActivate() async throws {
        _ = try await remoteConfig.fetchAndActivate()
    }

    func boolValue(forKey key: String) -> Bool? {
        remoteConfig.configValue(forKey: key).boolValue
    }

    func stringValue(forKey key: String) -> String? {
        remoteConfig.configValue(forKey: key).stringValue
    }

    func intValue(forKey key: String) -> Int? {
        remoteConfig.configValue(forKey: key).numberValue.intValue
    }
}
