import CryptoKit
import FirebaseCrashlytics
import Foundation

protocol CrashReportingService {
    var isNoop: Bool { get }
    func configureLaunchContext(backendMode: BackendMode, schemaVersions: CrashlyticsSchemaVersions)
    func setAccountId(_ accountId: String?)
}

extension CrashReportingService {
    func configureLaunchContext(backendMode: BackendMode) {
        configureLaunchContext(
            backendMode: backendMode,
            schemaVersions: .current
        )
    }
}

nonisolated struct CrashlyticsSchemaVersions: Equatable {
    let onboarding: Int
    let profile: Int
    let workoutSummary: Int
    let trophyCatalog: Int
    let insightPolicy: String
    let piiRegistry: Int
    let localPlanCache: Int

    static let current = CrashlyticsSchemaVersions(
        onboarding: UserProfile.currentOnboardingSchemaVersion,
        profile: UserProfile.currentProfileSchemaVersion,
        workoutSummary: WorkoutSessionSummary.currentSchemaVersion,
        trophyCatalog: TrophyDefinitionCatalog.version,
        insightPolicy: AIInsight.currentSourcePolicyVersion,
        piiRegistry: PIIRegistry.schemaVersion,
        localPlanCache: 1
    )

    var crashlyticsValue: String {
        [
            "onboarding=\(onboarding)",
            "profile=\(profile)",
            "workoutSummary=\(workoutSummary)",
            "trophyCatalog=\(trophyCatalog)",
            "insightPolicy=\(insightPolicy)",
            "piiRegistry=\(piiRegistry)",
            "localPlanCache=\(localPlanCache)"
        ].joined(separator: ";")
    }
}

struct NoopCrashReportingService: CrashReportingService {
    let isNoop = true

    func configureLaunchContext(backendMode: BackendMode, schemaVersions: CrashlyticsSchemaVersions) {}

    func setAccountId(_ accountId: String?) {}
}

final class FirebaseCrashReportingService: CrashReportingService {
    let isNoop = false

    private let client: any CrashlyticsClient

    init(client: any CrashlyticsClient = FirebaseCrashlyticsClient()) {
        self.client = client
    }

    func configureLaunchContext(backendMode: BackendMode, schemaVersions: CrashlyticsSchemaVersions) {
        client.setCustomValue(backendMode.rawValue, forKey: "backendMode")
        client.setCustomValue(schemaVersions.crashlyticsValue, forKey: "schemaVersions")
    }

    func setAccountId(_ accountId: String?) {
        guard let accountId = AccountOwnership.normalizedAccountId(accountId) else {
            client.setUserID(nil)
            return
        }
        client.setUserID(Self.accountHashPrefix(accountId))
    }

    static func accountHashPrefix(_ accountId: String) -> String {
        let digest = SHA256.hash(data: Data(accountId.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

protocol CrashlyticsClient {
    func setCustomValue(_ value: Any?, forKey key: String)
    func setUserID(_ userID: String?)
}

struct FirebaseCrashlyticsClient: CrashlyticsClient {
    func setCustomValue(_ value: Any?, forKey key: String) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }

    func setUserID(_ userID: String?) {
        Crashlytics.crashlytics().setUserID(userID)
    }
}
