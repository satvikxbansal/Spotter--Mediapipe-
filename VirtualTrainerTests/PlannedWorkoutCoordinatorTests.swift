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
        XCTAssertEqual(coordinator.sessionState, .ready)
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
        coordinator.startSession()
        let firstContext = try XCTUnwrap(coordinator.currentContext)

        XCTAssertTrue(
            coordinator.completeCurrentSet(with: makeSummary(from: firstContext, reps: 8))
        )

        let restContext = try XCTUnwrap(coordinator.restContext)
        XCTAssertEqual(coordinator.sessionState, .rest)
        XCTAssertTrue(coordinator.isAwaitingContinue)
        XCTAssertEqual(coordinator.completedSetSummaries.count, 1)
        XCTAssertEqual(coordinator.currentSetIndex, 0)
        XCTAssertNil(coordinator.currentContext)
        XCTAssertEqual(restContext.restSeconds, 60)
        XCTAssertEqual(restContext.lastSummary.reps, 8)
        XCTAssertEqual(restContext.upNextContext.exerciseType, .squat)
        XCTAssertEqual(restContext.upNextContext.target, .reps(9))

        coordinator.continueToNextSet()

        let nextContext = try XCTUnwrap(coordinator.currentContext)
        XCTAssertEqual(coordinator.sessionState, .activeSet)
        XCTAssertFalse(coordinator.isAwaitingContinue)
        XCTAssertFalse(coordinator.isSessionComplete)
        XCTAssertEqual(coordinator.currentSetIndex, 1)
        XCTAssertEqual(nextContext.exerciseType, .squat)
        XCTAssertEqual(nextContext.target, .reps(9))
        XCTAssertEqual(nextContext.setIndex, 1)
    }

    func testCoordinatorAdvancesAcrossExercisesAndCompletesPlan() throws {
        var coordinator = PlannedWorkoutCoordinator(plan: makePlan())
        coordinator.startSession()

        let firstContext = try XCTUnwrap(coordinator.currentContext)
        _ = coordinator.completeCurrentSet(with: makeSummary(from: firstContext, reps: 8))
        coordinator.continueToNextSet()

        let secondContext = try XCTUnwrap(coordinator.currentContext)
        _ = coordinator.completeCurrentSet(with: makeSummary(from: secondContext, reps: 9))

        let secondRestContext = try XCTUnwrap(coordinator.restContext)
        XCTAssertEqual(secondRestContext.upNextContext.exerciseType, .pushup)
        XCTAssertEqual(secondRestContext.upNextContext.exerciseIndex, 1)
        XCTAssertEqual(secondRestContext.upNextContext.setIndex, 0)

        coordinator.continueToNextSet()

        let thirdContext = try XCTUnwrap(coordinator.currentContext)
        XCTAssertEqual(thirdContext.exerciseType, .pushup)
        XCTAssertEqual(thirdContext.exerciseIndex, 1)
        XCTAssertEqual(thirdContext.setIndex, 0)
        XCTAssertEqual(thirdContext.target, .reps(6))

        _ = coordinator.completeCurrentSet(with: makeSummary(from: thirdContext, reps: 6))
        XCTAssertEqual(coordinator.sessionState, .completed)
        XCTAssertTrue(coordinator.isSessionComplete)
        XCTAssertFalse(coordinator.hasNextSet)

        coordinator.continueToNextSet()

        XCTAssertTrue(coordinator.isSessionComplete)
        XCTAssertNil(coordinator.currentContext)
        XCTAssertEqual(coordinator.completedSetSummaries.count, 3)
    }

    func testWorkoutSummaryBuilderAggregatesCompletedSets() throws {
        var coordinator = PlannedWorkoutCoordinator(
            plan: makePlan(),
            startedAt: Date(timeIntervalSince1970: 1_776_100_000)
        )
        coordinator.startSession()

        let firstContext = try XCTUnwrap(coordinator.currentContext)
        _ = coordinator.completeCurrentSet(
            with: makeSummary(
                from: firstContext,
                reps: 8,
                duration: 30,
                formScore: formScore(90)
            )
        )
        coordinator.continueToNextSet()

        let secondContext = try XCTUnwrap(coordinator.currentContext)
        _ = coordinator.completeCurrentSet(
            with: makeSummary(
                from: secondContext,
                reps: 9,
                duration: 35,
                formScore: formScore(80)
            )
        )
        coordinator.continueToNextSet()

        let thirdContext = try XCTUnwrap(coordinator.currentContext)
        _ = coordinator.completeCurrentSet(
            with: makeSummary(
                from: thirdContext,
                reps: 6,
                duration: 40,
                holdDuration: 12,
                formScore: nil
            )
        )

        let summary = coordinator.workoutSummary(
            completedAt: Date(timeIntervalSince1970: 1_776_100_200)
        )

        XCTAssertEqual(summary.planId, coordinator.plan.id)
        XCTAssertEqual(summary.planTitle, "Phase 9A Strength")
        XCTAssertEqual(summary.completedSets, 3)
        XCTAssertEqual(summary.totalSets, 3)
        XCTAssertEqual(summary.exercisesCompleted, 2)
        XCTAssertEqual(summary.totalExercises, 2)
        XCTAssertEqual(summary.totalReps, 23)
        XCTAssertEqual(summary.totalHoldSeconds, 12)
        XCTAssertEqual(try XCTUnwrap(summary.averageFormScore), 85, accuracy: 0.001)
        XCTAssertEqual(summary.completionPercentage, 1)
        XCTAssertEqual(summary.exerciseSummaries.count, 2)
        XCTAssertEqual(summary.exerciseSummaries.first?.exerciseType, .squat)
        XCTAssertEqual(summary.exerciseSummaries.first?.setsCompleted, 2)
    }

    func testCoordinatorCanCancelSession() {
        var coordinator = PlannedWorkoutCoordinator(plan: makePlan())
        coordinator.startSession()

        coordinator.cancelSession(at: Date(timeIntervalSince1970: 1_776_100_050))

        XCTAssertEqual(coordinator.sessionState, .cancelled)
        XCTAssertFalse(coordinator.isSessionComplete)
        XCTAssertNil(coordinator.currentContext)
        XCTAssertNotNil(coordinator.completedAt)
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

    func testWorkoutSessionContextBridgesTargetVariants() {
        let planId = UUID(uuidString: "00000000-0000-0000-0000-0000000009B0") ?? UUID()

        XCTAssertEqual(
            makeContext(planId: planId, target: .reps(12)).liveSessionContext.target,
            .reps(12)
        )
        XCTAssertEqual(
            makeContext(planId: planId, target: .timed(seconds: 45)).liveSessionContext.target,
            .seconds(45)
        )
        XCTAssertEqual(
            makeContext(planId: planId, target: .amrap(seconds: 60)).liveSessionContext.target,
            .seconds(60)
        )
        XCTAssertEqual(
            makeContext(planId: planId, target: .amrap(seconds: nil)).liveSessionContext.target,
            .open
        )
        XCTAssertEqual(
            makeContext(planId: planId, target: .open).liveSessionContext.target,
            .open
        )
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
        reps: Int,
        duration: TimeInterval = 32,
        holdDuration: TimeInterval = 0,
        formScore: FormScore? = nil
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
            duration: duration,
            reps: reps,
            holdDuration: holdDuration,
            latestFormScore: formScore,
            peakEffort: 0.4,
            lastCue: nil,
            completionSource: .targetMet
        )
    }

    func formScore(_ score: Int) -> FormScore {
        FormScore(
            score: score,
            grade: FormScore.Grade.from(score: score),
            romPenalty: 0,
            tempoPenalty: 0,
            feedbackPenalty: 0
        )
    }

    func makeContext(
        planId: UUID,
        target: WorkoutTarget
    ) -> WorkoutSessionContext {
        WorkoutSessionContext(
            planId: planId,
            planTitle: "Target Bridge",
            exerciseType: .squat,
            target: target,
            setIndex: 0,
            totalSets: 1,
            exerciseIndex: 0,
            totalExercises: 1,
            coach: .good,
            startsActive: false
        )
    }
}
