import XCTest
@testable import VirtualTrainer

final class DashboardContentTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private lazy var factory = DashboardContentFactory(
        planService: PlanService(
            quickStartDeckService: QuickStartPlanDeckService(calendar: calendar)
        ),
        calendar: calendar
    )

    func testCompletedProfileDashboardGeneratesPlans() {
        let content = factory.makeContent(
            profile: makeProfile(goal: .strength),
            now: Date(timeIntervalSince1970: 1_777_000_000)
        )

        XCTAssertEqual(content.athleteName, "Test")
        XCTAssertEqual(content.smartStart.plan.estimatedMinutes, 7)
        XCTAssertEqual(content.dailyPlan.plan.estimatedMinutes, 25)
        XCTAssertFalse(content.smartStart.plan.blocks.isEmpty)
        XCTAssertFalse(content.dailyPlan.plan.blocks.isEmpty)
        XCTAssertFalse(content.smartStart.plan.blocks.flatMap(\.exercises).isEmpty)
    }

    func testChangingGoalChangesRecommendedPlanType() {
        let strengthContent = factory.makeContent(
            profile: makeProfile(goal: .strength),
            now: Date(timeIntervalSince1970: 1_777_000_000)
        )
        let performanceContent = factory.makeContent(
            profile: makeProfile(goal: .performance),
            now: Date(timeIntervalSince1970: 1_777_000_000)
        )
        let longevityContent = factory.makeContent(
            profile: makeProfile(goal: .longevity),
            now: Date(timeIntervalSince1970: 1_777_000_000)
        )

        XCTAssertTrue(strengthContent.smartStart.title.contains("Strength"))
        XCTAssertTrue(performanceContent.smartStart.title.contains("Performance"))
        XCTAssertTrue(longevityContent.smartStart.title.contains("Longevity"))
        XCTAssertNotEqual(strengthContent.smartStart.title, performanceContent.smartStart.title)
        XCTAssertNotEqual(performanceContent.smartStart.title, longevityContent.smartStart.title)
    }

    func testFormCheckActionRoutesToExerciseSelection() throws {
        let content = factory.makeContent(
            profile: makeProfile(goal: .performance),
            now: Date(timeIntervalSince1970: 1_777_000_000)
        )

        let action = try XCTUnwrap(content.quickActions.first { $0.kind == .formCheck })

        XCTAssertTrue(action.isEnabled)
        XCTAssertNil(action.statusLabel)
        XCTAssertEqual(action.destination, .formCheckSelection)
    }

    func testRunningAnalysisActionIsDisabledAndComingSoon() throws {
        let content = factory.makeContent(
            profile: makeProfile(goal: .longevity),
            now: Date(timeIntervalSince1970: 1_777_000_000)
        )

        let action = try XCTUnwrap(content.quickActions.first { $0.kind == .runningAnalysis })

        XCTAssertFalse(action.isEnabled)
        XCTAssertEqual(action.statusLabel, "Coming Soon")
        XCTAssertEqual(action.destination, .runningAnalysis)
    }

    func testRecentWorkoutHistoryFeedsStreakAndRecentWorkout() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 12)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let oldWorkout = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: today))
        let history = [
            RecentWorkoutHistoryItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000801") ?? UUID(),
                exerciseType: .pushup,
                completedAt: yesterday
            ),
            RecentWorkoutHistoryItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000802") ?? UUID(),
                exerciseType: .squat,
                completedAt: today
            ),
            RecentWorkoutHistoryItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000803") ?? UUID(),
                exerciseType: .plank,
                completedAt: oldWorkout
            )
        ]

        let content = factory.makeContent(
            profile: makeProfile(goal: .strength),
            now: today,
            recentWorkoutHistory: history
        )

        XCTAssertEqual(content.streak.dayCount, 2)
        XCTAssertEqual(content.recentWorkout?.exerciseType, .squat)
        XCTAssertEqual(content.recentWorkout?.completedAt, today)
    }

    func testDashboardCanUseStoreComputedCurrentStreak() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 12)))
        let oldWorkout = try XCTUnwrap(calendar.date(byAdding: .day, value: -14, to: today))
        let history = [
            RecentWorkoutHistoryItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000804") ?? UUID(),
                exerciseType: .pushup,
                completedAt: oldWorkout
            )
        ]

        let content = factory.makeContent(
            profile: makeProfile(goal: .strength),
            now: today,
            recentWorkoutHistory: history,
            currentStreakDayCount: 9
        )

        XCTAssertEqual(content.streak.dayCount, 9)
        XCTAssertEqual(content.recentWorkout?.exerciseType, .pushup)
    }

    func testSmartStartDeckCycleAdvancesAndWraps() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: 12)))
        var content = factory.makeContent(
            profile: makeProfile(goal: .strength, level: .intermediate),
            now: now
        )
        let firstVariantId = content.currentSmartStart.id

        content.advanceSmartStartPlan()

        XCTAssertEqual(content.selectedSmartStartIndex, 1)
        XCTAssertNotEqual(content.currentSmartStart.id, firstVariantId)

        for _ in 1..<content.smartStartDeck.variants.count {
            content.advanceSmartStartPlan()
        }

        XCTAssertEqual(content.selectedSmartStartIndex, 0)
        XCTAssertEqual(content.currentSmartStart.id, firstVariantId)
    }

    func testSmartStartSummaryUsesSelectedDeckPlan() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: 12)))
        var content = factory.makeContent(
            profile: makeProfile(goal: .performance, level: .intermediate),
            now: now
        )

        content.advanceSmartStartPlan()
        let selectedVariant = content.currentSmartStart

        XCTAssertEqual(content.smartStart.plan.id, selectedVariant.plan.id)
        XCTAssertEqual(content.smartStart.title, selectedVariant.title)
    }

    func testEmptySmartStartDeckFallsBackWithoutCrashing() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: 12)))
        let fallbackPlan = PlanService().generateSmartStart(
            profile: makeProfile(goal: .strength, level: .beginner)
        )
        let dailyPlan = PlanService().generateDailyPlan(
            profile: makeProfile(goal: .strength, level: .beginner)
        )
        let content = DashboardContent(
            greeting: "Good morning",
            athleteName: "Test",
            streak: DashboardStreak(dayCount: 0),
            smartStartDeck: QuickStartDeck(
                id: "empty",
                generatedForDay: now,
                generationVersion: "test",
                variants: []
            ),
            selectedSmartStartIndex: 0,
            smartStartFallback: DashboardPlanSummary(plan: fallbackPlan),
            dailyPlan: DashboardPlanSummary(plan: dailyPlan),
            quickActions: [],
            trophyTeaserText: "",
            recentWorkout: nil
        )

        XCTAssertEqual(content.currentSmartStart.plan.id, fallbackPlan.id)
        XCTAssertEqual(content.smartStart.plan.id, fallbackPlan.id)
    }
}

private extension DashboardContentTests {
    func makeProfile(
        goal: FitnessGoal,
        level: FitnessLevel = .beginner
    ) -> UserProfile {
        let now = Date(timeIntervalSince1970: 1_776_000_000)
        return UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000707") ?? UUID(),
            displayName: "Test Athlete",
            genderIdentity: .preferNotToSay,
            age: 30,
            height: 175,
            heightUnit: .metric,
            weight: 72,
            weightUnit: .metric,
            primaryGoal: goal,
            fitnessLevel: level,
            equipment: [.bodyweight, .mat, .wall],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }
}
