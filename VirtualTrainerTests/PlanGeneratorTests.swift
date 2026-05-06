import XCTest
@testable import VirtualTrainer

final class PlanGeneratorTests: XCTestCase {
    private let generator = PlanGenerator()
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

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

    func testGeneratedRestSecondsUseMetadataAndAgePolicy() throws {
        let profile = makeProfile(
            age: 65,
            goal: .longevity,
            level: .beginner,
            equipment: [.bodyweight, .mat]
        )
        let input = PlanGenerationInput(profile: profile, sessionLength: .twentyFive)
        let rules = PlanGenerationRules.resolved(for: input)

        let plan = generator.generate(input: input)

        XCTAssertEqual(rules.restBonusSeconds, 30)
        for block in plan.blocks {
            for exercise in block.exercises {
                let metadata = try XCTUnwrap(ExerciseMetadataCatalog.metadata(for: exercise.exerciseType))
                let slotBonus = block.type == .finisher ? -10 : 0
                XCTAssertEqual(
                    exercise.restSeconds,
                    max(15, metadata.defaultRestSeconds + rules.restBonusSeconds + slotBonus),
                    "\(exercise.exerciseType.rawValue) rest should come from metadata plus age/session policy"
                )
            }
        }
    }

    func testQuickStartDeckHasFiveSafeSevenMinuteVariantsWhenPossible() throws {
        let profile = makeProfile(
            goal: .strength,
            level: .intermediate,
            equipment: [.bodyweight, .dumbbells, .mat, .wall]
        )
        let now = try makeDate(year: 2026, month: 5, day: 6)
        let deck = makeDeckService().generateDeck(profile: profile, now: now)

        XCTAssertLessThanOrEqual(deck.variants.count, 5)
        XCTAssertEqual(deck.variants.count, 5)
        XCTAssertEqual(
            deck.variants.filter { $0.intensityLabel == .beginner }.count,
            2
        )
        XCTAssertEqual(
            deck.variants.filter { $0.intensityLabel == .intermediate }.count,
            3
        )

        let input = PlanGenerationInput(profile: profile, sessionLength: .seven)
        for variant in deck.variants {
            XCTAssertEqual(variant.plan.estimatedMinutes, 7)
            XCTAssertLessThanOrEqual(
                cameraSwitchCount(in: variant.plan),
                PlanSessionLength.seven.maxCameraSwitches,
                "\(variant.title) exceeded the 7-minute camera switch limit"
            )

            for exercise in plannedExercises(in: variant.plan) {
                let metadata = try XCTUnwrap(ExerciseMetadataCatalog.metadata(for: exercise.exerciseType))
                XCTAssertTrue(
                    metadata.requiredEquipment.isSubset(of: input.effectiveEquipment),
                    "\(variant.title) included unavailable equipment for \(exercise.exerciseType.rawValue)"
                )
            }
        }
    }

    func testQuickStartDeckIsStableForSameProfileAndDay() throws {
        let profile = makeProfile(
            goal: .performance,
            level: .intermediate,
            equipment: [.bodyweight, .mat, .wall]
        )
        let now = try makeDate(year: 2026, month: 5, day: 6)
        let service = makeDeckService()

        let firstDeck = service.generateDeck(profile: profile, now: now)
        let secondDeck = service.generateDeck(profile: profile, now: now)

        XCTAssertEqual(firstDeck, secondDeck)
    }

    func testQuickStartDeckChangesAcrossDays() throws {
        let profile = makeProfile(
            goal: .longevity,
            level: .intermediate,
            equipment: [.bodyweight, .mat, .wall]
        )
        let today = try makeDate(year: 2026, month: 5, day: 6)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let service = makeDeckService()

        let todayDeck = service.generateDeck(profile: profile, now: today)
        let tomorrowDeck = service.generateDeck(profile: profile, now: tomorrow)

        XCTAssertNotEqual(
            todayDeck.variants.map(\.id),
            tomorrowDeck.variants.map(\.id)
        )
    }

    func testQuickStartVariantSeedChangesSmartStartPlan() throws {
        let profile = makeProfile(
            goal: .strength,
            level: .intermediate,
            equipment: [.bodyweight, .dumbbells, .mat, .wall]
        )
        let now = try makeDate(year: 2026, month: 5, day: 6)
        let planService = PlanService(
            generator: generator,
            quickStartDeckService: makeDeckService()
        )

        let firstPlan = planService.generateSmartStart(
            profile: profile,
            variantSeed: "alpha",
            now: now
        )
        let secondPlan = planService.generateSmartStart(
            profile: profile,
            variantSeed: "beta",
            now: now
        )

        XCTAssertNotEqual(firstPlan.id, secondPlan.id)
    }

    func testBeginnerQuickStartIntermediateOptionsUseChallengeLite() throws {
        let profile = makeProfile(
            goal: .performance,
            level: .beginner,
            equipment: [.bodyweight, .mat, .wall]
        )
        let now = try makeDate(year: 2026, month: 5, day: 6)
        let deck = makeDeckService().generateDeck(profile: profile, now: now)
        let challengeVariants = deck.variants.filter { $0.intensityLabel == .intermediate }

        XCTAssertEqual(challengeVariants.count, 3)
        XCTAssertTrue(challengeVariants.allSatisfy { $0.plan.difficulty == .beginner })
        XCTAssertTrue(challengeVariants.allSatisfy { $0.reason.contains("Challenge Lite") })
    }
}

private extension PlanGeneratorTests {
    func makeDeckService() -> QuickStartPlanDeckService {
        QuickStartPlanDeckService(generator: generator, calendar: calendar)
    }

    func makeDate(year: Int, month: Int, day: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

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
