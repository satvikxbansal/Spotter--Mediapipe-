import XCTest
@testable import VirtualTrainer

final class DashboardContentTests: XCTestCase {
    private let factory = DashboardContentFactory(
        calendar: Calendar(identifier: .gregorian)
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
}

private extension DashboardContentTests {
    func makeProfile(goal: FitnessGoal) -> UserProfile {
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
            fitnessLevel: .beginner,
            equipment: [.bodyweight],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }
}
