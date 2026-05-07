import Foundation

nonisolated enum FeatureFlag: String, Codable, CaseIterable, Hashable {
    case coachInsightLLMRewrite
}

nonisolated struct FeatureFlags: Codable, Equatable {
    static let `default` = FeatureFlags()

    private let enabledFlags: Set<FeatureFlag>

    init(enabledFlags: Set<FeatureFlag> = []) {
        self.enabledFlags = enabledFlags
    }

    init(enabled: Set<FeatureFlag>) {
        self.enabledFlags = enabled
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        enabledFlags.contains(flag)
    }
}
