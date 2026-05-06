import Foundation

nonisolated enum SessionMode: String, Equatable {
    case freeAnalysis
    case plannedWorkout
    case calibration
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

    var isCalibration: Bool {
        mode == .calibration
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

    static func calibration(
        exerciseType: ExerciseType = CalibrationDefaults.exerciseType,
        targetReps: Int = CalibrationDefaults.targetReps,
        coach: CoachPersonality = .good,
        startsActive: Bool = false
    ) -> LiveSessionContext {
        LiveSessionContext(
            mode: .calibration,
            exerciseType: exerciseType,
            target: .reps(targetReps),
            title: "Calibration",
            coach: coach,
            startsActive: startsActive
        )
    }

    static func plannedWorkout(
        workout: WorkoutPlan,
        setIndex: Int = 0,
        coach: CoachPersonality = .good
    ) -> LiveSessionContext {
        guard !workout.exercises.isEmpty else {
            return LiveSessionContext(
                mode: .plannedWorkout,
                exerciseType: .squat,
                target: .open,
                setIndex: nil,
                totalSets: 0,
                planId: workout.id,
                title: workout.title,
                coach: coach
            )
        }

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

    static func plannedWorkout(
        plan: WorkoutPlanV2,
        exerciseIndex: Int = 0,
        setIndex: Int = 0,
        coach: CoachPersonality? = nil,
        startsActive: Bool = false
    ) -> LiveSessionContext? {
        let exercises = plan.blocks.flatMap(\.exercises)
        guard !exercises.isEmpty else { return nil }

        let safeExerciseIndex = exercises.indices.contains(exerciseIndex) ? exerciseIndex : 0
        let exercise = exercises[safeExerciseIndex]
        let safeSetIndex = exercise.sets.indices.contains(setIndex) ? setIndex : 0
        let plannedSet = exercise.sets.isEmpty ? nil : exercise.sets[safeSetIndex]

        return LiveSessionContext(
            mode: .plannedWorkout,
            exerciseType: exercise.exerciseType,
            target: plannedSet.map { SessionTarget(workoutTarget: $0.target) } ?? .open,
            setIndex: plannedSet.map { _ in safeSetIndex },
            totalSets: exercise.sets.isEmpty ? nil : exercise.sets.count,
            planId: plan.id,
            title: plan.title,
            coach: coach ?? plan.coach,
            startsActive: startsActive
        )
    }
}

nonisolated private extension SessionTarget {
    init(workoutTarget: WorkoutTarget) {
        switch workoutTarget {
        case .reps(let reps):
            self = .reps(reps)
        case .hold(let seconds), .timed(let seconds):
            self = .seconds(seconds)
        case .amrap(let seconds):
            if let seconds {
                self = .seconds(seconds)
            } else {
                self = .open
            }
        case .open:
            self = .open
        }
    }
}

nonisolated struct FreeAnalysisSummary: Identifiable {
    let id: UUID
    let exerciseType: ExerciseType
    let coach: CoachPersonality
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let reps: Int
    let holdDuration: TimeInterval
    let latestFormScore: FormScore?
    let peakEffort: Double
    let lastCue: CoachCue?
    let cueEvents: [CueEvent]
    let repQualityEvents: [RepQualityEvent]
    let qualitySummary: SetQualitySummary?

    init(
        id: UUID = UUID(),
        exerciseType: ExerciseType,
        coach: CoachPersonality,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        reps: Int,
        holdDuration: TimeInterval,
        latestFormScore: FormScore?,
        peakEffort: Double,
        lastCue: CoachCue?,
        cueEvents: [CueEvent] = [],
        repQualityEvents: [RepQualityEvent] = [],
        qualitySummary: SetQualitySummary? = nil
    ) {
        self.id = id
        self.exerciseType = exerciseType
        self.coach = coach
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = max(duration, 0)
        self.reps = max(reps, 0)
        self.holdDuration = max(holdDuration, 0)
        self.latestFormScore = latestFormScore
        self.peakEffort = max(0, min(peakEffort, 1))
        self.lastCue = lastCue
        self.cueEvents = cueEvents
        self.repQualityEvents = repQualityEvents
        self.qualitySummary = qualitySummary
    }

    var durationText: String {
        let seconds = max(Int(duration), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
