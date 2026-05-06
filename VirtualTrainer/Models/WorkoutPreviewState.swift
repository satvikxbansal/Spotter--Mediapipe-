import Foundation

nonisolated struct WorkoutPreviewState: Equatable {
    private(set) var originalPlan: WorkoutPlanV2
    private(set) var editedPlan: WorkoutPlanV2
    let input: PlanGenerationInput?
    private(set) var selectedCoach: CoachPersonality

    init(
        plan: WorkoutPlanV2,
        profile: UserProfile? = nil
    ) {
        self.originalPlan = plan
        self.editedPlan = plan
        self.input = profile.map {
            PlanGenerationInput(
                profile: $0,
                sessionLengthMinutes: plan.estimatedMinutes
            )
        }
        self.selectedCoach = plan.coach
    }

    var displayPlan: WorkoutPlanV2 {
        editedPlan.replacingCoach(selectedCoach)
    }

    var exercises: [PlannedExercise] {
        displayPlan.blocks.flatMap(\.exercises)
    }

    var exerciseCount: Int {
        exercises.count
    }

    var allowedEquipment: Set<EquipmentOption> {
        if let input {
            return input.effectiveEquipment
        }

        var equipment: Set<EquipmentOption> = [.bodyweight]
        for exercise in exercises {
            guard let metadata = ExerciseMetadataCatalog.metadata(for: exercise.exerciseType) else {
                continue
            }
            equipment.formUnion(metadata.requiredEquipment)
        }
        return equipment
    }

    var cameraSwitchLimit: Int {
        PlanSessionLength(rawMinutes: displayPlan.estimatedMinutes).maxCameraSwitches
    }

    var cameraSwitchCount: Int {
        Self.cameraSwitchCount(in: exercises.map(\.cameraPosition))
    }

    var cameraSequenceText: String {
        let names = exercises.map { Self.cameraText(for: $0.cameraPosition) }
        guard !names.isEmpty else { return "No camera setup needed yet." }
        return names.joined(separator: " -> ")
    }

    var hasUserEdits: Bool {
        editedPlan.replacingCoach(originalPlan.coach) != originalPlan
    }

    mutating func selectCoach(_ coach: CoachPersonality) {
        selectedCoach = coach
        editedPlan = editedPlan.replacingCoach(coach)
    }

    mutating func swapExercise(
        _ exerciseType: ExerciseType,
        reason: PlanSwapReason = .variety,
        planService: PlanService = PlanService()
    ) -> Bool {
        let before = displayPlan
        let updated = input.map {
            planService.swapExercise(
                in: before,
                exerciseId: exerciseType,
                reason: reason,
                input: $0
            )
        } ?? planService.swapExercise(
            in: before,
            exerciseId: exerciseType,
            reason: reason
        )

        editedPlan = updated.replacingCoach(selectedCoach)
        return updated != before
    }

    mutating func swapAll(
        reason: PlanSwapReason = .variety,
        planService: PlanService = PlanService()
    ) -> Bool {
        let before = displayPlan
        let updated = planService.swapAll(
            in: before,
            reason: reason,
            input: input
        )

        editedPlan = updated.replacingCoach(selectedCoach)
        return updated != before
    }

    func targetDraft(
        for exerciseId: PlanExerciseIdentifier,
        service: PlanTargetEditService = PlanTargetEditService()
    ) -> TargetVolumeDraft? {
        service.draft(
            for: exerciseId,
            in: displayPlan,
            input: input
        )
    }

    @discardableResult
    mutating func applyTargetDraft(
        _ draft: TargetVolumeDraft,
        service: PlanTargetEditService = PlanTargetEditService()
    ) -> TargetVolumeValidation {
        let result = service.applying(
            draft,
            to: displayPlan
        )

        if result.validation.isValid {
            editedPlan = result.plan.replacingCoach(selectedCoach)
        }

        return result.validation
    }

    mutating func resetToOriginalPlan() {
        editedPlan = originalPlan.replacingCoach(selectedCoach)
    }

    mutating func resetExerciseToOriginal(
        _ exerciseId: PlanExerciseIdentifier,
        service: PlanTargetEditService = PlanTargetEditService()
    ) {
        editedPlan = service.resetExercise(
            exerciseId: exerciseId,
            in: displayPlan,
            toOriginalFrom: originalPlan
        )
        .replacingCoach(selectedCoach)
    }

    func startSessionContext(startsActive: Bool = false) -> LiveSessionContext? {
        LiveSessionContext.plannedWorkout(
            plan: displayPlan,
            coach: selectedCoach,
            startsActive: startsActive
        )
    }

    static func cameraSwitchCount(in cameras: [CameraPosition]) -> Int {
        guard cameras.count > 1 else { return 0 }

        var switches = 0
        for index in cameras.indices.dropFirst() {
            if cameras[index] != cameras[cameras.index(before: index)] {
                switches += 1
            }
        }
        return switches
    }

    static func cameraText(for cameraPosition: CameraPosition) -> String {
        switch cameraPosition {
        case .front:
            return "Front"
        case .side:
            return "Side"
        }
    }
}
