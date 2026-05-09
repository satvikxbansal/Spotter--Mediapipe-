import XCTest
@testable import VirtualTrainer

@MainActor
final class OnboardingModelTests: XCTestCase {
    func testAgeBracketMapping() {
        XCTAssertEqual(UserProfile.ageBracket(for: 18), .teen)
        XCTAssertEqual(UserProfile.ageBracket(for: 20), .youngAdult)
        XCTAssertEqual(UserProfile.ageBracket(for: 35), .adult)
        XCTAssertEqual(UserProfile.ageBracket(for: 50), .midlife)
        XCTAssertEqual(UserProfile.ageBracket(for: 65), .senior)
    }

    func testOldProfileJSONDecodesWithPreferenceDefaults() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000111",
          "displayName": "Legacy Athlete",
          "genderIdentity": "preferNotToSay",
          "age": 31,
          "height": 175,
          "heightUnit": "metric",
          "weight": 72,
          "weightUnit": "metric",
          "primaryGoal": "strength",
          "fitnessLevel": "beginner",
          "equipment": ["bodyweight", "mat"],
          "preferredCoach": "bennett",
          "selectedTheme": "hyper",
          "onboardingCompletedAt": "2026-05-06T00:00:00Z",
          "createdAt": "2026-05-06T00:00:00Z",
          "updatedAt": "2026-05-06T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let profile = try decoder.decode(UserProfile.self, from: Data(json.utf8))

