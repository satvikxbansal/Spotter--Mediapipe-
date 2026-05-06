import Foundation

nonisolated struct PlanExerciseIdentifier: Hashable, Identifiable {
    let blockIndex: Int
    let exerciseIndex: Int

    var id: String {
        "\(blockIndex)-\(exerciseIndex)"
    }
}

nonisolated struct TargetVolumeDraft: Equatable, Identifiable {
    let exerciseId: PlanExerciseIdentifier
    let originalExerciseType: ExerciseType
    var draftSetCount: Int
    var draftTarget: WorkoutTarget
    let minSetCount: Int
    let maxSetCount: Int
    let minTargetValue: Int
    let maxTargetValue: Int
    var validationMessage: String?

    var id: String {
        exerciseId.id
    }

    var canEditTargetValue: Bool {
        switch draftTarget {
        case .reps, .hold, .timed, .amrap(seconds: .some):
            return true
        case .amrap(seconds: nil), .open:
            return false
        }
    }

    var targetValueLabel: String {
        switch draftTarget {
        case .reps:
            return "Reps"
        case .hold, .timed, .amrap(seconds: .some):
            return "Seconds"
        case .amrap(seconds: nil):
            return "AMRAP"
        case .open:
            return "Open"
        }
    }

    var draftTargetValue: Int? {
        get {
            switch draftTarget {
            case .reps(let count):
                return count
            case .hold(let seconds), .timed(let seconds):
                return seconds
            case .amrap(let seconds):
                return seconds
            case .open:
                return nil
            }
        }
        set {
            guard let newValue else { return }
            switch draftTarget {
            case .reps:
                draftTarget = .reps(newValue)
            case .hold:
                draftTarget = .hold(seconds: newValue)
            case .timed:
                draftTarget = .timed(seconds: newValue)
            case .amrap(seconds: .some):
                draftTarget = .amrap(seconds: newValue)
            case .amrap(seconds: nil), .open:
                break
            }
        }
    }
}

nonisolated struct TargetVolumeValidation: Equatable {
    let isValid: Bool
    let didClamp: Bool
    let draft: TargetVolumeDraft
    let message: String?

    static func accepted(_ draft: TargetVolumeDraft, didClamp: Bool, message: String?) -> TargetVolumeValidation {
        TargetVolumeValidation(
            isValid: true,
            didClamp: didClamp,
            draft: draft,
            message: message
        )
    }

    static func rejected(_ draft: TargetVolumeDraft, message: String) -> TargetVolumeValidation {
        TargetVolumeValidation(
            isValid: false,
            didClamp: false,
            draft: draft,
            message: message
        )
    }
}

