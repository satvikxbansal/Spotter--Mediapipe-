import XCTest
@testable import VirtualTrainer

@MainActor
final class Phase16JServicesTests: XCTestCase {
    func testRemoteConfigDefaultsAreHonoredWhenFetchFails() async {
        let defaults = FeatureFlags(
            backendSyncEnabled: true,
            coachInsightLLMRewrite: false,
            quickStartDeckVersion: "quick-start-deck-v1",
            trophyCatalogVersion: 1,
            runningAnalysisEnabled: false,
            designSystemV2Enabled: false
        )
        let client = ThrowingRemoteConfigClient(
            bools: [
                "backendSyncEnabled": false,
                "coachInsightLLMRewrite": true,
                "runningAnalysisEnabled": true,
                "designSystemV2Enabled": true
            ],
            strings: ["quickStartDeckVersion": "remote-deck-v99"],
            ints: ["trophyCatalogVersion": 99]
        )
        let service = RemoteFeatureFlagService(
            defaults: defaults,
            client: client,
            remoteEnabled: true
        )

        XCTAssertFalse(service.hasCompletedInitialRefresh)
        XCTAssertFalse(service.allowsBackendSync)

        await service.refresh()

        XCTAssertEqual(service.flags, defaults)
        XCTAssertTrue(service.hasCompletedInitialRefresh)
        XCTAssertTrue(service.allowsBackendSync)
        XCTAssertEqual(client.setDefaultsPayload?["backendSyncEnabled"] as? NSNumber, NSNumber(value: true))
        XCTAssertTrue(client.didAttemptFetch)
    }

    func testFeatureFlagsDecodeLegacyEnabledFlagsShape() throws {
        let data = Data(
            """
            {"enabledFlags":["coachInsightLLMRewrite","runningAnalysisEnabled","designSystemV2Enabled"]}
            """.utf8
        )

        let flags = try JSONDecoder().decode(FeatureFlags.self, from: data)

        XCTAssertTrue(flags.backendSyncEnabled)
        XCTAssertTrue(flags.coachInsightLLMRewrite)
        XCTAssertEqual(flags.quickStartDeckVersion, FeatureFlags.defaultQuickStartDeckVersion)
        XCTAssertEqual(flags.trophyCatalogVersion, FeatureFlags.defaultTrophyCatalogVersion)
        XCTAssertTrue(flags.runningAnalysisEnabled)
        XCTAssertTrue(flags.designSystemV2Enabled)
    }

    func testRemoteConfigSuccessAppliesOnlyValidOverrides() async {
        let client = SuccessfulRemoteConfigClient(
            bools: [
                "backendSyncEnabled": false,
                "coachInsightLLMRewrite": true,
                "runningAnalysisEnabled": true,
                "designSystemV2Enabled": true
            ],
            strings: ["quickStartDeckVersion": "  "],
            ints: ["trophyCatalogVersion": -4]
        )
        let service = RemoteFeatureFlagService(
            defaults: .default,
            client: client,
            remoteEnabled: true
        )

        await service.refresh()

        XCTAssertFalse(service.flags.backendSyncEnabled)
        XCTAssertTrue(service.hasCompletedInitialRefresh)
        XCTAssertFalse(service.allowsBackendSync)
        XCTAssertTrue(service.flags.coachInsightLLMRewrite)
        XCTAssertEqual(service.flags.quickStartDeckVersion, FeatureFlags.defaultQuickStartDeckVersion)
        XCTAssertEqual(service.flags.trophyCatalogVersion, FeatureFlags.defaultTrophyCatalogVersion)
        XCTAssertTrue(service.flags.runningAnalysisEnabled)
        XCTAssertTrue(service.flags.designSystemV2Enabled)
    }

    func testLocalAppDependenciesUseNoopObservabilityServices() async {
        let dependencies = AppDependencies.local()

        XCTAssertFalse(dependencies.analytics.emitsFirebaseCalls)
        XCTAssertTrue(dependencies.crashReporting.isNoop)
    }

    func testFirebaseAppDependenciesUseNoopObservabilityServicesInUnitTests() async {
        let defaults = UserDefaults(suiteName: "Phase16JServicesTests-\(UUID().uuidString)")!
        defaults.set(BackendMode.firebase.rawValue, forKey: BackendConfiguration.userDefaultsKey)
        let statusStore = BackendStatusStore(
            bundle: Bundle(for: Phase16JServicesTests.self),
            userDefaults: defaults,
            firebaseBootstrapper: { _ in .configured }
        )

        let dependencies = AppDependencies.from(statusStore)

        XCTAssertEqual(dependencies.backendMode, .firebase)
        XCTAssertFalse(dependencies.analytics.emitsFirebaseCalls)
        XCTAssertTrue(dependencies.crashReporting.isNoop)
    }

