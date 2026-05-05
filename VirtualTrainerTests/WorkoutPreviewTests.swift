import XCTest
@testable import VirtualTrainer

final class WorkoutPreviewTests: XCTestCase {
    func testPreviewStateRendersGeneratedPlan() {
        let profile = makeProfile(equipment: [.bodyweight, .wall, .mat])
        let plan = PlanService().generateDailyPlan(profile: profile)
        let state = WorkoutPreviewState(plan: plan, profile: profile)

        XCTAssertEqual(state.displayPlan.title, plan.title)
        XCTAssertEqual(state.displayPlan.subtitle, plan.subtitle)
        XCTAssertEqual(state.displayPlan.planReason, plan.planReason)
        XCTAssertFalse(state.displayPlan.blocks.isEmpty)
        XCTAssertFalse(state.exercises.isEmpty)
    }

    func testCoachCanBeChangedWithoutChangingProfileDefault() {
        let profile = makeProfile(preferredCoach: .bennett)
        let plan = makeBodyweightPlan(coach: .good)
        var state = WorkoutPreviewState(plan: plan, profile: profile)

        state.selectCoach(.drill)

        XCTAssertEqual(state.selectedCoach, .drill)
        XCTAssertEqual(state.displayPlan.coach, .drill)
        XCTAssertEqual(profile.preferredCoach, .bennett)
    }

    func testSavingDefaultCoachUpdatesProfileWhenRequested() async {
        await MainActor.run {
            let store = OnboardingStore(fileURL: temporaryProfileURL())
            store.draft = validDraft(preferredCoach: .bennett)
            store.completeOnboarding()

            store.updatePreferredCoach(.fletcher)

            XCTAssertEqual(store.profile?.preferredCoach, .fletcher)
        }
    }

    func testSwappingExerciseKeepsEquipmentConstraints() {
        let profile = makeProfile(equipment: [.bodyweight])
        let input = PlanGenerationInput(profile: profile, sessionLength: .seven)
        let plan = makeBodyweightPlan(coach: .good)
        var state = WorkoutPreviewState(plan: plan, profile: profile)

        let didSwap = state.swapExercise(.squat)

        XCTAssertTrue(didSwap)
        XCTAssertEqual(state.exercises.first?.exerciseType, .sumoSquat)
        XCTAssertLessThanOrEqual(state.cameraSwitchCount, input.sessionLength.maxCameraSwitches)
        for exercise in state.exercises {
            let metadata = ExerciseMetadataCatalog.metadata(for: exercise.exerciseType)
            XCTAssertTrue(
                metadata?.requiredEquipment.isSubset(of: input.effectiveEquipment) ?? false,
                "\(exercise.exerciseType.rawValue) introduced unavailable equipment"
            )
        }
    }

    func testSwappingPreservesIsometricTargetStyle() {
        let profile = makeProfile(equipment: [.bodyweight, .wall])
        var state = WorkoutPreviewState(plan: makeIsometricPlan(coach: .good), profile: profile)

        let didSwap = state.swapExercise(.wallSit)

        XCTAssertFalse(didSwap)
        XCTAssertEqual(state.exercises.first?.exerciseType, .wallSit)
        XCTAssertEqual(state.exercises.first?.sets.first?.target, .hold(seconds: 20))
    }

    func testSwapAllStaysWithinEquipmentAndCameraConstraints() {
        let profile = makeProfile(equipment: [.bodyweight])
        let input = PlanGenerationInput(profile: profile, sessionLength: .seven)
        var state = WorkoutPreviewState(plan: makeBodyweightPlan(coach: .good), profile: profile)

        _ = state.swapAll()

        XCTAssertLessThanOrEqual(state.cameraSwitchCount, state.cameraSwitchLimit)
        XCTAssertEqual(state.cameraSwitchLimit, input.sessionLength.maxCameraSwitches)
        for exercise in state.exercises {
            let metadata = ExerciseMetadataCatalog.metadata(for: exercise.exerciseType)
            XCTAssertTrue(
                metadata?.requiredEquipment.isSubset(of: input.effectiveEquipment) ?? false,
                "\(exercise.exerciseType.rawValue) introduced unavailable equipment"
            )
        }
    }

