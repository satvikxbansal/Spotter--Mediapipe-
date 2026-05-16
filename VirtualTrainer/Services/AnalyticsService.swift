import FirebaseAnalytics
import Foundation

nonisolated enum AnalyticsEventName: String, CaseIterable, Hashable {
    case appOpen
    case onboardingCompleted
    case calibrationCompleted
    case workoutSaved
    case trophyUnlocked
    case insightImpression
    case insightHelpful
    case insightNotHelpful
    case shareCardRendered
    case syncError
}

nonisolated enum AnalyticsWorkoutMode: String, CaseIterable, Hashable {
    case freeAnalysis
    case plannedWorkout
}

nonisolated enum AnalyticsShareCardKind: String, CaseIterable, Hashable {
    case heatmap
    case trophy
    case recap
}

nonisolated struct AnalyticsEvent: Equatable {
    let name: AnalyticsEventName
    let parameters: [String: String]

    init(_ name: AnalyticsEventName, parameters: [String: String] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

protocol AnalyticsService {
    var emitsFirebaseCalls: Bool { get }
    func track(_ event: AnalyticsEvent)
}

extension AnalyticsService {
    func trackAppOpen() {
        track(AnalyticsEvent(.appOpen))
    }

    func trackOnboardingCompleted() {
        track(AnalyticsEvent(.onboardingCompleted))
    }

    func trackCalibrationCompleted(outcome: CalibrationStatus) {
        track(
            AnalyticsEvent(
                .calibrationCompleted,
                parameters: ["outcome": AnalyticsSanitizer.safeIdentifier(outcome.rawValue)]
            )
        )
    }

    func trackWorkoutSaved(mode: AnalyticsWorkoutMode) {
        track(
            AnalyticsEvent(
                .workoutSaved,
                parameters: ["mode": mode.rawValue]
            )
        )
    }

    func trackTrophyUnlocked(id: String, rarity: TrophyRarity) {
        track(
            AnalyticsEvent(
                .trophyUnlocked,
                parameters: [
                    "id": AnalyticsSanitizer.safeIdentifier(id),
                    "rarity": rarity.rawValue
                ]
            )
        )
    }

    func trackTrophyUnlocks(_ events: [TrophyUnlockEvent]) {
        for event in events {
            guard let definition = TrophyDefinitionCatalog.definition(for: event.trophyId) else {
                continue
            }
            trackTrophyUnlocked(id: event.trophyId, rarity: definition.rarity)
        }
    }

    func trackInsightImpression(type: InsightType, surface: InsightSurface) {
        track(
            AnalyticsEvent(
                .insightImpression,
                parameters: [
                    "type": type.rawValue,
                    "surface": surface.rawValue
                ]
            )
        )
    }

    func trackInsightHelpful(type: InsightType) {
        track(
            AnalyticsEvent(
                .insightHelpful,
                parameters: ["type": type.rawValue]
            )
        )
    }

    func trackInsightNotHelpful(type: InsightType) {
        track(
            AnalyticsEvent(
                .insightNotHelpful,
                parameters: ["type": type.rawValue]
            )
        )
    }

    func trackShareCardRendered(kind: AnalyticsShareCardKind) {
        track(
            AnalyticsEvent(
                .shareCardRendered,
                parameters: ["kind": kind.rawValue]
            )
        )
    }

    func trackSyncError(domain: String) {
        track(
            AnalyticsEvent(
                .syncError,
                parameters: ["domain": AnalyticsSanitizer.safeIdentifier(domain)]
            )
        )
    }
}

struct NoopAnalyticsService: AnalyticsService {
    let emitsFirebaseCalls = false

    func track(_ event: AnalyticsEvent) {}
}

final class FirebaseAnalyticsService: AnalyticsService {
    let emitsFirebaseCalls = true

    private let client: any FirebaseAnalyticsLogging

    init(client: any FirebaseAnalyticsLogging = FirebaseAnalyticsClient()) {
        self.client = client
    }

    func track(_ event: AnalyticsEvent) {
        guard AnalyticsPrivacyGuard.isAllowed(event) else { return }
        client.logEvent(
            event.name.rawValue,
            parameters: Dictionary(uniqueKeysWithValues: event.parameters.map { ($0.key, $0.value as Any) })
        )
    }
}

protocol FirebaseAnalyticsLogging {
    func logEvent(_ name: String, parameters: [String: Any]?)
}

struct FirebaseAnalyticsClient: FirebaseAnalyticsLogging {
    func logEvent(_ name: String, parameters: [String: Any]?) {
        Analytics.logEvent(name, parameters: parameters)
    }
}

nonisolated enum AnalyticsPrivacyGuard {
    static let forbiddenParameterKeys: Set<String> = [
        "displayName",
        "name",
        "firstName",
        "lastName",
        "email",
        "phone",
        "age",
        "gender",
        "genderIdentity",
        "height",
        "weight",
        "birthdate",
        "accountId",
        "uid",
        "userId",
        "rawVideo",
        "cameraFrame",
        "videoFrame",
        "faceImage",
        "rawPoseStream",
        "rawPoseTimeline",
        "rawLandmarks",
        "rawFaceBlendshapeStream",
        "biometricFaceData",
        "apiKey",
        "privateKey",
        "secret",
        "token"
    ]

    private static let normalizedForbiddenParameterKeys = Set(
        forbiddenParameterKeys.map(normalizedParameterKey)
    )

    static func isAllowed(_ event: AnalyticsEvent) -> Bool {
        event.parameters.keys.allSatisfy { key in
            !normalizedForbiddenParameterKeys.contains(normalizedParameterKey(key))
        }
    }

    private static func normalizedParameterKey(_ key: String) -> String {
        String(key.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
            .lowercased()
    }
}

nonisolated enum AnalyticsSanitizer {
    static func safeIdentifier(_ value: String, maxLength: Int = 80) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let scalars = value.unicodeScalars.map { scalar in
            String(allowed.contains(scalar) ? Character(scalar) : "_")
        }
        let sanitized = scalars.joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return String((sanitized.isEmpty ? "unknown" : sanitized).prefix(maxLength))
    }
}

nonisolated enum AnalyticsEventCatalog {
    static let privacySamples: [AnalyticsEvent] = [
        AnalyticsEvent(.appOpen),
        AnalyticsEvent(.onboardingCompleted),
        AnalyticsEvent(.calibrationCompleted, parameters: ["outcome": CalibrationStatus.completed.rawValue]),
        AnalyticsEvent(.workoutSaved, parameters: ["mode": AnalyticsWorkoutMode.freeAnalysis.rawValue]),
        AnalyticsEvent(.workoutSaved, parameters: ["mode": AnalyticsWorkoutMode.plannedWorkout.rawValue]),
        AnalyticsEvent(.trophyUnlocked, parameters: ["id": "spark", "rarity": TrophyRarity.common.rawValue]),
        AnalyticsEvent(.insightImpression, parameters: ["type": InsightType.consistency.rawValue, "surface": InsightSurface.dashboard.rawValue]),
        AnalyticsEvent(.insightHelpful, parameters: ["type": InsightType.planAdjustment.rawValue]),
        AnalyticsEvent(.insightNotHelpful, parameters: ["type": InsightType.recovery.rawValue]),
        AnalyticsEvent(.shareCardRendered, parameters: ["kind": AnalyticsShareCardKind.heatmap.rawValue]),
        AnalyticsEvent(.shareCardRendered, parameters: ["kind": AnalyticsShareCardKind.trophy.rawValue]),
        AnalyticsEvent(.shareCardRendered, parameters: ["kind": AnalyticsShareCardKind.recap.rawValue]),
        AnalyticsEvent(.syncError, parameters: ["domain": "FirebaseFirestore"])
    ]
}