nonisolated final class PlanTargetEditService {
    func draft(
        for exerciseId: PlanExerciseIdentifier,
        in plan: WorkoutPlanV2,
        input: PlanGenerationInput? = nil
    ) -> TargetVolumeDraft? {
        guard let exercise = exercise(in: plan, exerciseId: exerciseId),
              let baseTarget = editableBaseTarget(for: exercise)
        else { return nil }

        let bounds = targetBounds(
            for: baseTarget,
            plan: plan,
            input: input
        )
        let validationMessage = initialValidationMessage(for: baseTarget)

        return TargetVolumeDraft(
            exerciseId: exerciseId,
            originalExerciseType: exercise.exerciseType,
            draftSetCount: max(exercise.sets.count, bounds.minSetCount),
            draftTarget: baseTarget,
            minSetCount: bounds.minSetCount,
            maxSetCount: bounds.maxSetCount,
            minTargetValue: bounds.minTargetValue,
            maxTargetValue: bounds.maxTargetValue,
            validationMessage: validationMessage
        )
    }

    func applying(
        _ draft: TargetVolumeDraft,
        to plan: WorkoutPlanV2
    ) -> (plan: WorkoutPlanV2, validation: TargetVolumeValidation) {
        guard let exercise = exercise(in: plan, exerciseId: draft.exerciseId) else {
            return (plan, .rejected(draft, message: "This movement is no longer available in the plan."))
        }

        guard editableBaseTarget(for: exercise) != nil else {
            return (plan, .rejected(draft, message: "This target is not editable yet."))
        }

        let validation = validate(draft)
        guard validation.isValid else {
            return (plan, validation)
        }

        if validation.draft.draftSetCount == exercise.sets.count,
           validation.draft.draftTarget == exercise.sets.first?.target {
            return (plan, validation)
        }

        let updatedExercise = PlannedExercise(
            exerciseType: exercise.exerciseType,
            sets: plannedSets(
                count: validation.draft.draftSetCount,
                target: validation.draft.draftTarget
            ),
            restSeconds: exercise.restSeconds,
            coachingFocus: exercise.coachingFocus,
            cameraPosition: exercise.cameraPosition,
            allowSwap: exercise.allowSwap
        )

        return (
            replacingExercise(
                in: plan,
                exerciseId: draft.exerciseId,
                with: updatedExercise
            ),
            validation
        )
    }

    func resetExercise(
        exerciseId: PlanExerciseIdentifier,
        in editedPlan: WorkoutPlanV2,
        toOriginalFrom originalPlan: WorkoutPlanV2
    ) -> WorkoutPlanV2 {
        guard let originalExercise = exercise(in: originalPlan, exerciseId: exerciseId) else {
            return editedPlan
        }

        return replacingExercise(
            in: editedPlan,
            exerciseId: exerciseId,
            with: originalExercise
        )
    }
}