    func testStartSessionCreatesPlannedWorkoutContext() throws {
        var state = WorkoutPreviewState(plan: makeBodyweightPlan(coach: .good))
        state.selectCoach(.drill)

        let context = try XCTUnwrap(state.startSessionContext())

        XCTAssertEqual(context.mode, .plannedWorkout)
        XCTAssertEqual(context.exerciseType, .squat)
        XCTAssertEqual(context.target, .reps(8))
        XCTAssertEqual(context.planId, state.displayPlan.id)
        XCTAssertEqual(context.setIndex, 0)
        XCTAssertEqual(context.totalSets, 2)
        XCTAssertEqual(context.coach, .drill)
        XCTAssertFalse(context.startsActive)
    }
}

private extension WorkoutPreviewTests {
    func makeBodyweightPlan(coach: CoachPersonality) -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000808") ?? UUID(),
            title: "Preview Strength",
            subtitle: "Generated preview",
            goal: "Build clean strength without extra equipment.",
            estimatedMinutes: 7,
            difficulty: .beginner,
            coach: coach,
            blocks: [
                WorkoutBlock(
                    title: "Strength Practice",
                    type: .main,
                    exercises: [
                        PlannedExercise(
                            exerciseType: .squat,
                            sets: [
                                PlannedSet(setIndex: 1, target: .reps(8)),
                                PlannedSet(setIndex: 2, target: .reps(9))
                            ],
                            restSeconds: 60,
                            coachingFocus: "Depth, tempo, and knee tracking.",
                            cameraPosition: .front,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: Date(timeIntervalSince1970: 1_776_000_000),
            planReason: "Generated locally for a bodyweight beginner plan.",
            source: .generatedLocal
        )
    }

    func makeIsometricPlan(coach: CoachPersonality) -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000809") ?? UUID(),
            title: "Preview Hold",
            subtitle: "Generated preview",
            goal: "Build lower-body endurance.",
            estimatedMinutes: 7,
            difficulty: .beginner,
            coach: coach,
            blocks: [
                WorkoutBlock(
                    title: "Hold Practice",
                    type: .main,
                    exercises: [
                        PlannedExercise(
                            exerciseType: .wallSit,
                            sets: [
                                PlannedSet(setIndex: 1, target: .hold(seconds: 20))
                            ],
                            restSeconds: 60,
                            coachingFocus: "Keep knees tracking and back supported.",
                            cameraPosition: .front,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: Date(timeIntervalSince1970: 1_776_000_000),
            planReason: "Generated locally for an isometric beginner plan.",
            source: .generatedLocal
        )
    }

    func makeProfile(
        equipment: Set<EquipmentOption> = [.bodyweight],
        preferredCoach: CoachPreference = .bennett
    ) -> UserProfile {
        let now = Date(timeIntervalSince1970: 1_776_000_000)
        return UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000909") ?? UUID(),
            displayName: "Test Athlete",
            genderIdentity: .preferNotToSay,
            age: 30,
            height: 175,
            heightUnit: .metric,
            weight: 72,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .beginner,
            equipment: equipment.sorted { $0.rawValue < $1.rawValue },
            preferredCoach: preferredCoach,
            selectedTheme: .hyper,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    @MainActor
    func validDraft(preferredCoach: CoachPreference) -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft.displayName = "Test Athlete"
        draft.genderIdentity = .preferNotToSay
        draft.age = "30"
        draft.height = "175"
        draft.weight = "72"
        draft.primaryGoal = .strength
        draft.fitnessLevel = .beginner
        draft.equipment = [.bodyweight]
        draft.preferredCoach = preferredCoach
        return draft
    }

    func temporaryProfileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("UserProfile.json")
    }
}