    func testNoopAnalyticsInLocalModeEmitsZeroFirebaseCalls() {
        let analytics: any AnalyticsService = NoopAnalyticsService()

        XCTAssertFalse(analytics.emitsFirebaseCalls)
        analytics.trackAppOpen()
        analytics.trackWorkoutSaved(mode: .freeAnalysis)
        analytics.trackSyncError(domain: "FirebaseFirestore")
    }

    func testAnalyticsEventCallsUseNoPIIKeys() {
        let recorder = RecordingAnalyticsService()

        recorder.trackAppOpen()
        recorder.trackOnboardingCompleted()
        recorder.trackCalibrationCompleted(outcome: .completed)
        recorder.trackWorkoutSaved(mode: .freeAnalysis)
        recorder.trackWorkoutSaved(mode: .plannedWorkout)
        recorder.trackTrophyUnlocked(id: "ten-session-streak", rarity: .rare)
        recorder.trackInsightImpression(type: .consistency, surface: .dashboard)
        recorder.trackInsightHelpful(type: .planAdjustment)
        recorder.trackInsightNotHelpful(type: .recovery)
        recorder.trackShareCardRendered(kind: .heatmap)
        recorder.trackShareCardRendered(kind: .trophy)
        recorder.trackShareCardRendered(kind: .recap)
        recorder.trackSyncError(domain: "FirebaseFirestore")

        XCTAssertEqual(Set(recorder.events.map(\.name)), Set(AnalyticsEventName.allCases))
        for event in recorder.events + AnalyticsEventCatalog.privacySamples {
            XCTAssertTrue(
                AnalyticsPrivacyGuard.isAllowed(event),
                "\(event.name.rawValue) included forbidden parameter keys: \(event.parameters.keys)"
            )
            XCTAssertTrue(
                Set(event.parameters.keys).isDisjoint(with: AnalyticsPrivacyGuard.forbiddenParameterKeys),
                "\(event.name.rawValue) included PII-like parameter keys."
            )
        }
    }

    func testAnalyticsPrivacyGuardRejectsCaseAndSeparatorVariants() {
        let event = AnalyticsEvent(
            .syncError,
            parameters: [
                "display_name": "athlete",
                "User-ID": "abc"
            ]
        )

        XCTAssertFalse(AnalyticsPrivacyGuard.isAllowed(event))
    }

    func testCrashReportingNoopsInUnitTests() {
        let crashReporting: any CrashReportingService = NoopCrashReportingService()

        XCTAssertTrue(crashReporting.isNoop)
        crashReporting.configureLaunchContext(backendMode: .local)
        crashReporting.setAccountId("uid-for-unit-test")
    }

    func testCrashlyticsAccountIdUsesSha256Prefix() {
        XCTAssertEqual(
            FirebaseCrashReportingService.accountHashPrefix("spotter-account"),
            "67dbe0d4"
        )
    }
}

private final class ThrowingRemoteConfigClient: RemoteConfigClient {
    enum TestError: Error {
        case fetchFailed
    }

    private let bools: [String: Bool]
    private let strings: [String: String]
    private let ints: [String: Int]

    private(set) var setDefaultsPayload: [String: NSObject]?
    private(set) var didAttemptFetch = false

    init(
        bools: [String: Bool] = [:],
        strings: [String: String] = [:],
        ints: [String: Int] = [:]
    ) {
        self.bools = bools
        self.strings = strings
        self.ints = ints
    }

    func setDefaults(_ defaults: [String: NSObject]) {
        setDefaultsPayload = defaults
    }

    func fetchAndActivate() async throws {
        didAttemptFetch = true
        throw TestError.fetchFailed
    }

    func boolValue(forKey key: String) -> Bool? {
        bools[key]
    }

    func stringValue(forKey key: String) -> String? {
        strings[key]
    }

    func intValue(forKey key: String) -> Int? {
        ints[key]
    }
}

private final class SuccessfulRemoteConfigClient: RemoteConfigClient {
    private let bools: [String: Bool]
    private let strings: [String: String]
    private let ints: [String: Int]

    init(
        bools: [String: Bool] = [:],
        strings: [String: String] = [:],
        ints: [String: Int] = [:]
    ) {
        self.bools = bools
        self.strings = strings
        self.ints = ints
    }

    func setDefaults(_ defaults: [String: NSObject]) {}

    func fetchAndActivate() async throws {}

    func boolValue(forKey key: String) -> Bool? {
        bools[key]
    }

    func stringValue(forKey key: String) -> String? {
        strings[key]
    }

    func intValue(forKey key: String) -> Int? {
        ints[key]
    }
}

private final class RecordingAnalyticsService: AnalyticsService {
    let emitsFirebaseCalls = false
    private(set) var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) {
        events.append(event)
    }
}
