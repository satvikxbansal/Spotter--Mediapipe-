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

    func testEditingRepTargetUpdatesPreviewPlan() throws {
        var state = WorkoutPreviewState(plan: makeBodyweightPlan(coach: .good))
        let exerciseId = firstExerciseId()
        var draft = try XCTUnwrap(state.targetDraft(for: exerciseId))

        draft.draftTargetValue = 12
        let validation = state.applyTargetDraft(draft)

        XCTAssertTrue(validation.isValid)
        XCTAssertFalse(validation.didClamp)
        XCTAssertTrue(state.hasUserEdits)
        XCTAssertEqual(
            state.displayPlan.blocks[0].exercises[0].sets.map(\.target),
            [.reps(12), .reps(12)]
        )
    }

    func testEditingSetCountRebuildsPlannedSets() throws {
        var state = WorkoutPreviewState(plan: makeBodyweightPlan(coach: .good))
        var draft = try XCTUnwrap(state.targetDraft(for: firstExerciseId()))

        draft.draftSetCount = 3
        draft.draftTargetValue = 10
        _ = state.applyTargetDraft(draft)

        let sets = state.displayPlan.blocks[0].exercises[0].sets
        XCTAssertEqual(sets.map(\.setIndex), [1, 2, 3])
        XCTAssertEqual(sets.map(\.target), [.reps(10), .reps(10), .reps(10)])
    }

    func testSavingUnchangedDraftPreservesOriginalProgression() throws {
        var state = WorkoutPreviewState(plan: makeBodyweightPlan(coach: .good))
        let draft = try XCTUnwrap(state.targetDraft(for: firstExerciseId()))

        _ = state.applyTargetDraft(draft)

        XCTAssertFalse(state.hasUserEdits)
        XCTAssertEqual(
            state.displayPlan.blocks[0].exercises[0].sets.map(\.target),
            [.reps(8), .reps(9)]
        )
    }

    func testResetExerciseRestoresOriginalTargetAndSetCount() throws {
        var state = WorkoutPreviewState(plan: makeBodyweightPlan(coach: .good))
        let exerciseId = firstExerciseId()
        var draft = try XCTUnwrap(state.targetDraft(for: exerciseId))
        draft.draftSetCount = 3
        draft.draftTargetValue = 12
        _ = state.applyTargetDraft(draft)

        state.resetExerciseToOriginal(exerciseId)

        XCTAssertFalse(state.hasUserEdits)
        XCTAssertEqual(
            state.displayPlan.blocks[0].exercises[0].sets.map(\.target),
            [.reps(8), .reps(9)]
        )
    }

    func testInvalidTargetValuesAreClampedToSafeBounds() throws {
        let profile = makeProfile()
        var state = WorkoutPreviewState(
            plan: makeBodyweightPlan(coach: .good),
            profile: profile
        )
        var draft = try XCTUnwrap(state.targetDraft(for: firstExerciseId()))

        draft.draftSetCount = 0
        draft.draftTargetValue = 99
        let validation = state.applyTargetDraft(draft)

        XCTAssertTrue(validation.isValid)
        XCTAssertTrue(validation.didClamp)
        let sets = state.displayPlan.blocks[0].exercises[0].sets
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets.first?.target, .reps(20))
    }

    func testStartSessionUsesEditedPlanTarget() throws {
        var state = WorkoutPreviewState(plan: makeBodyweightPlan(coach: .good))
        var draft = try XCTUnwrap(state.targetDraft(for: firstExerciseId()))

        draft.draftSetCount = 3
        draft.draftTargetValue = 11
        _ = state.applyTargetDraft(draft)

        let context = try XCTUnwrap(state.startSessionContext())

        XCTAssertEqual(context.target, .reps(11))
        XCTAssertEqual(context.totalSets, 3)
    }

    func testEditingHoldAndTimedTargetsUpdatesPlan() throws {
        var holdState = WorkoutPreviewState(plan: makeIsometricPlan(coach: .good))
        var holdDraft = try XCTUnwrap(holdState.targetDraft(for: firstExerciseId()))
        holdDraft.draftSetCount = 2
        holdDraft.draftTargetValue = 35
        _ = holdState.applyTargetDraft(holdDraft)

        XCTAssertEqual(
            holdState.displayPlan.blocks[0].exercises[0].sets.map(\.target),
            [.hold(seconds: 35), .hold(seconds: 35)]
        )
        XCTAssertEqual(holdState.startSessionContext()?.target, .seconds(35))

        var timedState = WorkoutPreviewState(plan: makeTimedPlan(coach: .good))
        var timedDraft = try XCTUnwrap(timedState.targetDraft(for: firstExerciseId()))
        timedDraft.draftTargetValue = 45
        _ = timedState.applyTargetDraft(timedDraft)

        XCTAssertEqual(timedState.displayPlan.blocks[0].exercises[0].sets.first?.target, .timed(seconds: 45))
        XCTAssertEqual(timedState.startSessionContext()?.target, .seconds(45))
    }

    func testOpenTargetsAreNotEditableInPreview() {
        let state = WorkoutPreviewState(plan: makeOpenPlan(coach: .good))

        XCTAssertNil(state.targetDraft(for: firstExerciseId()))
    }
}

private extension WorkoutPreviewTests {
    func firstExerciseId() -> PlanExerciseIdentifier {
        PlanExerciseIdentifier(blockIndex: 0, exerciseIndex: 0)
    }

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

    func makeTimedPlan(coach: CoachPersonality) -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000080A") ?? UUID(),
            title: "Preview Timed",
            subtitle: "Generated preview",
            goal: "Build steady conditioning.",
            estimatedMinutes: 7,
            difficulty: .beginner,
            coach: coach,
            blocks: [
                WorkoutBlock(
                    title: "Timed Practice",
                    type: .main,
                    exercises: [
                        PlannedExercise(
                            exerciseType: .jumpingJack,
                            sets: [
                                PlannedSet(setIndex: 1, target: .timed(seconds: 30))
                            ],
                            restSeconds: 45,
                            coachingFocus: "Move smoothly and stay visible.",
                            cameraPosition: .front,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: Date(timeIntervalSince1970: 1_776_000_000),
            planReason: "Generated locally for timed target editing.",
            source: .generatedLocal
        )
    }

    func makeOpenPlan(coach: CoachPersonality) -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000080B") ?? UUID(),
            title: "Preview Open",
            subtitle: "Generated preview",
            goal: "Practice without a fixed target.",
            estimatedMinutes: 7,
            difficulty: .beginner,
            coach: coach,
            blocks: [
                WorkoutBlock(
                    title: "Open Practice",
                    type: .main,
                    exercises: [
                        PlannedExercise(
                            exerciseType: .pushup,
                            sets: [
                                PlannedSet(setIndex: 1, target: .open)
                            ],
                            restSeconds: 60,
                            coachingFocus: "Stop manually when finished.",
                            cameraPosition: .side,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: Date(timeIntervalSince1970: 1_776_000_000),
            planReason: "Generated locally for open target editing.",
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
