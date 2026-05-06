import Foundation

nonisolated struct PlannedWorkoutCoordinator {
    let plan: WorkoutPlanV2
    let startedAt: Date

    private(set) var currentBlockIndex: Int
    private(set) var currentExerciseIndex: Int
    private(set) var currentSetIndex: Int
    private(set) var completedSetSummaries: [PlannedWorkoutSetSummary]
    private(set) var restOutcomes: [UUID: PlannedWorkoutRestResult]
    private(set) var sessionState: WorkoutSessionState
    private(set) var completedAt: Date?

    init(plan: WorkoutPlanV2, startedAt: Date = Date()) {
        self.plan = plan
        self.startedAt = startedAt
        self.completedSetSummaries = []
        self.restOutcomes = [:]
        self.completedAt = nil

        if let firstPosition = Self.firstSetPosition(in: plan) {
            self.currentBlockIndex = firstPosition.blockIndex
            self.currentExerciseIndex = firstPosition.exerciseIndex
            self.currentSetIndex = firstPosition.setIndex
            self.sessionState = .ready
        } else {
            self.currentBlockIndex = 0
            self.currentExerciseIndex = 0
            self.currentSetIndex = 0
            self.sessionState = .completed
            self.completedAt = startedAt
        }
    }

    var isAwaitingContinue: Bool {
        sessionState == .rest
    }

    var isSessionComplete: Bool {
        sessionState == .completed
    }

    var currentTarget: WorkoutTarget? {
        currentSet?.target
    }

    var currentContext: WorkoutSessionContext? {
        guard sessionState == .ready || sessionState == .activeSet,
              let position = currentPosition
        else { return nil }

        return context(for: position)
    }

    var restContext: PlannedWorkoutRestContext? {
        guard sessionState == .rest,
              let summary = completedSetSummaries.last,
              let position = currentPosition,
              let nextPosition = Self.nextSetPosition(after: position, in: plan),
              let upNextContext = context(for: nextPosition)
        else { return nil }

        return PlannedWorkoutRestContext(
            lastSummary: summary,
            upNextContext: upNextContext,
            restSeconds: max(currentExercise?.restSeconds ?? 0, 0)
        )
    }

    var hasNextSet: Bool {
        guard let position = currentPosition else { return false }
        return Self.nextSetPosition(after: position, in: plan) != nil
    }

    mutating func startSession() {
        guard sessionState == .ready else { return }
        sessionState = .activeSet
    }

    @discardableResult
    mutating func completeCurrentSet(with summary: PlannedWorkoutSetSummary) -> Bool {
        guard sessionState == .activeSet,
              summary.planId == plan.id,
              let currentExercise,
              let currentTarget,
              summary.exerciseType == currentExercise.exerciseType,
              summary.target == currentTarget,
              summary.exerciseIndex == currentGlobalExerciseIndex,
              summary.setIndex == currentSetIndex,
              summary.totalSets == currentExercise.sets.count,
              summary.totalExercises == totalExercises
        else { return false }

        completedSetSummaries.append(summary)
        if hasNextSet {
            sessionState = .rest
        } else {
            sessionState = .completed
            completedAt = summary.completedAt
        }
        return true
    }

    mutating func continueToNextSet() {
        guard sessionState == .rest,
              let position = currentPosition
        else { return }

        if let nextPosition = Self.nextSetPosition(after: position, in: plan) {
            currentBlockIndex = nextPosition.blockIndex
            currentExerciseIndex = nextPosition.exerciseIndex
            currentSetIndex = nextPosition.setIndex
            sessionState = .activeSet
        } else {
            sessionState = .completed
            completedAt = completedSetSummaries.last?.completedAt ?? Date()
        }
    }

    mutating func recordRestOutcome(_ result: PlannedWorkoutRestResult) {
        guard sessionState == .rest,
              let summary = completedSetSummaries.last
        else { return }

        restOutcomes[summary.id] = result
    }

    mutating func cancelSession(at date: Date = Date()) {
        guard sessionState != .completed else { return }
        sessionState = .cancelled
        completedAt = date
    }

    func workoutSummary(completedAt fallbackCompletedAt: Date = Date()) -> WorkoutSummary {
        WorkoutSummaryBuilder.build(
            plan: plan,
            startedAt: startedAt,
            completedSets: completedSetSummaries,
            completedAt: completedAt ?? fallbackCompletedAt
        )
    }

    func workoutSessionSummary(completedAt fallbackCompletedAt: Date = Date()) -> WorkoutSessionSummary {
        WorkoutSessionSummary.plannedWorkout(
            plan: plan,
            startedAt: startedAt,
            completedSets: completedSetSummaries,
            restOutcomes: restOutcomes,
            completedAt: completedAt ?? fallbackCompletedAt
        )
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
        guard sessionState != .completed,
              sessionState != .cancelled,
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

    func context(for position: SetPosition) -> WorkoutSessionContext? {
        guard let exercise = exercise(at: position),
              let set = set(at: position, in: exercise)
        else { return nil }

        return WorkoutSessionContext(
            planId: plan.id,
            planTitle: plan.title,
            exerciseType: exercise.exerciseType,
            target: set.target,
            setIndex: position.setIndex,
            totalSets: exercise.sets.count,
            exerciseIndex: globalExerciseIndex(
                blockIndex: position.blockIndex,
                exerciseIndex: position.exerciseIndex
            ),
            totalExercises: totalExercises,
            coach: plan.coach,
            startsActive: false
        )
    }

    func exercise(at position: SetPosition) -> PlannedExercise? {
        guard plan.blocks.indices.contains(position.blockIndex) else { return nil }
        let block = plan.blocks[position.blockIndex]
        guard block.exercises.indices.contains(position.exerciseIndex) else { return nil }
        return block.exercises[position.exerciseIndex]
    }

    func set(at position: SetPosition, in exercise: PlannedExercise) -> PlannedSet? {
        guard exercise.sets.indices.contains(position.setIndex) else { return nil }
        return exercise.sets[position.setIndex]
    }

    func globalExerciseIndex(blockIndex: Int, exerciseIndex: Int) -> Int {
        guard plan.blocks.indices.contains(blockIndex) else { return 0 }

        let exercisesBeforeBlock = plan.blocks
            .prefix(blockIndex)
            .reduce(0) { $0 + $1.exercises.count }

        return exercisesBeforeBlock + exerciseIndex
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
