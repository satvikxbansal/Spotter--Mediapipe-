import SwiftUI
import UIKit
import XCTest
@testable import VirtualTrainer

@MainActor
final class DesignSystemV2Tests: XCTestCase {
    private static var retainedSnapshotWindows: [UIWindow] = []

    func testHexColorHelperRoundTrip() {
        assertColor(Color(hex: 0x0D0D0D), red: 13, green: 13, blue: 13)
        assertColor(Color(hex: 0xF2F0EB), red: 242, green: 240, blue: 235)
        assertColor(Color(hex: 0x00D1FF), red: 0, green: 209, blue: 255)
        assertColor(Color(hex: 0xFF5C3A), red: 255, green: 92, blue: 58)
    }

    func testSpotterV2TokensStayNamespacedFromV1ThemeTokens() {
        let v2TokenNames: Set<String> = [
            "SpotterV2.Tokens.background",
            "SpotterV2.Tokens.foreground",
            "SpotterV2.Tokens.secondary",
            "SpotterV2.Tokens.muted",
            "SpotterV2.Tokens.mutedForeground",
            "SpotterV2.Tokens.destructive",
            "SpotterV2.Tokens.card",
            "SpotterV2.Tokens.border",
            "SpotterV2.Tokens.chart1",
            "SpotterV2.Tokens.chart3",
            "SpotterV2.Tokens.chart4",
            "SpotterV2.Tokens.chart5"
        ]
        let v1TokenNames: Set<String> = [
            "Theme.Colors.background",
            "Theme.Colors.surface",
            "Theme.Colors.surfaceRaised",
            "Theme.Colors.textPrimary",
            "Theme.Colors.textSecondary",
            "Theme.Colors.textTertiary",
            "Theme.Colors.accent",
            "Theme.Colors.danger",
            "Theme.Colors.positive",
            "Theme.Colors.divider"
        ]

        XCTAssertTrue(v2TokenNames.isDisjoint(with: v1TokenNames))
    }

    func testToggleStoreForceOnWinsOverRemoteFalse() {
        let defaults = isolatedDefaults()
        let store = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { false },
            userDefaults: defaults
        )

        store.setOverride(.forceOn)

