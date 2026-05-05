import XCTest
@testable import VirtualTrainer

final class PlannedWorkoutCoordinatorTests: XCTestCase {
    func testCoordinatorStartsAtFirstPlannedSet() throws {
        let plan = makePlan()
        let coordinator = PlannedWorkoutCoordinator(
            plan: plan,
            startedAt: Date(timeIntervalSince1970: 1_776_100_000)
        )

        let context = try XCTUnwrap(coordinator.currentContext)

        XCTAssertEqual(coordinator.plan.id, plan.id)
        XCTAssertEqual(coordinator.currentBlockIndex, 0)
        XCTAssertEqual(coordinator.currentExerciseIndex, 0)
        XCTAssertEqual(coordinator.currentSetIndex, 0)
        XCTAssertEqual(coordinator.currentTarget, .reps(8))
        XCTAssertEqual(context.mode, .plannedWorkout)
        XCTAssertEqual(context.planId, plan.id)
        XCTAssertEqual(context.exerciseType, .squat)
        XCTAssertEqual(context.target, .reps(8))
        XCTAssertEqual(context.setIndex, 0)
        XCTAssertEqual(context.totalSets, 2)
        XCTAssertEqual(context.exerciseIndex, 0)
        XCTAssertEqual(context.totalExercises, 2)
        XCTAssertEqual(context.coach, .drill)
    }

    func testCompletingSetWaitsForContinueBeforeAdvancing() throws {
        var coordinator = PlannedWorkoutCoordinator(plan: makePlan())
        let firstContext = try XCTUnwrap(coordinator.currentContext)

        XCTAssertTrue(
            coordinator.completeCurrentSet(with: makeSummary(from: firstContext, reps: 8))
        )

        XCTAssertTrue(coordinator.isAwaitingContinue)
        XCTAssertEqual(coordinator.completedSetSummaries.count, 1)
        XCTAssertEqual(coordinator.currentSetIndex, 0)

        coordinator.continueToNextSet()

        let nextContext = try XCTUnwrap(coordinator.currentContext)
        XCTAssertFalse(coordinator.isAwaitingContinue)
        XCTAssertFalse(coordinator.isSessionComplete)
        XCTAssertEqual(coordinator.currentSetIndex, 1)
        XCTAssertEqual(nextContext.exerciseType, .squat)
        XCTAssertEqual(nextContext.target, .reps(9))
        XCTAssertEqual(nextContext.setIndex, 1)
    }

    func testCoordinatorAdvancesAcrossExercisesAndCompletesPlan() throws {
        var coordinator = PlannedWorkoutCoordinator(plan: makePlan())

        let firstContext = try XCTUnwrap(coordinator.currentContext)
        _ = coordinator.completeCurrentSet(with: makeSummary(from: firstContext, reps: 8))
        coordinator.continueToNextSet()

        let secondContext = try XCTUnwrap(coordinator.currentContext)
        _ = coordinator.completeCurrentSet(with: makeSummary(from: secondContext, reps: 9))
        coordinator.continueToNextSet()

        let thirdContext = try XCTUnwrap(coordinator.currentContext)
        XCTAssertEqual(thirdContext.exerciseType, .pushup)
        XCTAssertEqual(thirdContext.exerciseIndex, 1)
        XCTAssertEqual(thirdContext.setIndex, 0)
        XCTAssertEqual(thirdContext.target, .reps(6))

        _ = coordinator.completeCurrentSet(with: makeSummary(from: thirdContext, reps: 6))
        XCTAssertFalse(coordinator.isSessionComplete)
        XCTAssertFalse(coordinator.hasNextSet)

        coordinator.continueToNextSet()

        XCTAssertTrue(coordinator.isSessionComplete)
        XCTAssertNil(coordinator.currentContext)
        XCTAssertEqual(coordinator.completedSetSummaries.count, 3)
    }

    func testWorkoutSessionContextBridgesToLiveSessionContext() {
        let planId = UUID(uuidString: "00000000-0000-0000-0000-0000000009A0") ?? UUID()
        let context = WorkoutSessionContext(
            planId: planId,
            planTitle: "Strength Session",
            exerciseType: .plank,
            target: .hold(seconds: 30),
            setIndex: 0,
            totalSets: 1,
            exerciseIndex: 0,
            totalExercises: 1,
            coach: .good,
            startsActive: true
        )

        let liveContext = context.liveSessionContext

        XCTAssertEqual(liveContext.mode, .plannedWorkout)
        XCTAssertEqual(liveContext.planId, planId)
        XCTAssertEqual(liveContext.title, "Strength Session")
        XCTAssertEqual(liveContext.exerciseType, .plank)
        XCTAssertEqual(liveContext.target, .seconds(30))
        XCTAssertEqual(liveContext.setIndex, 0)
        XCTAssertEqual(liveContext.totalSets, 1)
        XCTAssertEqual(liveContext.coach, .good)
        XCTAssertTrue(liveContext.startsActive)
    }
}

private extension PlannedWorkoutCoordinatorTests {
    func makePlan() -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000009A1") ?? UUID(),
            title: "Phase 9A Strength",
            subtitle: "Coordinator test plan",
            goal: "Build clean strength.",
            estimatedMinutes: 7,
            difficulty: .beginner,
            coach: .drill,
            blocks: [
                WorkoutBlock(
                    title: "Strength",
                    type: .main,
                    exercises: [
                        PlannedExercise(
                            exerciseType: .squat,
                            sets: [
                                PlannedSet(setIndex: 1, target: .reps(8)),
                                PlannedSet(setIndex: 2, target: .reps(9))
                            ],
                            restSeconds: 60,
                            coachingFocus: "Depth and knee tracking.",
                            cameraPosition: .front,
                            allowSwap: true
                        ),
                        PlannedExercise(
                            exerciseType: .pushup,
                            sets: [
                                PlannedSet(setIndex: 1, target: .reps(6))
                            ],
                            restSeconds: 60,
                            coachingFocus: "Body line and controlled tempo.",
                            cameraPosition: .side,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: Date(timeIntervalSince1970: 1_776_100_000),
            planReason: "Stable fixture for planned workout coordinator tests.",
            source: .generatedLocal
        )
    }

    func makeSummary(
        from context: WorkoutSessionContext,
        reps: Int
    ) -> PlannedWorkoutSetSummary {
        PlannedWorkoutSetSummary(
            planId: context.planId,
            exerciseType: context.exerciseType,
            target: context.target,
            setIndex: context.setIndex,
            totalSets: context.totalSets,
            exerciseIndex: context.exerciseIndex,
            totalExercises: context.totalExercises,
            completedAt: Date(timeIntervalSince1970: 1_776_100_100),
            duration: 32,
            reps: reps,
            holdDuration: 0,
            latestFormScore: nil,
            peakEffort: 0.4,
            lastCue: nil,
            completionSource: .targetMet
        )
    }
}
