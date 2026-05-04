import Foundation

nonisolated enum SessionMode: String, Equatable {
    case freeAnalysis
    case plannedWorkout
}

nonisolated enum SessionTarget: Equatable {
    case open
    case reps(Int)
    case seconds(Int)
}

nonisolated struct LiveSessionContext: Identifiable, Equatable {
    let id: UUID
    let mode: SessionMode
    let exerciseType: ExerciseType
    let target: SessionTarget?
    let setIndex: Int?
    let totalSets: Int?
    let planId: UUID?
    let title: String
    let coach: CoachPersonality
    let startsActive: Bool

    var isFreeAnalysis: Bool {
        mode == .freeAnalysis
    }

    init(
        id: UUID = UUID(),
        mode: SessionMode,
        exerciseType: ExerciseType,
        target: SessionTarget?,
        setIndex: Int? = nil,
        totalSets: Int? = nil,
        planId: UUID? = nil,
        title: String? = nil,
        coach: CoachPersonality = .good,
        startsActive: Bool = false
    ) {
        self.id = id
        self.mode = mode
        self.exerciseType = exerciseType
        self.target = target
        self.setIndex = setIndex
        self.totalSets = totalSets
        self.planId = planId
        self.title = title ?? exerciseType.displayName
        self.coach = coach
        self.startsActive = startsActive
    }

    static func freeAnalysis(
        exerciseType: ExerciseType,
        coach: CoachPersonality = .good,
        startsActive: Bool = false
    ) -> LiveSessionContext {
        LiveSessionContext(
            mode: .freeAnalysis,
            exerciseType: exerciseType,
            target: .open,
            title: exerciseType.displayName,
            coach: coach,
            startsActive: startsActive
        )
    }

    static func plannedWorkout(
        workout: WorkoutPlan,
        setIndex: Int = 0,
        coach: CoachPersonality = .good
    ) -> LiveSessionContext {
        let safeIndex = workout.exercises.indices.contains(setIndex) ? setIndex : 0
        let set = workout.exercises[safeIndex]
        let definition = set.exerciseType.definition
        let target: SessionTarget = definition?.movementType == .isometric
            ? .seconds(set.targetReps)
            : .reps(set.targetReps)

        return LiveSessionContext(
            mode: .plannedWorkout,
            exerciseType: set.exerciseType,
            target: target,
            setIndex: safeIndex,
            totalSets: workout.exercises.count,
            planId: workout.id,
            title: workout.title,
            coach: coach
        )
    }
}

nonisolated struct FreeAnalysisSummary: Identifiable {
    let id = UUID()
    let exerciseType: ExerciseType
    let duration: TimeInterval
    let reps: Int
    let latestFormScore: FormScore?
    let peakEffort: Double
    let lastCue: CoachCue?

    var durationText: String {
        let seconds = max(Int(duration), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