        XCTAssertEqual(profile.limitations, [])
        XCTAssertEqual(profile.preferredSessionLength, .twentyFive)
        XCTAssertEqual(profile.workoutDaysPerWeek, UserProfile.defaultWorkoutDaysPerWeek)
        XCTAssertEqual(profile.reminderPreference, .none)
        XCTAssertEqual(profile.timezoneIdentifier, TimeZone.current.identifier)
        XCTAssertEqual(profile.avatarStyle, .default)
        XCTAssertEqual(profile.onboardingSchemaVersion, UserProfile.currentOnboardingSchemaVersion)
        XCTAssertEqual(profile.profileSchemaVersion, UserProfile.currentProfileSchemaVersion)
        XCTAssertNil(profile.deletedAt)
    }

    func testStatsValidationExplainsImperialWeightBoundary() async {
        await MainActor.run {
            let store = OnboardingStore(fileURL: temporaryProfileURL())
            store.draft.age = "33"
            store.draft.height = "178"
            store.draft.heightUnit = .metric
            store.draft.weight = "65"
            store.draft.weightUnit = .imperial

            XCTAssertFalse(store.canContinue(from: .stats))
            XCTAssertEqual(store.weightValidationMessage, "Weight must be between 66 and 550 lb.")
        }
    }

    func testWeightUnitSwitchConvertsExistingValue() async {
        await MainActor.run {
            let store = OnboardingStore(fileURL: temporaryProfileURL())
            store.draft.age = "33"
            store.draft.height = "178"
            store.draft.weight = "65"

            store.updateWeightUnit(.imperial)

            XCTAssertEqual(store.draft.weight, "143.3")
            XCTAssertNil(store.weightValidationMessage)
            XCTAssertTrue(store.canContinue(from: .stats))
        }
    }

    func testOnboardingCompletesWithNewPreferenceFields() async {
        let store = OnboardingStore(fileURL: temporaryProfileURL())
        store.draft = validDraft()
        store.draft.limitations = [.kneeSensitive, .highImpactSensitive]
        store.draft.preferredSessionLength = .thirtyFive
        store.draft.workoutDaysPerWeek = 4
        store.draft.reminderPreference = .morning
        store.draft.timezoneIdentifier = "America/New_York"
        store.draft.avatarStyle = .performance

        await store.completeOnboarding()

        XCTAssertEqual(store.profile?.limitations, [.kneeSensitive, .highImpactSensitive])
        XCTAssertEqual(store.profile?.preferredSessionLength, .thirtyFive)
        XCTAssertEqual(store.profile?.workoutDaysPerWeek, 4)
        XCTAssertEqual(store.profile?.reminderPreference, .morning)
        XCTAssertEqual(store.profile?.timezoneIdentifier, "America/New_York")
        XCTAssertEqual(store.profile?.avatarStyle, .performance)
    }

    func testProfilePreferenceUpdatePersistsNewFields() async {
        let url = temporaryProfileURL()
        let store = OnboardingStore(fileURL: url)
        store.draft = validDraft()
        await store.completeOnboarding()

        _ = await store.updateTrainingPreferences(
            limitations: [.wristSensitive, .lowerBackSensitive],
            preferredSessionLength: .fifteen,
            workoutDaysPerWeek: 5,
            reminderPreference: .evening,
            timezoneIdentifier: "Asia/Kolkata",
            avatarStyle: .longevity
        )

        let reloadedStore = OnboardingStore(fileURL: url)
        XCTAssertEqual(reloadedStore.profile?.limitations, [.wristSensitive, .lowerBackSensitive])
        XCTAssertEqual(reloadedStore.profile?.preferredSessionLength, .fifteen)
        XCTAssertEqual(reloadedStore.profile?.workoutDaysPerWeek, 5)
        XCTAssertEqual(reloadedStore.profile?.reminderPreference, .evening)
        XCTAssertEqual(reloadedStore.profile?.timezoneIdentifier, "Asia/Kolkata")
        XCTAssertEqual(reloadedStore.profile?.avatarStyle, .longevity)
    }

    func testChangingGoalUpdatesProfileAndNextGeneratedPlan() async {
        let store = OnboardingStore(fileURL: temporaryProfileURL())
        store.draft = validDraft()
        await store.completeOnboarding()

        await store.updatePrimaryGoal(.longevity)

        guard let profile = store.profile else {
            XCTFail("Expected completed profile")
            return
        }
        let plan = PlanService().generateDailyPlan(profile: profile)
        XCTAssertEqual(profile.primaryGoal, .longevity)
        XCTAssertEqual(plan.title, "25-Minute Longevity")
    }

    func testChangingCoachUpdatesProfileAndNextGeneratedPlan() async {
        let store = OnboardingStore(fileURL: temporaryProfileURL())
        store.draft = validDraft()
        await store.completeOnboarding()

        await store.updatePreferredCoach(.fletcher)

        guard let profile = store.profile else {
            XCTFail("Expected completed profile")
            return
        }
        let plan = PlanService().generateDailyPlan(profile: profile)
        XCTAssertEqual(profile.preferredCoach, .fletcher)
        XCTAssertEqual(plan.coach, .drill)
    }

    func testChangingThemeUpdatesProfileAndThemeStore() async {
        let profileURL = temporaryProfileURL()
        let themeURL = temporaryThemeURL()
        let store = OnboardingStore(fileURL: profileURL)
        let themeStore = ThemeStore(fileURL: themeURL)
        store.draft = validDraft()
        await store.completeOnboarding()

        await store.updateSelectedTheme(.hotGirl)
        await themeStore.updateSelectedTheme(.hotGirl)

        let reloadedProfileStore = OnboardingStore(fileURL: profileURL)
        let reloadedThemeStore = ThemeStore(fileURL: themeURL)
        XCTAssertEqual(reloadedProfileStore.profile?.selectedTheme, .hotGirl)
        XCTAssertEqual(reloadedThemeStore.selectedTheme, .hotGirl)
    }

    func testThemeStoreSyncsWithProfileTheme() async {
        let store = OnboardingStore(fileURL: temporaryProfileURL())
        let themeStore = ThemeStore(fileURL: temporaryThemeURL(), defaultTheme: .spicy)
        store.draft = validDraft()
        await store.completeOnboarding()
        await store.updateSelectedTheme(.warm)

        await themeStore.sync(with: store.profile)

        XCTAssertEqual(themeStore.selectedTheme, .warm)
    }

    func testThemeStorePersistsProfileThemeEvenWhenItMatchesDefault() async {
        let url = temporaryThemeURL()
        let store = OnboardingStore(fileURL: temporaryProfileURL())
        let themeStore = ThemeStore(fileURL: url, defaultTheme: .hyper)
        store.draft = validDraft()
        await store.completeOnboarding()

        assertTrue(await themeStore.sync(with: store.profile))

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(ThemeStore(fileURL: url).selectedTheme, .hyper)
    }

    func testFailedThemeProfileUpdateDoesNotMutateInMemoryProfile() async throws {
        let url = temporaryProfileURL()
        let store = OnboardingStore(fileURL: url)
        store.draft = validDraft()
        await store.completeOnboarding()
        XCTAssertEqual(store.profile?.selectedTheme, .hyper)

        let parentURL = url.deletingLastPathComponent()
        try FileManager.default.removeItem(at: parentURL)
        try Data().write(to: parentURL)

        assertFalse(await store.updateSelectedTheme(.spicy))
        XCTAssertEqual(store.profile?.selectedTheme, .hyper)
        XCTAssertNotNil(store.persistenceError)
    }

    func testChangingPreferredSessionLengthUpdatesProfile() async {
        let store = OnboardingStore(fileURL: temporaryProfileURL())
        store.draft = validDraft()
        await store.completeOnboarding()

        await store.updatePreferredSessionLength(.thirtyFive)

        XCTAssertEqual(store.profile?.preferredSessionLength, .thirtyFive)
    }

    func testFreeAnalysisContextIsOpenTarget() {
        let context = LiveSessionContext.freeAnalysis(exerciseType: .pushup, coach: .good)

        XCTAssertEqual(context.mode, .freeAnalysis)
        XCTAssertEqual(context.exerciseType, .pushup)
        XCTAssertEqual(context.target, .open)
        XCTAssertNil(context.planId)
        XCTAssertNil(context.setIndex)
        XCTAssertNil(context.totalSets)
    }

    func testPlannedWorkoutContextCarriesTargetAndPlanMetadata() {
        let workout = WorkoutPlan.MockData.upperBody
        let context = LiveSessionContext.plannedWorkout(workout: workout, setIndex: 1, coach: .drill)

        XCTAssertEqual(context.mode, .plannedWorkout)
        XCTAssertEqual(context.exerciseType, .pushup)
        XCTAssertEqual(context.target, .reps(15))
        XCTAssertEqual(context.planId, workout.id)
        XCTAssertEqual(context.setIndex, 1)
        XCTAssertEqual(context.totalSets, workout.exercises.count)
        XCTAssertEqual(context.coach, .drill)
    }

    func testPlannedWorkoutContextHandlesEmptyLegacyWorkoutWithoutCrashing() {
        let workout = WorkoutPlan(
            title: "Empty Legacy Flow",
            subtitle: "Legacy plan without sets",
            exercises: [],
            estimatedMinutes: 0
        )
        let context = LiveSessionContext.plannedWorkout(workout: workout)

        XCTAssertEqual(context.mode, SessionMode.plannedWorkout)
        XCTAssertEqual(context.exerciseType, ExerciseType.squat)
        XCTAssertEqual(context.target, SessionTarget.open)
        XCTAssertNil(context.setIndex)
        XCTAssertEqual(context.totalSets, 0)
        XCTAssertEqual(context.planId, workout.id)
    }

    private func temporaryProfileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("UserProfile.json")
    }

    private func temporaryThemeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Theme.json")
    }

    private func validDraft() -> OnboardingDraft {
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
}