nonisolated private extension PlanTargetEditService {
    enum EditableTargetStyle: Equatable {
        case reps
        case hold
        case timed
        case amrapSeconds
        case amrapOpen
    }

    struct TargetBounds {
        let minSetCount: Int
        let maxSetCount: Int
        let minTargetValue: Int
        let maxTargetValue: Int
    }

    func exercise(
        in plan: WorkoutPlanV2,
        exerciseId: PlanExerciseIdentifier
    ) -> PlannedExercise? {
        guard plan.blocks.indices.contains(exerciseId.blockIndex) else {
            return nil
        }

        let block = plan.blocks[exerciseId.blockIndex]
        guard block.exercises.indices.contains(exerciseId.exerciseIndex) else {
            return nil
        }

        return block.exercises[exerciseId.exerciseIndex]
    }

    func editableBaseTarget(for exercise: PlannedExercise) -> WorkoutTarget? {
        guard let firstTarget = exercise.sets.first?.target else { return nil }
        let firstStyle = editableStyle(for: firstTarget)
        guard firstStyle != nil,
              exercise.sets.allSatisfy({ editableStyle(for: $0.target) == firstStyle })
        else { return nil }

        return firstTarget
    }

    func editableStyle(for target: WorkoutTarget) -> EditableTargetStyle? {
        switch target {
        case .reps:
            return .reps
        case .hold:
            return .hold
        case .timed:
            return .timed
        case .amrap(seconds: .some):
            return .amrapSeconds
        case .amrap(seconds: nil):
            return .amrapOpen
        case .open:
            return nil
        }
    }

    func targetBounds(
        for target: WorkoutTarget,
        plan: WorkoutPlanV2,
        input: PlanGenerationInput?
    ) -> TargetBounds {
        let minSetCount = 1
        let maxSetCount = 5

        switch target {
        case .reps:
            let level = input?.fitnessLevel ?? fitnessLevel(for: plan.difficulty)
            let ageBracket = input?.ageBracket ?? .adult
            let maxReps: Int
            switch (level, ageBracket) {
            case (.beginner, .senior):
                maxReps = 16
            case (.beginner, .midlife):
                maxReps = 18
            case (.beginner, _):
                maxReps = 20
            case (.intermediate, .senior):
                maxReps = 20
            case (.intermediate, .midlife):
                maxReps = 24
            case (.intermediate, _):
                maxReps = 30
            }

            let minReps = level == .beginner ? 4 : 5
            return TargetBounds(
                minSetCount: minSetCount,
                maxSetCount: maxSetCount,
                minTargetValue: minReps,
                maxTargetValue: maxReps
            )
        case .hold, .timed, .amrap(seconds: .some):
            let ageBracket = input?.ageBracket ?? .adult
            let maxSeconds: Int
            switch ageBracket {
            case .senior:
                maxSeconds = 60
            case .midlife:
                maxSeconds = 75
            case .teen, .youngAdult, .adult:
                maxSeconds = 90
            }

            return TargetBounds(
                minSetCount: minSetCount,
                maxSetCount: maxSetCount,
                minTargetValue: 10,
                maxTargetValue: maxSeconds
            )
        case .amrap(seconds: nil), .open:
            return TargetBounds(
                minSetCount: minSetCount,
                maxSetCount: maxSetCount,
                minTargetValue: 0,
                maxTargetValue: 0
            )
        }
    }

    func fitnessLevel(for difficulty: ExerciseDifficulty) -> FitnessLevel {
        switch difficulty {
        case .beginner:
            return .beginner
        case .intermediate, .advanced:
            return .intermediate
        }
    }

    func initialValidationMessage(for target: WorkoutTarget) -> String? {
        switch target {
        case .amrap(seconds: nil):
            return "AMRAP targets adjust sets only for now."
        case .open:
            return "Open targets are not editable in planned workouts yet."
        case .reps, .hold, .timed, .amrap(seconds: .some):
            return nil
        }
    }

    func validate(_ draft: TargetVolumeDraft) -> TargetVolumeValidation {
        var sanitized = draft
        var didClamp = false
        var messages: [String] = []

        let clampedSetCount = clamp(
            draft.draftSetCount,
            minValue: draft.minSetCount,
            maxValue: draft.maxSetCount
        )
        if clampedSetCount != draft.draftSetCount {
            didClamp = true
            messages.append("Sets were kept between \(draft.minSetCount) and \(draft.maxSetCount).")
            sanitized.draftSetCount = clampedSetCount
        }

        if draft.canEditTargetValue,
           let targetValue = draft.draftTargetValue {
            let clampedTarget = clamp(
                targetValue,
                minValue: draft.minTargetValue,
                maxValue: draft.maxTargetValue
            )
            if clampedTarget != targetValue {
                didClamp = true
                messages.append("\(draft.targetValueLabel) were kept between \(draft.minTargetValue) and \(draft.maxTargetValue).")
                sanitized.draftTargetValue = clampedTarget
            }
        }

        if case .open = draft.draftTarget {
            return .rejected(sanitized, message: "Open targets are not editable in planned workouts yet.")
        }

        sanitized.validationMessage = (messages.first ?? draft.validationMessage)
        return .accepted(
            sanitized,
            didClamp: didClamp,
            message: messages.first ?? draft.validationMessage
        )
    }

    func clamp(_ value: Int, minValue: Int, maxValue: Int) -> Int {
        min(max(value, minValue), maxValue)
    }

    func plannedSets(count: Int, target: WorkoutTarget) -> [PlannedSet] {
        (1...count).map { index in
            PlannedSet(setIndex: index, target: target)
        }
    }

    func replacingExercise(
        in plan: WorkoutPlanV2,
        exerciseId: PlanExerciseIdentifier,
        with updatedExercise: PlannedExercise
    ) -> WorkoutPlanV2 {
        let blocks = plan.blocks.enumerated().map { blockIndex, block in
            guard blockIndex == exerciseId.blockIndex else { return block }

            let exercises = block.exercises.enumerated().map { exerciseIndex, exercise in
                exerciseIndex == exerciseId.exerciseIndex ? updatedExercise : exercise
            }

            return WorkoutBlock(
                title: block.title,
                type: block.type,
                exercises: exercises
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