        XCTAssertTrue(store.isEffectivelyEnabled)
    }

    func testToggleStoreForceOffWinsOverRemoteTrue() {
        let defaults = isolatedDefaults()
        let store = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { true },
            userDefaults: defaults
        )

        store.setOverride(.forceOff)

        XCTAssertFalse(store.isEffectivelyEnabled)
    }

    func testToggleStoreSystemDefaultDelegatesToProvider() {
        let defaults = isolatedDefaults()
        var remoteFlag = false
        let store = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { remoteFlag },
            userDefaults: defaults
        )

        store.setOverride(.systemDefault)
        XCTAssertFalse(store.isEffectivelyEnabled)

        remoteFlag = true
        XCTAssertTrue(store.isEffectivelyEnabled)
    }

    func testToggleStorePersistsDebugOverrideAndClearsSystemDefault() {
        let defaults = isolatedDefaults()
        let firstStore = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { false },
            userDefaults: defaults
        )

        firstStore.setOverride(.forceOn)

        let persistedStore = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { false },
            userDefaults: defaults
        )
        XCTAssertEqual(persistedStore.override, .forceOn)
        XCTAssertTrue(persistedStore.isEffectivelyEnabled)

        persistedStore.setOverride(.systemDefault)

        let resetStore = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { false },
            userDefaults: defaults
        )
        XCTAssertEqual(resetStore.override, .systemDefault)
        XCTAssertFalse(resetStore.isEffectivelyEnabled)
    }

    func testToggleOffRoutesReadyUserToExistingMainTabs() {
        let route = SpotterAppRootRoute.resolve(
            isDesignSystemV2Enabled: false,
            hasCompletedOnboarding: true,
            shouldShowCalibrationGate: false
        )

        XCTAssertEqual(route, .v1MainTabs)
    }

    func testToggleOffKeepsExistingOnboardingAndCalibrationRoots() {
        XCTAssertEqual(
            SpotterAppRootRoute.resolve(
                isDesignSystemV2Enabled: false,
                hasCompletedOnboarding: false,
                shouldShowCalibrationGate: true
            ),
            .v1Onboarding
        )
        XCTAssertEqual(
            SpotterAppRootRoute.resolve(
                isDesignSystemV2Enabled: false,
                hasCompletedOnboarding: true,
                shouldShowCalibrationGate: true
            ),
            .v1Calibration
        )
    }

    func testToggleOnRoutesReadyUserToV2MainShell() {
        let appRoute = SpotterAppRootRoute.resolve(
            isDesignSystemV2Enabled: true,
            hasCompletedOnboarding: true,
            shouldShowCalibrationGate: false
        )
        let v2Route = V2RootRoute.resolve(
            hasCompletedOnboarding: true,
            shouldShowCalibrationGate: false
        )

        XCTAssertEqual(appRoute, .v2Root)
        XCTAssertEqual(v2Route, .mainShell)
    }

    func testV2RootPreservesOnboardingAndCalibrationGates() {
        XCTAssertEqual(
            V2RootRoute.resolve(
                hasCompletedOnboarding: false,
                shouldShowCalibrationGate: true
            ),
            .onboarding
        )
        XCTAssertEqual(
            V2RootRoute.resolve(
                hasCompletedOnboarding: true,
                shouldShowCalibrationGate: true
            ),
            .calibration
        )
    }

    func testSkippedCalibrationBypassesGateUntilCalibrationIsReset() async {
        let store = CalibrationStore(fileURL: temporaryDirectory().appendingPathComponent("CalibrationRecord.json"))

        XCTAssertTrue(store.shouldShowCalibrationGate)
        assertTrue(await store.saveSkipped(notes: "DEBUG first-run reset test."))
        XCTAssertFalse(store.shouldShowCalibrationGate)
        XCTAssertEqual(
            SpotterAppRootRoute.resolve(
                isDesignSystemV2Enabled: false,
                hasCompletedOnboarding: true,
                shouldShowCalibrationGate: store.shouldShowCalibrationGate
            ),
            .v1MainTabs
        )

        await store.resetForDebug()

        XCTAssertTrue(store.shouldShowCalibrationGate)
        XCTAssertEqual(
            SpotterAppRootRoute.resolve(
                isDesignSystemV2Enabled: false,
                hasCompletedOnboarding: true,
                shouldShowCalibrationGate: store.shouldShowCalibrationGate
            ),
            .v1Calibration
        )
    }

    func testSwitchingToggleDoesNotResetOnboardingThemeOrHistoryStores() async {
        let defaults = isolatedDefaults()
        let toggleStore = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: { false },
            userDefaults: defaults
        )
        let directory = temporaryDirectory()
        let onboardingStore = OnboardingStore(fileURL: directory.appendingPathComponent("UserProfile.json"))
        let themeStore = ThemeStore(fileURL: directory.appendingPathComponent("Theme.json"))
        let historyStore = WorkoutHistoryStore(fileURL: directory.appendingPathComponent("WorkoutHistory.json"))
        onboardingStore.draft = validDraft()

        let completedOnboarding = await onboardingStore.completeOnboarding()
        let updatedTheme = await themeStore.updateSelectedTheme(.spicy)
        let addedSummary = await historyStore.addSummary(sampleSummary())

        XCTAssertTrue(completedOnboarding)
        XCTAssertTrue(updatedTheme)
        XCTAssertTrue(addedSummary)

        toggleStore.setOverride(.forceOn)
        toggleStore.setOverride(.forceOff)

        XCTAssertEqual(onboardingStore.profile?.displayName, "Test Athlete")
        XCTAssertTrue(onboardingStore.hasCompletedOnboarding)
        XCTAssertEqual(themeStore.selectedTheme, .spicy)
        XCTAssertEqual(historyStore.summaries.count, 1)
        XCTAssertEqual(historyStore.summaries.first?.title, "Squats")
    }

    func testReduceTransparencyResolvesSolidNavStyle() {
        XCTAssertEqual(V2NavStyle.resolved(reduceTransparency: false), .liquidGlass)
        XCTAssertEqual(V2NavStyle.resolved(reduceTransparency: true), .solid)
    }

    func testD4V2DashboardStartsSelectedQuickStartPlan() throws {
        var content = makeD4DashboardContent(goal: .performance, level: .intermediate)
        content.advanceSmartStartPlan()
        let selectedVariant = content.currentSmartStart

        let selectedPlan = V2DashboardPlanActions.selectedQuickStartPlan(from: content)

        XCTAssertEqual(selectedPlan.id, selectedVariant.plan.id)
        XCTAssertEqual(selectedPlan.title, selectedVariant.plan.title)
    }

    func testD4V2DashboardShuffleCyclesQuickStartDeck() throws {
        let content = makeD4DashboardContent(goal: .strength, level: .intermediate)
        let firstPlanID = content.currentSmartStart.plan.id

        let shuffled = V2DashboardPlanActions.shuffledContent(from: content)

        XCTAssertEqual(shuffled.selectedSmartStartIndex, 1)
        XCTAssertNotEqual(shuffled.currentSmartStart.plan.id, firstPlanID)
    }

    func testD4CoachInsightCardSurfacesWhenInsightEngineHasDashboardCandidate() async throws {
        let now = date(year: 2026, month: 5, day: 7, hour: 12)
        let profile = makeD4Profile(goal: .strength, level: .intermediate)
        let history = [
            sampleSummary(
                title: "Push-ups",
                exerciseType: .pushup,
                endedAt: now,
                totalReps: 16,
                averageFormScore: 92
            ),
            sampleSummary(
                title: "Squats",
                exerciseType: .squat,
                endedAt: date(year: 2026, month: 5, day: 6, hour: 12),
                totalReps: 18,
                averageFormScore: 88
            )
        ]
        let trophies = trophySnapshot(now: now)
        let trendEngine = TrendEngine(calendar: d4Calendar)
        let trendSnapshot = trendEngine.buildSnapshot(
            history: history,
            profile: profile,
            trophies: trophies,
            now: now
        )
        let signals = SignalExtractor(trendEngine: trendEngine).extractSignals(
            snapshot: trendSnapshot,
            history: history,
            profile: profile,
            trophies: trophies,
            context: SignalGenerationContext(historySessionCount: history.count)
        )

        let generatedInsights = await InsightEngine().generateDashboardInsights(
            profile: profile,
            trendSnapshot: trendSnapshot,
            signals: signals,
            trophies: trophies,
            now: now
        )
        let insight = try XCTUnwrap(generatedInsights.first { $0.surfaces.contains(.dashboard) })

        XCTAssertTrue(V2DashboardInsightPresentation.shouldSurface(insight))
    }

    func testD4V2CameraTabLaunchesFreeAnalysisWithSameArgsAsV1() {
        let profile = makeD4Profile(coach: .fletcher)

        let v1Launch = FreeAnalysisCameraLaunchConfiguration.make(
            exerciseType: .squat,
            profile: profile
        )
        let v2Launch = FreeAnalysisCameraLaunchConfiguration.make(
            exerciseType: .squat,
            profile: profile
        )

        XCTAssertEqual(v1Launch, v2Launch)
        XCTAssertEqual(v2Launch.exerciseType, .squat)
        XCTAssertEqual(v2Launch.coach, .drill)
    }

    func testD4BackendBannerAppearsOnlyWhenFallbackActive() {
        XCTAssertTrue(
            V2BackendFallbackBannerModel.shouldShow(
                desired: .firebase,
                active: .local,
                message: "Firebase mode was requested, but setup failed.",
                isDismissed: false
            )
        )
        XCTAssertFalse(
            V2BackendFallbackBannerModel.shouldShow(
                desired: .firebase,
                active: .firebase,
                message: nil,
                isDismissed: false
            )
        )
        XCTAssertFalse(
            V2BackendFallbackBannerModel.shouldShow(
                desired: .firebase,
                active: .local,
                message: "Firebase mode was requested, but setup failed.",
                isDismissed: true
            )
        )
    }

    func testD4V1DashboardRouteRemainsUntouchedWhenToggleOff() {
        XCTAssertEqual(
            SpotterAppRootRoute.resolve(
                isDesignSystemV2Enabled: false,
                hasCompletedOnboarding: true,
                shouldShowCalibrationGate: false
            ),
            .v1MainTabs
        )
    }

    func testSnapshotSmokeForCoreV2ComponentsAcrossHyperAndHotGirlThemes() throws {
        for theme in [SpotterThemeOption.hyper, .hotGirl] {
            try renderSnapshot(
                name: "V2Card-\(theme.rawValue)",
                view: V2Card(
                    theme: theme,
                    hardShadowColor: SpotterV2.Tokens.primary(theme)
                ) {
                    Text("V2 CARD")
                        .font(SpotterV2Typography.heading(size: 22))
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                }
            )

            try renderSnapshot(
                name: "V2CTAButton-\(theme.rawValue)",
                view: V2CTAButton(
                    title: "Start Training",
                    systemImage: "bolt.fill",
                    theme: theme,
                    action: {}
                )
            )

            try renderSnapshot(
                name: "V2MetricPill-\(theme.rawValue)",
                view: V2MetricPill(
                    theme: theme,
                    eyebrow: "Form quality",
                    value: "94%",
                    detail: "Smoke render",
                    systemImage: "brain.head.profile"
                )
            )
        }
    }

    func testSnapshotSmokeForV2MainShellPlaceholders() throws {
        for theme in [SpotterThemeOption.hyper, .warm] {
            try renderSnapshot(
                name: "V2MainShell-\(theme.rawValue)",
                view: V2MainShellSnapshotHost(theme: theme, selectedTab: .dashboard)
            )
            try renderSnapshot(
                name: "V2LiquidGlassTabBar-\(theme.rawValue)",
                view: V2TabBarSnapshotHost(theme: theme, selectedTab: .profile)
            )
        }
    }

    func testSnapshotSmokeForD4V2DashboardStatesAcrossHyperAndHotGirlThemes() async throws {
        let sizes: [(String, CGSize)] = [
            ("SE", CGSize(width: 375, height: 667)),
            ("ProMax", CGSize(width: 440, height: 956))
        ]

        for theme in [SpotterThemeOption.hyper, .hotGirl] {
            for richHistory in [false, true] {
                for (sizeName, size) in sizes {
                    let stateName = richHistory ? "Rich" : "Empty"
                    let environment = await makeD4DashboardSnapshotEnvironment(
                        theme: theme,
                        richHistory: richHistory
                    )
                    try renderScreenSnapshot(
                        name: "D4Dashboard-\(stateName)-\(theme.rawValue)-\(sizeName)",
                        size: size,
                        view: D4DashboardSnapshotHost(environment: environment),
                        minimumVisiblePixelRatio: 0.08
                    )
                }
            }
        }
    }

    func testV2OnboardingDraftCompletesAndWritesUserProfile() async {
        let store = OnboardingStore(fileURL: temporaryDirectory().appendingPathComponent("V2UserProfile.json"))
        store.draft = validV2Draft()

        assertTrue(await store.completeOnboarding())

        XCTAssertEqual(store.profile?.displayName, "V2 Athlete")
        XCTAssertEqual(store.profile?.genderIdentity, .female)
        XCTAssertEqual(store.profile?.age, 29)
        XCTAssertEqual(store.profile?.height, 168)
        XCTAssertEqual(store.profile?.weight, 64.5)
        XCTAssertEqual(store.profile?.primaryGoal, .performance)
        XCTAssertEqual(store.profile?.fitnessLevel, .intermediate)
        XCTAssertEqual(Set(store.profile?.equipment ?? []), [.bodyweight, .dumbbells])
        XCTAssertEqual(store.profile?.limitations, [.wristSensitive])
        XCTAssertEqual(store.profile?.preferredSessionLength, .thirtyFive)
        XCTAssertEqual(store.profile?.workoutDaysPerWeek, 5)
    }

    func testV2CalibrationCompletionStillUsesCalibrationStoreContract() async throws {
        let store = CalibrationStore(fileURL: temporaryDirectory().appendingPathComponent("V2CalibrationRecord.json"))
        let startedAt = Date(timeIntervalSince1970: 1_779_000_000)
        let completedAt = Date(timeIntervalSince1970: 1_779_000_036)
        let record = CalibrationRecord.completed(
            exerciseType: CalibrationDefaults.exerciseType,
            targetReps: CalibrationDefaults.targetReps,
            completedReps: CalibrationDefaults.targetReps,
            startedAt: startedAt,
            completedAt: completedAt,
            visibilityPassed: true,
            averageFormScore: 92
        )

        assertTrue(await store.saveCompleted(record))

        let saved = try XCTUnwrap(store.record)
        XCTAssertEqual(saved.exerciseType, CalibrationDefaults.exerciseType)
        XCTAssertEqual(saved.targetReps, CalibrationDefaults.targetReps)
        XCTAssertEqual(saved.completedReps, CalibrationDefaults.targetReps)
        XCTAssertEqual(saved.startedAt, startedAt)
        XCTAssertEqual(saved.completedAt, completedAt)
        XCTAssertEqual(saved.visibilityPassed, true)
        XCTAssertEqual(saved.averageFormScore, 92)
    }

    func testV2CameraReadinessDeniedStateShowsSettingsCTA() {
        let state = V2CameraReadinessAdapter.makeState(
            permissionStatus: .denied,
            visibilityResult: BodyVisibilityChecker.Result(
                isReady: false,
                visibility: 0,
                message: "Camera access is unavailable.",
                missingJoints: []
            ),
            coordinatorState: .positioning,
            setupInstruction: "Make sure your body fits in frame."
        )

        XCTAssertEqual(state.kind, .permissionDenied)
        XCTAssertEqual(state.secondaryActionTitle, "Open Settings")
        XCTAssertNil(state.primaryActionTitle)
    }

    func testV2WelcomeLoginDeltaIsComingSoonOnly() {
        XCTAssertEqual(V2WelcomeView.loginComingSoonTitle, "Sign in with Apple is coming soon")
        XCTAssertTrue(V2WelcomeView.loginComingSoonMessage.contains("local-first"))
    }

    func testV2OnboardingScaleConfigurationsStayInsideStoreValidationRanges() {
        XCTAssertEqual(V2ScaleConfiguration.age.lowerBound, 13)
        XCTAssertEqual(V2ScaleConfiguration.age.upperBound, 100)
        XCTAssertEqual(V2ScaleConfiguration.heightMetric.lowerBound, 120)
        XCTAssertEqual(V2ScaleConfiguration.heightMetric.upperBound, 230)
        XCTAssertEqual(V2ScaleConfiguration.heightImperial.lowerBound, 48)
        XCTAssertEqual(V2ScaleConfiguration.heightImperial.upperBound, 90)
        XCTAssertEqual(V2ScaleConfiguration.weightMetric.lowerBound, 30)
        XCTAssertEqual(V2ScaleConfiguration.weightMetric.upperBound, 250)
        XCTAssertEqual(V2ScaleConfiguration.weightImperial.lowerBound, 66)
        XCTAssertEqual(V2ScaleConfiguration.weightImperial.upperBound, 550)
    }

    func testV2OnboardingScaleFormattingStaysParseableForDraftValues() {
        XCTAssertEqual(
            V2ScaleConfiguration.age.formattedValue(
                for: V2ScaleConfiguration.age.index(for: 34)
            ),
            "34"
        )
        XCTAssertEqual(
            V2ScaleConfiguration.weightMetric.formattedValue(
                for: V2ScaleConfiguration.weightMetric.index(for: 84.5)
            ),
            "84.5"
        )
        XCTAssertEqual(Double(V2ScaleConfiguration.weightMetric.formattedValue(84.5)), 84.5)
        XCTAssertEqual(Int(V2ScaleConfiguration.heightImperial.formattedValue(70)), 70)
    }

    func testSnapshotSmokeForD3V2ScreensAcrossDeviceSizesAndLaunchThemes() throws {
        let sizes: [(String, CGSize)] = [
            ("SE", CGSize(width: 375, height: 667)),
            ("Pro", CGSize(width: 402, height: 874)),
            ("ProMax", CGSize(width: 440, height: 956))
        ]

        for theme in [SpotterThemeOption.hyper, .hotGirl] {
            for (sizeName, size) in sizes {
                try renderScreenSnapshot(
                    name: "D3Welcome-\(theme.rawValue)-\(sizeName)",
                    size: size,
                    view: D3OnboardingScreenSnapshotHost(theme: theme, screen: .welcome)
                )
                try renderScreenSnapshot(
                    name: "D3Identity-\(theme.rawValue)-\(sizeName)",
                    size: size,
                    view: D3OnboardingScreenSnapshotHost(theme: theme, screen: .identity)
                )
                try renderScreenSnapshot(
                    name: "D3Stats-\(theme.rawValue)-\(sizeName)",
                    size: size,
                    view: D3OnboardingScreenSnapshotHost(theme: theme, screen: .stats)
                )
                try renderScreenSnapshot(
                    name: "D3Objective-\(theme.rawValue)-\(sizeName)",
                    size: size,
                    view: D3OnboardingScreenSnapshotHost(theme: theme, screen: .objective)
                )
                try renderScreenSnapshot(
                    name: "D3Calibration-\(theme.rawValue)-\(sizeName)",
                    size: size,
                    view: D3CalibrationIntroSnapshotHost(theme: theme)
                )
                try renderScreenSnapshot(
                    name: "D3CameraReady-\(theme.rawValue)-\(sizeName)",
                    size: size,
                    view: D3CameraReadinessSnapshotHost(theme: theme, state: .ready)
                )
            }
        }
    }
}

