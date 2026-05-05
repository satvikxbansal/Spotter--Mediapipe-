import XCTest
@testable import VirtualTrainer

final class WorkoutPlanV2Tests: XCTestCase {
    func testTargetFormatting() {
        XCTAssertEqual(WorkoutTarget.reps(1).formattedText, "1 rep")
        XCTAssertEqual(WorkoutTarget.reps(12).formattedText, "12 reps")
        XCTAssertEqual(WorkoutTarget.hold(seconds: 45).formattedText, "45 sec hold")
        XCTAssertEqual(WorkoutTarget.timed(seconds: 90).formattedText, "1:30 work")
        XCTAssertEqual(WorkoutTarget.amrap(seconds: 300).formattedText, "AMRAP 5:00")
        XCTAssertEqual(WorkoutTarget.amrap(seconds: nil).formattedText, "AMRAP")
        XCTAssertEqual(WorkoutTarget.open.formattedText, "Open")
        XCTAssertEqual(WorkoutTarget.formatTargetText(.timed(seconds: 30)), "30 sec work")
    }

    func testWorkoutPlanV2CodableRoundtrip() throws {
        let planId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
        let plan = WorkoutPlanV2(
            id: planId,
            title: "Phase 5 Mixed Targets",
            subtitle: "Reps, holds, timed work, and free mode",
            goal: "Build resilient full-body capacity",
            estimatedMinutes: 24,
            difficulty: .intermediate,
            coach: .drill,
            blocks: [
                WorkoutBlock(
                    title: "Warmup",
                    type: .warmup,
                    exercises: [
                        PlannedExercise(
                            exerciseType: .jumpingJack,
                            sets: [
                                PlannedSet(setIndex: 1, target: .timed(seconds: 120))
                            ],
                            restSeconds: 20,
                            coachingFocus: "Find rhythm and full-body visibility.",
                            cameraPosition: .front,
                            allowSwap: true
                        )
                    ]
                ),
                WorkoutBlock(
                    title: "Main",
                    type: .main,
                    exercises: [
                        PlannedExercise(
                            exerciseType: .squat,
                            sets: [
                                PlannedSet(setIndex: 1, target: .reps(10)),
                                PlannedSet(setIndex: 2, target: .amrap(seconds: 180))
                            ],
                            restSeconds: 60,
                            coachingFocus: "Depth, knee tracking, and tempo.",
                            cameraPosition: .front,
                            allowSwap: false
                        ),
                        PlannedExercise(
                            exerciseType: .plank,
                            sets: [
                                PlannedSet(setIndex: 1, target: .hold(seconds: 45)),
                                PlannedSet(setIndex: 2, target: .open)
                            ],
                            restSeconds: 45,
                            coachingFocus: "Brace cleanly and keep the body line long.",
                            cameraPosition: .side,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: Date(timeIntervalSince1970: 1_776_000_000),
            planReason: "Covers every WorkoutTarget case used by the planner.",
            source: .aiAssisted
        )

        let data = try JSONEncoder().encode(plan)
        let decodedPlan = try JSONDecoder().decode(WorkoutPlanV2.self, from: data)

        XCTAssertEqual(decodedPlan, plan)
    }

    func testLegacyWorkoutPlanConversionGroupsConsecutiveSets() throws {
        let legacyPlanId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000456"))
        let legacyPlan = WorkoutPlan(
            id: legacyPlanId,
            title: "Legacy Legs",
            subtitle: "Lower Body",
            exercises: [
                WorkoutSet(exerciseType: .squat, targetReps: 12),
                WorkoutSet(exerciseType: .squat, targetReps: 10),
                WorkoutSet(exerciseType: .wallSit, targetReps: 30)
            ],
            estimatedMinutes: 12
        )

        let plan = legacyPlan.convertedToV2(
            goal: "Convert without losing targets",
            coach: .good,
            generatedAt: Date(timeIntervalSince1970: 1_776_000_000)
        )

        XCTAssertEqual(plan.id, legacyPlan.id)
        XCTAssertEqual(plan.blocks.count, 1)
        XCTAssertEqual(plan.blocks.first?.type, .main)
        XCTAssertEqual(plan.blocks.first?.exercises.count, 2)
        XCTAssertEqual(plan.blocks.first?.exercises.first?.sets.map(\.target), [.reps(12), .reps(10)])
        XCTAssertEqual(plan.blocks.first?.exercises.last?.exerciseType, .wallSit)
        XCTAssertEqual(plan.blocks.first?.exercises.last?.sets.first?.target, .hold(seconds: 30))
    }
}
