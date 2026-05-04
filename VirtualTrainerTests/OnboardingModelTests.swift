import XCTest
@testable import VirtualTrainer

final class OnboardingModelTests: XCTestCase {
    func testAgeBracketMapping() {
        XCTAssertEqual(UserProfile.ageBracket(for: 18), .teen)
        XCTAssertEqual(UserProfile.ageBracket(for: 20), .youngAdult)
        XCTAssertEqual(UserProfile.ageBracket(for: 35), .adult)
        XCTAssertEqual(UserProfile.ageBracket(for: 50), .midlife)
        XCTAssertEqual(UserProfile.ageBracket(for: 65), .senior)
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
}
