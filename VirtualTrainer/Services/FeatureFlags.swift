import Foundation

nonisolated enum FeatureFlag: String, Codable, CaseIterable, Hashable {
    case backendSyncEnabled
    case coachInsightLLMRewrite
    case runningAnalysisEnabled
    case designSystemV2Enabled
}

nonisolated struct FeatureFlags: Codable, Equatable {
    static let defaultQuickStartDeckVersion = "quick-start-deck-v1"
    static let defaultTrophyCatalogVersion = 1
    static let `default` = FeatureFlags(
        backendSyncEnabled: true,
        coachInsightLLMRewrite: false,
        quickStartDeckVersion: defaultQuickStartDeckVersion,
        trophyCatalogVersion: defaultTrophyCatalogVersion,
        runningAnalysisEnabled: false,
        designSystemV2Enabled: false
    )

    let backendSyncEnabled: Bool
    let coachInsightLLMRewrite: Bool
    let quickStartDeckVersion: String
    let trophyCatalogVersion: Int
    let runningAnalysisEnabled: Bool
    let designSystemV2Enabled: Bool

    private enum CodingKeys: String, CodingKey {
        case backendSyncEnabled
        case coachInsightLLMRewrite
        case quickStartDeckVersion
        case trophyCatalogVersion
        case runningAnalysisEnabled
        case designSystemV2Enabled
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case enabledFlags
    }

    init(
        backendSyncEnabled: Bool = true,
        coachInsightLLMRewrite: Bool = false,
        quickStartDeckVersion: String = FeatureFlags.defaultQuickStartDeckVersion,
        trophyCatalogVersion: Int = FeatureFlags.defaultTrophyCatalogVersion,
        runningAnalysisEnabled: Bool = false,
        designSystemV2Enabled: Bool = false
    ) {
        self.backendSyncEnabled = backendSyncEnabled
        self.coachInsightLLMRewrite = coachInsightLLMRewrite
        self.quickStartDeckVersion = quickStartDeckVersion
        self.trophyCatalogVersion = trophyCatalogVersion
        self.runningAnalysisEnabled = runningAnalysisEnabled
        self.designSystemV2Enabled = designSystemV2Enabled
    }

    init(enabledFlags: Set<FeatureFlag> = []) {
        self.init(
            backendSyncEnabled: true,
            coachInsightLLMRewrite: enabledFlags.contains(.coachInsightLLMRewrite),
            runningAnalysisEnabled: enabledFlags.contains(.runningAnalysisEnabled),
            designSystemV2Enabled: enabledFlags.contains(.designSystemV2Enabled)
        )
    }

    init(enabled: Set<FeatureFlag>) {
        self.init(enabledFlags: enabled)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyEnabledFlags = try legacyContainer.decodeIfPresent(
            Set<FeatureFlag>.self,
            forKey: .enabledFlags
        ) ?? []
        self.init(
            backendSyncEnabled: try container.decodeIfPresent(Bool.self, forKey: .backendSyncEnabled) ?? Self.default.backendSyncEnabled,
            coachInsightLLMRewrite: try container.decodeIfPresent(Bool.self, forKey: .coachInsightLLMRewrite)
                ?? legacyEnabledFlags.contains(.coachInsightLLMRewrite),
            quickStartDeckVersion: try container.decodeIfPresent(String.self, forKey: .quickStartDeckVersion) ?? Self.default.quickStartDeckVersion,
            trophyCatalogVersion: try container.decodeIfPresent(Int.self, forKey: .trophyCatalogVersion) ?? Self.default.trophyCatalogVersion,
            runningAnalysisEnabled: try container.decodeIfPresent(Bool.self, forKey: .runningAnalysisEnabled)
                ?? legacyEnabledFlags.contains(.runningAnalysisEnabled),
            designSystemV2Enabled: try container.decodeIfPresent(Bool.self, forKey: .designSystemV2Enabled)
                ?? legacyEnabledFlags.contains(.designSystemV2Enabled)
        )
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        switch flag {
        case .backendSyncEnabled:
            return backendSyncEnabled
        case .coachInsightLLMRewrite:
            return coachInsightLLMRewrite
        case .runningAnalysisEnabled:
            return runningAnalysisEnabled
        case .designSystemV2Enabled:
            return designSystemV2Enabled
        }
    }
}