private extension DesignSystemV2Tests {
    func isolatedDefaults() -> UserDefaults {
        let suiteName = "DesignSystemV2Tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite.")
            return .standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesignSystemV2Tests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            XCTFail("Could not create temp directory: \(error)")
        }
        return directory
    }

    var d4Calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        d4Calendar.date(
            from: DateComponents(
                timeZone: d4Calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        ) ?? Date(timeIntervalSince1970: 1_778_000_000)
    }

    func validDraft() -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft.displayName = "Test Athlete"
        draft.genderIdentity = .preferNotToSay
        draft.age = "30"
        draft.height = "175"
        draft.weight = "72"
        draft.primaryGoal = .strength
        draft.fitnessLevel = .beginner
        draft.equipment = [.bodyweight, .mat]
        return draft
    }

    func validV2Draft() -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft.displayName = "V2 Athlete"
        draft.genderIdentity = .female
        draft.age = "29"
        draft.height = "168"
        draft.weight = "64.5"
        draft.primaryGoal = .performance
        draft.fitnessLevel = .intermediate
        draft.equipment = [.bodyweight, .dumbbells]
        draft.limitations = [.wristSensitive]
        draft.preferredSessionLength = .thirtyFive
        draft.workoutDaysPerWeek = 5
        return draft
    }

    func makeD4Profile(
        goal: FitnessGoal = .strength,
        level: FitnessLevel = .intermediate,
        coach: CoachPreference = .bennett,
        theme: SpotterThemeOption = .hyper
    ) -> UserProfile {
        let now = date(year: 2026, month: 5, day: 7)
        return UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000004004") ?? UUID(),
            displayName: "Test Athlete",
            genderIdentity: .preferNotToSay,
            age: 30,
            height: 175,
            heightUnit: .metric,
            weight: 72,
            weightUnit: .metric,
            primaryGoal: goal,
            fitnessLevel: level,
            equipment: [.bodyweight, .dumbbells, .mat, .wall],
            preferredCoach: coach,
            selectedTheme: theme,
            limitations: [],
            preferredSessionLength: .twentyFive,
            workoutDaysPerWeek: 4,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    func makeD4DashboardContent(
        goal: FitnessGoal,
        level: FitnessLevel
    ) -> DashboardContent {
        let factory = DashboardContentFactory(
            planService: PlanService(
                quickStartDeckService: QuickStartPlanDeckService(calendar: d4Calendar)
            ),
            calendar: d4Calendar
        )
        return factory.makeContent(
            profile: makeD4Profile(goal: goal, level: level),
            now: date(year: 2026, month: 5, day: 7)
        )
    }

    func sampleSummary() -> WorkoutSessionSummary {
        let endedAt = Date(timeIntervalSince1970: 1_778_067_200)
        return WorkoutSessionSummary(
            mode: .freeAnalysis,
            title: "Squats",
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-72),
            endedAt: endedAt,
            durationSeconds: 72,
            totalReps: 12,
            totalHoldSeconds: 0,
            averageFormScore: 91,
            exerciseSummaries: [],
            topCue: nil,
            effortSummary: "Sample free analysis session."
        )
    }

    func sampleSummary(
        title: String,
        exerciseType: ExerciseType,
        endedAt: Date,
        totalReps: Int,
        averageFormScore: Double
    ) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            mode: .freeAnalysis,
            title: title,
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-420),
            endedAt: endedAt,
            durationSeconds: 420,
            totalReps: totalReps,
            totalHoldSeconds: exerciseType == .plank ? 90 : 0,
            averageFormScore: averageFormScore,
            exerciseSummaries: [
                ExerciseSetSummary(
                    exerciseType: exerciseType,
                    setIndex: 1,
                    achievedReps: totalReps,
                    achievedHoldSeconds: exerciseType == .plank ? 90 : 0,
                    averageFormScore: averageFormScore
                )
            ],
            topCue: nil,
            effortSummary: "D4 dashboard snapshot session."
        )
    }

    func trophySnapshot(now: Date) -> TrophyProgressSnapshot {
        TrophyProgressSnapshot(
            catalogVersion: TrophyDefinitionCatalog.version,
            generatedAt: now,
            progress: TrophyDefinitionCatalog.all.map { definition in
                TrophyProgress(
                    trophyId: definition.id,
                    currentValue: 0,
                    targetValue: definition.targetValue,
                    earned: false,
                    earnedAt: nil,
                    lastUpdatedAt: now,
                    confidence: definition.isComingSoon ? .unavailable : .exact,
                    progressLabel: "0/\(Int(definition.targetValue)) \(definition.unit)"
                )
            },
            newlyEarnedEvents: []
        )
    }

    func makeD4DashboardSnapshotEnvironment(
        theme: SpotterThemeOption,
        richHistory: Bool
    ) async -> D4DashboardSnapshotEnvironment {
        let directory = temporaryDirectory()
        let onboardingStore = OnboardingStore(fileURL: directory.appendingPathComponent("UserProfile.json"))
        let historyStore = WorkoutHistoryStore(fileURL: directory.appendingPathComponent("WorkoutHistory.json"))
        let trophyStore = TrophyStore(fileURL: directory.appendingPathComponent("TrophyProgress.json"), calendar: d4Calendar)
        let profile = makeD4Profile(theme: theme)

        if richHistory {
            for summary in [
                sampleSummary(
                    title: "Push-ups",
                    exerciseType: .pushup,
                    endedAt: date(year: 2026, month: 5, day: 7),
                    totalReps: 20,
                    averageFormScore: 94
                ),
                sampleSummary(
                    title: "Squats",
                    exerciseType: .squat,
                    endedAt: date(year: 2026, month: 5, day: 6),
                    totalReps: 18,
                    averageFormScore: 89
                ),
                sampleSummary(
                    title: "Plank",
                    exerciseType: .plank,
                    endedAt: date(year: 2026, month: 5, day: 5),
                    totalReps: 0,
                    averageFormScore: 87
                )
            ] {
                assertTrue(await historyStore.addSummary(summary))
            }
        }
        let snapshotNow = date(year: 2026, month: 5, day: 7)
        let calibrationStore = CalibrationStore(fileURL: directory.appendingPathComponent("CalibrationRecord.json"))
        await trophyStore.updateAll(
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status,
            now: snapshotNow
        )
        let dashboardContent = DashboardContentFactory(calendar: d4Calendar).makeContent(
            profile: profile,
            now: snapshotNow,
            recentWorkoutHistory: historyStore.recentWorkoutHistoryItems(),
            currentStreakDayCount: historyStore.aggregateStats(now: snapshotNow).currentStreak,
            trophySnapshot: trophyStore.snapshot,
            featureFlags: FeatureFlags(designSystemV2Enabled: true)
        )

        return D4DashboardSnapshotEnvironment(
            accountContext: AccountContext(),
            appDependencies: AppDependencies.local(),
            onboardingStore: onboardingStore,
            calibrationStore: calibrationStore,
            historyStore: historyStore,
            trophyStore: trophyStore,
            themeStore: ThemeStore(fileURL: directory.appendingPathComponent("Theme.json"), defaultTheme: theme),
            insightStore: InsightStore(fileURL: directory.appendingPathComponent("CoachInsights.json")),
            backendStatusStore: BackendStatusStore(userDefaults: isolatedDefaults()),
            featureFlagService: RemoteFeatureFlagService.local(defaults: FeatureFlags(designSystemV2Enabled: true)),
            toggleStore: DesignSystemV2ToggleStore(
                remoteFlagSnapshotProvider: { true },
                userDefaults: isolatedDefaults()
            ),
            profile: profile,
            dashboardContent: dashboardContent
        )
    }

    func assertColor(
        _ color: Color,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = rgba(color)
        XCTAssertEqual(components.red, red / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.green, green / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.blue, blue / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(components.alpha, 1, accuracy: 0.001, file: file, line: line)
    }

    func rgba(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }

    func renderSnapshot<V: View>(name: String, view: V) throws {
        let size = CGSize(width: 390, height: 220)
        let image = renderImage(
            size: size,
            content: view
                .padding(SpotterV2.Spacing.xl)
                .frame(width: size.width, height: size.height)
                .background(SpotterV2.Tokens.background)
                .preferredColorScheme(.dark)
        )

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 2_000)
    }

    func renderScreenSnapshot<V: View>(
        name: String,
        size: CGSize,
        view: V,
        minimumVisiblePixelRatio: CGFloat? = nil
    ) throws {
        let image = renderImage(
            size: size,
            content: view
                .frame(width: size.width, height: size.height)
                .background(SpotterV2.Tokens.background)
                .preferredColorScheme(.dark)
        )

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 8_000)
        if let minimumVisiblePixelRatio {
            XCTAssertGreaterThan(
                visiblePixelRatio(in: image),
                minimumVisiblePixelRatio,
                "Snapshot \(name) did not contain enough rendered UI pixels."
            )
        }
    }

    func renderImage<V: View>(size: CGSize, content: V) -> UIImage {
        let controller = UIHostingController(
            rootView: content
        )
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        Self.retainedSnapshotWindows.append(window)

        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            controller.view.layer.render(in: context.cgContext)
        }
    }

    func visiblePixelRatio(in image: UIImage) -> CGFloat {
        guard let cgImage = image.cgImage,
              let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        guard bytesPerPixel >= 3 else { return 0 }
        let step = 8
        var visibleSamples = 0
        var totalSamples = 0

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                let distance = abs(red - 13) + abs(green - 13) + abs(blue - 13)
                if distance > 54 {
                    visibleSamples += 1
                }
                totalSamples += 1
            }
        }

        guard totalSamples > 0 else { return 0 }
        return CGFloat(visibleSamples) / CGFloat(totalSamples)
    }
}

