import Foundation

nonisolated enum PlanSwapReason: String, Codable, CaseIterable, Identifiable, Hashable {
    case variety
    case tooHard
    case unavailableEquipment
    case discomfort

    var id: String { rawValue }

    var coachingPrefix: String {
        switch self {
        case .variety:
            return "Swapped for variety."
        case .tooHard:
            return "Swapped to keep the session manageable."
        case .unavailableEquipment:
            return "Swapped to match available equipment."
        case .discomfort:
            return "Swapped to avoid discomfort."
        }
    }
}

nonisolated final class PlanSwapService {
    func swapExercise(
        in plan: WorkoutPlanV2,
        exerciseId: ExerciseType,
        reason: PlanSwapReason,
        input: PlanGenerationInput? = nil
    ) -> WorkoutPlanV2 {
        guard let originalMetadata = ExerciseMetadataCatalog.metadata(for: exerciseId) else {
            return plan
        }

        let exerciseTypesInPlan = Set(plan.blocks.flatMap { block in
            block.exercises.map(\.exerciseType)
        })
        let allowedEquipment = input?.effectiveEquipment ?? inferredEquipment(from: plan)
        let sessionLength = PlanSessionLength(rawMinutes: plan.estimatedMinutes)
        let cameraSwitchLimit = sessionLength.maxCameraSwitches
        let candidates = ExerciseMetadataCatalog.plannedWorkoutMetadata.filter { metadata in
            guard metadata.exerciseType != exerciseId,
                  !exerciseTypesInPlan.contains(metadata.exerciseType),
                  metadata.movementPattern == originalMetadata.movementPattern,
                  usesIsometricTargetStyle(metadata) == usesIsometricTargetStyle(originalMetadata),
                  metadata.requiredEquipment.isSubset(of: allowedEquipment),
                  let difficulty = metadata.difficulty,
                  difficultyRank(difficulty) <= difficultyRank(plan.difficulty)
            else { return false }

            if isDumbbellExercise(metadata),
               !allowedEquipment.contains(.dumbbells) {
                return false
            }

            if reason == .discomfort || reason == .tooHard {
                return !isHighImpact(metadata)
            }

            return true
        }

        guard let replacement = candidates.sorted(by: deterministicOrder).first(where: { metadata in
            let replacementSequence = currentCameraSequenceReplacing(
                exerciseId: exerciseId,
                with: metadata.exerciseType.cameraPosition,
                in: plan
            )
            return cameraSwitchCount(in: replacementSequence) <= cameraSwitchLimit
        }) else {
            return plan
        }

        let blocks = plan.blocks.map { block in
            WorkoutBlock(
                title: block.title,
                type: block.type,
                exercises: block.exercises.map { plannedExercise in
                    guard plannedExercise.exerciseType == exerciseId else {
                        return plannedExercise
                    }

                    return PlannedExercise(
                        exerciseType: replacement.exerciseType,
                        sets: plannedExercise.sets,
                        restSeconds: max(plannedExercise.restSeconds, replacement.defaultRestSeconds),
                        coachingFocus: "\(reason.coachingPrefix) \(plannedExercise.coachingFocus)",
                        cameraPosition: replacement.exerciseType.cameraPosition,
                        allowSwap: plannedExercise.allowSwap
                    )
                }
            )
        }

        return WorkoutPlanV2(
            id: plan.id,
            title: plan.title,
            subtitle: plan.subtitle,
            goal: plan.goal,
            estimatedMinutes: plan.estimatedMinutes,
            difficulty: plan.difficulty,
            coach: plan.coach,
            blocks: blocks,
            generatedAt: plan.generatedAt,
            planReason: plan.planReason,
            source: plan.source
        )
    }
}

nonisolated private extension PlanSwapService {
    func inferredEquipment(from plan: WorkoutPlanV2) -> Set<EquipmentOption> {
        var equipment: Set<EquipmentOption> = [.bodyweight]

        for exercise in plan.blocks.flatMap({ $0.exercises }) {
            if let metadata = ExerciseMetadataCatalog.metadata(for: exercise.exerciseType) {
                equipment.formUnion(metadata.requiredEquipment)
            }
        }

        return equipment
    }

    func currentCameraSequenceReplacing(
        exerciseId: ExerciseType,
        with cameraPosition: CameraPosition,
        in plan: WorkoutPlanV2
    ) -> [CameraPosition] {
        plan.blocks.flatMap { block in
            block.exercises.map { exercise in
                exercise.exerciseType == exerciseId ? cameraPosition : exercise.cameraPosition
            }
        }
    }

    func cameraSwitchCount(in cameras: [CameraPosition]) -> Int {
        guard cameras.count > 1 else { return 0 }

        var switches = 0
        for index in cameras.indices.dropFirst() {
            if cameras[index] != cameras[cameras.index(before: index)] {
                switches += 1
            }
        }
        return switches
    }

    func deterministicOrder(_ lhs: ExercisePlanMetadata, _ rhs: ExercisePlanMetadata) -> Bool {
        catalogIndex(of: lhs.exerciseType) < catalogIndex(of: rhs.exerciseType)
    }

    func catalogIndex(of exerciseType: ExerciseType) -> Int {
        ExerciseMetadataCatalog.all.firstIndex { $0.exerciseType == exerciseType } ?? Int.max
    }

    func difficultyRank(_ difficulty: ExerciseDifficulty) -> Int {
        switch difficulty {
        case .beginner:
            return 0
        case .intermediate:
            return 1
        case .advanced:
            return 2
        }
    }

    func isHighImpact(_ metadata: ExercisePlanMetadata) -> Bool {
        metadata.planTags.contains(.highImpact) || metadata.contraindicationTags.contains(.highImpact)
    }

    func isDumbbellExercise(_ metadata: ExercisePlanMetadata) -> Bool {
        metadata.requiredEquipment.contains(.dumbbells) || metadata.planTags.contains(.dumbbell)
    }

    func usesIsometricTargetStyle(_ metadata: ExercisePlanMetadata) -> Bool {
        metadata.exerciseType.definition?.movementType == .isometric ||
            metadata.planTags.contains(.isometric)
    }
}
