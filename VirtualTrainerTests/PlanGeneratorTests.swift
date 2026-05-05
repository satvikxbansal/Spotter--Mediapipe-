import XCTest
@testable import VirtualTrainer

final class PlanGeneratorTests: XCTestCase {
    private let generator = PlanGenerator()

    func testBeginnerStrengthBodyweightPlanHasNoDumbbellExercises() {
        let profile = makeProfile(
            goal: .strength,
            level: .beginner,
            equipment: [.bodyweight]
        )

        let plan = generator.generate(
            input: PlanGenerationInput(profile: profile, sessionLength: .twentyFive)
        )

        for exercise in plannedExercises(in: plan) {
            let metadata = ExerciseMetadataCatalog.metadata(for: exercise.exerciseType)
            XCTAssertFalse(
                metadata?.requiredEquipment.contains(.dumbbells) ?? false,
                "\(exercise.exerciseType.rawValue) requires dumbbells"
            )
            XCTAssertFalse(
                metadata?.planTags.contains(.dumbbell) ?? false,
                "\(exercise.exerciseType.rawValue) is tagged as a dumbbell exercise"
            )
        }
    }

    func testBeginnerPerformanceAgeFiftyPlusAvoidsHighImpactWhenAlternativesExist() {
        let profile = makeProfile(
            age: 55,
            goal: .performance,
            level: .beginner,
            equipment: [.bodyweight]
        )

        let plan = generator.generate(
            input: PlanGenerationInput(profile: profile, sessionLength: .twentyFive)
        )

        for exercise in plannedExercises(in: plan) {
            let metadata = ExerciseMetadataCatalog.metadata(for: exercise.exerciseType)
            XCTAssertFalse(
                metadata?.planTags.contains(.highImpact) ?? false,
                "\(exercise.exerciseType.rawValue) should avoid high-impact work for 50+ performance plans"
            )
            XCTAssertFalse(
                metadata?.contraindicationTags.contains(.highImpact) ?? false,
                "\(exercise.exerciseType.rawValue) has high-impact contraindication"
            )
        }
    }

    func testLongevityPlanIncludesMobilityBalanceAndIsometricWork() {
        let profile = makeProfile(
            goal: .longevity,
            level: .beginner,
            equipment: [.bodyweight]
        )

        let plan = generator.generate(
            input: PlanGenerationInput(profile: profile, sessionLength: .twentyFive)
        )
        let metadata = plannedExercises(in: plan).compactMap {
            ExerciseMetadataCatalog.metadata(for: $0.exerciseType)
        }

        XCTAssertTrue(metadata.contains { $0.movementPattern == .mobility || $0.movementPattern == .yogaHold })
        XCTAssertTrue(metadata.contains { $0.movementPattern == .balance })
        XCTAssertTrue(metadata.contains { $0.planTags.contains(.isometric) })
    }

    func testIntermediateDumbbellStrengthIncludesDumbbellExerciseWhenAvailable() {
        let profile = makeProfile(
            goal: .strength,
            level: .intermediate,
            equipment: [.bodyweight, .dumbbells]
        )

        let plan = generator.generate(
            input: PlanGenerationInput(profile: profile, sessionLength: .twentyFive)
        )
        let metadata = plannedExercises(in: plan).compactMap {
            ExerciseMetadataCatalog.metadata(for: $0.exerciseType)
        }

        XCTAssertTrue(
            metadata.contains { $0.requiredEquipment.contains(.dumbbells) || $0.planTags.contains(.dumbbell) }
        )
    }

    func testSevenMinutePlanHasMaxFourExercises() {
        let profile = makeProfile(
            goal: .strength,
            level: .beginner,
            equipment: [.bodyweight]
        )

        let plan = generator.generate(
            input: PlanGenerationInput(profile: profile, sessionLength: .seven)
        )

        XCTAssertLessThanOrEqual(plannedExercises(in: plan).count, 4)
    }

    func testCameraSwitchLimitIsRespected() {
        for sessionLength in PlanSessionLength.allCases {
            let profile = makeProfile(
                goal: .performance,
                level: .intermediate,
                equipment: [.bodyweight, .dumbbells, .mat]
            )

            let plan = generator.generate(
                input: PlanGenerationInput(profile: profile, sessionLength: sessionLength)
            )

            XCTAssertLessThanOrEqual(
                cameraSwitchCount(in: plan),
                sessionLength.maxCameraSwitches,
                "\(sessionLength.rawValue)-minute plan exceeded camera switch limit"
            )
        }
    }

    func testAllPlannedTargetsAreNotOpen() {
        let profile = makeProfile(
            goal: .longevity,
            level: .beginner,
            equipment: [.bodyweight, .mat]
        )

        let plan = generator.generate(
            input: PlanGenerationInput(profile: profile, sessionLength: .thirtyFive)
        )

        for target in plannedTargets(in: plan) {
            XCTAssertFalse(target == .open)
        }
    }

    func testGeneratedPlanCodableRoundtrip() throws {
        let planId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000606"))
        let generatedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let profile = makeProfile(
            goal: .strength,
            level: .intermediate,
            equipment: [.bodyweight, .dumbbells, .mat]
        )

        let plan = generator.generate(
            input: PlanGenerationInput(profile: profile, sessionLength: .twentyFive),
            planId: planId,
            generatedAt: generatedAt
        )

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(WorkoutPlanV2.self, from: data)

        XCTAssertEqual(decoded, plan)
    }
}

private extension PlanGeneratorTests {
    func makeProfile(
        age: Int = 30,
        goal: FitnessGoal,
        level: FitnessLevel,
        equipment: Set<EquipmentOption>
    ) -> UserProfile {
        let now = Date(timeIntervalSince1970: 1_776_000_000)
        return UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000999") ?? UUID(),
            displayName: "Test Athlete",
            genderIdentity: .preferNotToSay,
            age: age,
            height: 175,
            heightUnit: .metric,
            weight: 72,
            weightUnit: .metric,
            primaryGoal: goal,
            fitnessLevel: level,
            equipment: equipment.sorted { $0.rawValue < $1.rawValue },
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    func plannedExercises(in plan: WorkoutPlanV2) -> [PlannedExercise] {
        plan.blocks.flatMap(\.exercises)
    }

    func plannedTargets(in plan: WorkoutPlanV2) -> [WorkoutTarget] {
        plannedExercises(in: plan).flatMap { exercise in
            exercise.sets.map(\.target)
        }
    }

    func cameraSwitchCount(in plan: WorkoutPlanV2) -> Int {
        let cameras = plannedExercises(in: plan).map(\.cameraPosition)
        guard cameras.count > 1 else { return 0 }

        var switches = 0
        for index in cameras.indices.dropFirst() {
            if cameras[index] != cameras[cameras.index(before: index)] {
                switches += 1
            }
        }
        return switches
    }
}