private struct D4DashboardSnapshotEnvironment {
    let accountContext: AccountContext
    let appDependencies: AppDependencies
    let onboardingStore: OnboardingStore
    let calibrationStore: CalibrationStore
    let historyStore: WorkoutHistoryStore
    let trophyStore: TrophyStore
    let themeStore: ThemeStore
    let insightStore: InsightStore
    let backendStatusStore: BackendStatusStore
    let featureFlagService: RemoteFeatureFlagService
    let toggleStore: DesignSystemV2ToggleStore
    let profile: UserProfile
    let dashboardContent: DashboardContent
}

private struct D4DashboardSnapshotHost: View {
    @StateObject private var accountContext: AccountContext
    @StateObject private var appDependencies: AppDependencies
    @StateObject private var onboardingStore: OnboardingStore
    @StateObject private var calibrationStore: CalibrationStore
    @StateObject private var historyStore: WorkoutHistoryStore
    @StateObject private var trophyStore: TrophyStore
    @StateObject private var themeStore: ThemeStore
    @StateObject private var insightStore: InsightStore
    @StateObject private var backendStatusStore: BackendStatusStore
    @StateObject private var featureFlagService: RemoteFeatureFlagService
    @StateObject private var toggleStore: DesignSystemV2ToggleStore
    private let profile: UserProfile
    private let dashboardContent: DashboardContent

