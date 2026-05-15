import Foundation

nonisolated enum WorkoutSessionState: String, Equatable {
    case ready
    case activeSet
    case rest
    case completed
    case cancelled
}

nonisolated struct WorkoutSessionContext: Identifiable, Equatable {
    let mode: SessionMode = .plannedWorkout
    let planId: UUID
    let planTitle: String
    let exerciseType: ExerciseType
    let target: WorkoutTarget
    let setIndex: Int
    let totalSets: Int
    let exerciseIndex: Int
    let totalExercises: Int
    let coach: CoachPersonality
    let startsActive: Bool

    var id: String {
        "\(planId.uuidString)-exercise-\(exerciseIndex)-set-\(setIndex)"
    }

    var targetText: String {
        target.formattedText
    }

    var liveSessionContext: LiveSessionContext {
        LiveSessionContext(
            mode: mode,
            exerciseType: exerciseType,
            target: sessionTarget,
            setIndex: setIndex,
            totalSets: totalSets,
            planId: planId,
            title: planTitle,
            coach: coach,
            startsActive: startsActive
        )
    }

    private var sessionTarget: SessionTarget {
        switch target {
        case .reps(let count):
            return .reps(count)
        case .hold(let seconds), .timed(let seconds):
            return .seconds(seconds)
        case .amrap(let seconds):
            guard let seconds else { return .open }
            return .seconds(seconds)
        case .open:
            return .open
        }
    }
}

@MainActor
extension WorkoutSessionContext {
    static var isLive: Bool {
        WorkoutSessionLiveState.shared.isLive
    }

    static func markLiveStarted() {
        WorkoutSessionLiveState.shared.markStarted()
    }

    static func markLiveEnded() {
        WorkoutSessionLiveState.shared.markEnded()
    }

    static func onWorkoutEnded(_ action: @escaping @MainActor () -> Void) {
        WorkoutSessionLiveState.shared.onEnded(action)
    }
}

@MainActor
private final class WorkoutSessionLiveState {
    static let shared = WorkoutSessionLiveState()

    private(set) var isLive = false
    private var onEndedActions: [@MainActor () -> Void] = []

    func markStarted() {
        isLive = true
    }

    func markEnded() {
        guard isLive else { return }
        isLive = false
        let actions = onEndedActions
        onEndedActions.removeAll()
        actions.forEach { $0() }
    }

    func onEnded(_ action: @escaping @MainActor () -> Void) {
        guard isLive else {
            action()
            return
        }
        onEndedActions.append(action)
    }
}

nonisolated struct PlannedWorkoutRestContext: Identifiable {
    let lastSummary: PlannedWorkoutSetSummary
    let upNextContext: WorkoutSessionContext
    let restSeconds: Int

    var id: String {
        "\(lastSummary.id.uuidString)-rest-\(upNextContext.id)"
    }
}

nonisolated struct PlannedWorkoutRestResult: Equatable {
    let restExtended: Bool
    let skipped: Bool

    init(restExtended: Bool = false, skipped: Bool = false) {
        self.restExtended = restExtended
        self.skipped = skipped
    }
}

nonisolated enum PlannedSetCompletionSource: String, Codable, Equatable {
    case targetMet
    case manual
}

nonisolated struct PlannedWorkoutSetSummary: Identifiable {
    let id: UUID
    let planId: UUID
    let exerciseType: ExerciseType
    let target: WorkoutTarget
    let setIndex: Int
    let totalSets: Int
    let exerciseIndex: Int
    let totalExercises: Int
    let completedAt: Date
    let duration: TimeInterval
    let reps: Int
    let holdDuration: TimeInterval
    let latestFormScore: FormScore?
    let peakEffort: Double
    let lastCue: CoachCue?
    let bestCue: CoachCue?
    let worstCue: CoachCue?
    let cueEvents: [CueEvent]
    let completionSource: PlannedSetCompletionSource
    let repQualityEvents: [RepQualityEvent]
    let qualitySummary: SetQualitySummary?

    init(
        id: UUID = UUID(),
        planId: UUID,
        exerciseType: ExerciseType,
        target: WorkoutTarget,
        setIndex: Int,
        totalSets: Int,
        exerciseIndex: Int,
        totalExercises: Int,
        completedAt: Date = Date(),
        duration: TimeInterval,
        reps: Int,
        holdDuration: TimeInterval,
        latestFormScore: FormScore?,
        peakEffort: Double,
        lastCue: CoachCue?,
        bestCue: CoachCue? = nil,
        worstCue: CoachCue? = nil,
        cueEvents: [CueEvent] = [],
        completionSource: PlannedSetCompletionSource,
        repQualityEvents: [RepQualityEvent] = [],
        qualitySummary: SetQualitySummary? = nil
    ) {
        self.id = id
        self.planId = planId
        self.exerciseType = exerciseType
        self.target = target
        self.setIndex = setIndex
        self.totalSets = totalSets
        self.exerciseIndex = exerciseIndex
        self.totalExercises = totalExercises
        self.completedAt = completedAt
        self.duration = duration
        self.reps = reps
        self.holdDuration = holdDuration
        self.latestFormScore = latestFormScore
        self.peakEffort = peakEffort
        self.lastCue = lastCue
        self.bestCue = bestCue
        self.worstCue = worstCue
        self.cueEvents = cueEvents
        self.completionSource = completionSource
        self.repQualityEvents = repQualityEvents
        self.qualitySummary = qualitySummary
    }
}
