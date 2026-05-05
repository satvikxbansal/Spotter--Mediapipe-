import Foundation

nonisolated struct PlannedWorkoutCoordinator {
    let plan: WorkoutPlanV2
    let startedAt: Date

    private(set) var currentBlockIndex: Int
    private(set) var currentExerciseIndex: Int
    private(set) var currentSetIndex: Int
    private(set) var completedSetSummaries: [PlannedWorkoutSetSummary]
    private(set) var isAwaitingContinue: Bool
    private(set) var isSessionComplete: Bool

    init(plan: WorkoutPlanV2, startedAt: Date = Date()) {
        self.plan = plan
        self.startedAt = startedAt
        self.completedSetSummaries = []
        self.isAwaitingContinue = false

        if let firstPosition = Self.firstSetPosition(in: plan) {
            self.currentBlockIndex = firstPosition.blockIndex
            self.currentExerciseIndex = firstPosition.exerciseIndex
            self.currentSetIndex = firstPosition.setIndex
            self.isSessionComplete = false
        } else {
            self.currentBlockIndex = 0
            self.currentExerciseIndex = 0
            self.currentSetIndex = 0
            self.isSessionComplete = true
        }
    }

    var currentTarget: WorkoutTarget? {
        currentSet?.target
    }

    var currentContext: WorkoutSessionContext? {
        guard !isSessionComplete,
              let exercise = currentExercise,
              let set = currentSet
        else { return nil }

        return WorkoutSessionContext(
            planId: plan.id,
            planTitle: plan.title,
            exerciseType: exercise.exerciseType,
            target: set.target,
            setIndex: currentSetIndex,
            totalSets: exercise.sets.count,
            exerciseIndex: currentGlobalExerciseIndex,
            totalExercises: totalExercises,
            coach: plan.coach,
            startsActive: false
        )
    }

    var hasNextSet: Bool {
        guard let position = currentPosition else { return false }
        return Self.nextSetPosition(after: position, in: plan) != nil
    }

    @discardableResult
    mutating func completeCurrentSet(with summary: PlannedWorkoutSetSummary) -> Bool {
        guard !isSessionComplete,
              !isAwaitingContinue,
              summary.planId == plan.id,
              summary.exerciseIndex == currentGlobalExerciseIndex,
              summary.setIndex == currentSetIndex
        else { return false }

        completedSetSummaries.append(summary)
        isAwaitingContinue = true
        return true
    }

    mutating func continueToNextSet() {
        guard isAwaitingContinue,
              let position = currentPosition
        else { return }

        if let nextPosition = Self.nextSetPosition(after: position, in: plan) {
            currentBlockIndex = nextPosition.blockIndex
            currentExerciseIndex = nextPosition.exerciseIndex
            currentSetIndex = nextPosition.setIndex
            isAwaitingContinue = false
        } else {
            isAwaitingContinue = false
            isSessionComplete = true
        }
    }
}

nonisolated private extension PlannedWorkoutCoordinator {
    struct SetPosition {
        let blockIndex: Int
        let exerciseIndex: Int
        let setIndex: Int
    }

    var currentBlock: WorkoutBlock? {
        guard plan.blocks.indices.contains(currentBlockIndex) else { return nil }
        return plan.blocks[currentBlockIndex]
    }

    var currentExercise: PlannedExercise? {
        guard let currentBlock,
              currentBlock.exercises.indices.contains(currentExerciseIndex)
        else { return nil }
        return currentBlock.exercises[currentExerciseIndex]
    }

    var currentSet: PlannedSet? {
        guard let currentExercise,
              currentExercise.sets.indices.contains(currentSetIndex)
        else { return nil }
        return currentExercise.sets[currentSetIndex]
    }

    var currentPosition: SetPosition? {
        guard !isSessionComplete,
              currentBlock != nil,
              currentExercise != nil,
              currentSet != nil
        else { return nil }

        return SetPosition(
            blockIndex: currentBlockIndex,
            exerciseIndex: currentExerciseIndex,
            setIndex: currentSetIndex
        )
    }

    var totalExercises: Int {
        plan.blocks.reduce(0) { $0 + $1.exercises.count }
    }

    var currentGlobalExerciseIndex: Int {
        guard plan.blocks.indices.contains(currentBlockIndex) else { return 0 }

        let exercisesBeforeCurrentBlock = plan.blocks
            .prefix(currentBlockIndex)
            .reduce(0) { $0 + $1.exercises.count }

        return exercisesBeforeCurrentBlock + currentExerciseIndex
    }

    static func firstSetPosition(in plan: WorkoutPlanV2) -> SetPosition? {
        for blockIndex in plan.blocks.indices {
            let block = plan.blocks[blockIndex]
            for exerciseIndex in block.exercises.indices {
                guard !block.exercises[exerciseIndex].sets.isEmpty else { continue }
                return SetPosition(
                    blockIndex: blockIndex,
                    exerciseIndex: exerciseIndex,
                    setIndex: 0
                )
            }
        }
        return nil
    }

    static func nextSetPosition(
        after position: SetPosition,
        in plan: WorkoutPlanV2
    ) -> SetPosition? {
        guard plan.blocks.indices.contains(position.blockIndex) else { return nil }

        let currentBlock = plan.blocks[position.blockIndex]
        if currentBlock.exercises.indices.contains(position.exerciseIndex) {
            let currentExercise = currentBlock.exercises[position.exerciseIndex]
            let nextSetIndex = position.setIndex + 1
            if currentExercise.sets.indices.contains(nextSetIndex) {
                return SetPosition(
                    blockIndex: position.blockIndex,
                    exerciseIndex: position.exerciseIndex,
                    setIndex: nextSetIndex
                )
            }
        }

        var blockIndex = position.blockIndex
        var exerciseIndex = position.exerciseIndex + 1

        while plan.blocks.indices.contains(blockIndex) {
            let block = plan.blocks[blockIndex]
            while block.exercises.indices.contains(exerciseIndex) {
                if !block.exercises[exerciseIndex].sets.isEmpty {
                    return SetPosition(
                        blockIndex: blockIndex,
                        exerciseIndex: exerciseIndex,
                        setIndex: 0
                    )
                }
                exerciseIndex += 1
            }

            blockIndex += 1
            exerciseIndex = 0
        }

        return nil
    }
}