    init(environment: D4DashboardSnapshotEnvironment) {
        _accountContext = StateObject(wrappedValue: environment.accountContext)
        _appDependencies = StateObject(wrappedValue: environment.appDependencies)
        _onboardingStore = StateObject(wrappedValue: environment.onboardingStore)
        _calibrationStore = StateObject(wrappedValue: environment.calibrationStore)
        _historyStore = StateObject(wrappedValue: environment.historyStore)
        _trophyStore = StateObject(wrappedValue: environment.trophyStore)
        _themeStore = StateObject(wrappedValue: environment.themeStore)
        _insightStore = StateObject(wrappedValue: environment.insightStore)
        _backendStatusStore = StateObject(wrappedValue: environment.backendStatusStore)
        _featureFlagService = StateObject(wrappedValue: environment.featureFlagService)
        _toggleStore = StateObject(wrappedValue: environment.toggleStore)
        profile = environment.profile
        dashboardContent = environment.dashboardContent
    }

    var body: some View {
        V2DashboardView(
            initialProfile: profile,
            initialDashboardContent: dashboardContent,
            refreshOnAppear: false,
            usesNavigationStack: false
        )
            .environmentObject(accountContext)
            .environmentObject(appDependencies)
            .environmentObject(onboardingStore)
            .environmentObject(calibrationStore)
            .environmentObject(historyStore)
            .environmentObject(trophyStore)
            .environmentObject(themeStore)
            .environmentObject(insightStore)
            .environmentObject(backendStatusStore)
            .environmentObject(featureFlagService)
            .environmentObject(toggleStore)
    }
}

private struct V2MainShellSnapshotHost: View {
    let theme: SpotterThemeOption
    let selectedTab: V2Tab
    @State private var appPresentation = AppLevelPresentationState()

    var body: some View {
        V2MainShellView(initialSelectedTab: selectedTab)
            .environmentObject(AccountContext())
            .environmentObject(AppDependencies.local())
            .environmentObject(OnboardingStore())
            .environmentObject(CalibrationStore())
            .environmentObject(WorkoutHistoryStore())
            .environmentObject(TrophyStore())
            .environmentObject(ThemeStore(defaultTheme: theme))
            .environmentObject(InsightStore())
            .environmentObject(BackendStatusStore())
            .environmentObject(RemoteFeatureFlagService.local(defaults: FeatureFlags(designSystemV2Enabled: true)))
            .environmentObject(
                DesignSystemV2ToggleStore(
                    remoteFlagSnapshotProvider: { true },
                    userDefaults: UserDefaults(suiteName: "V2MainShellSnapshot.\(theme.rawValue)") ?? .standard
                )
            )
            .environment(\.appLevelPresenter, $appPresentation)
    }
}

private struct V2TabBarSnapshotHost: View {
    let theme: SpotterThemeOption
    @State var selectedTab: V2Tab

    var body: some View {
        VStack {
            Spacer()
            V2LiquidGlassTabBar(selectedTab: $selectedTab, theme: theme)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum D3OnboardingSnapshotScreen {
    case welcome
    case identity
    case stats
    case objective
}

private struct D3OnboardingScreenSnapshotHost: View {
    let theme: SpotterThemeOption
    let screen: D3OnboardingSnapshotScreen
    @StateObject private var onboardingStore: OnboardingStore
    @StateObject private var themeStore: ThemeStore
    @StateObject private var appDependencies = AppDependencies.local()

    init(theme: SpotterThemeOption, screen: D3OnboardingSnapshotScreen) {
        self.theme = theme
        self.screen = screen
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("D3OnboardingSnapshot-\(UUID().uuidString)", isDirectory: true)
        let onboarding = OnboardingStore(fileURL: baseURL.appendingPathComponent("UserProfile.json"))
        onboarding.draft = Self.previewDraft(theme: theme)
        _onboardingStore = StateObject(wrappedValue: onboarding)
        _themeStore = StateObject(wrappedValue: ThemeStore(fileURL: baseURL.appendingPathComponent("Theme.json"), defaultTheme: theme))
    }

    var body: some View {
        Group {
            switch screen {
            case .welcome:
                V2WelcomeView(onStart: {})
            case .identity:
                V2OnboardingIdentityView(onBack: {}, onNext: {})
            case .stats:
                V2OnboardingStatsView(onBack: {}, onNext: {})
            case .objective:
                V2OnboardingObjectiveView(onBack: {}, onNext: {})
            }
        }
        .environmentObject(onboardingStore)
        .environmentObject(themeStore)
        .environmentObject(appDependencies)
    }

    private static func previewDraft(theme: SpotterThemeOption) -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft.displayName = "Satvik Bansal"
        draft.genderIdentity = .male
        draft.age = "24"
        draft.height = "178"
        draft.weight = "84.5"
        draft.primaryGoal = .strength
        draft.fitnessLevel = .beginner
        draft.equipment = [.bodyweight, .dumbbells]
        draft.limitations = [.kneeSensitive]
        draft.preferredSessionLength = .twentyFive
        draft.workoutDaysPerWeek = 4
        draft.selectedTheme = theme
        return draft
    }
}

private struct D3CalibrationIntroSnapshotHost: View {
    let theme: SpotterThemeOption
    @StateObject private var calibrationStore: CalibrationStore
    @StateObject private var themeStore: ThemeStore
    @StateObject private var appDependencies = AppDependencies.local()

    init(theme: SpotterThemeOption) {
        self.theme = theme
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("D3CalibrationSnapshot-\(UUID().uuidString)", isDirectory: true)
        _calibrationStore = StateObject(wrappedValue: CalibrationStore(fileURL: baseURL.appendingPathComponent("CalibrationRecord.json")))
        _themeStore = StateObject(wrappedValue: ThemeStore(fileURL: baseURL.appendingPathComponent("Theme.json"), defaultTheme: theme))
    }

    var body: some View {
        V2CalibrationIntroView()
            .environmentObject(calibrationStore)
            .environmentObject(themeStore)
            .environmentObject(appDependencies)
    }
}

private struct D3CameraReadinessSnapshotHost: View {
    let theme: SpotterThemeOption
    let state: V2CameraReadinessUIState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SpotterV2.Tokens.secondary.opacity(0.95),
                    SpotterV2.Tokens.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            V2CameraReadinessView(
                theme: theme,
                state: state,
                orientationInstruction: "Turn phone sideways for squats",
                visibilityPercent: state.kind == .ready ? 100 : 38,
                onStartTracking: {},
                onOpenSettings: {},
                onClose: {}
            )
        }
    }
}
