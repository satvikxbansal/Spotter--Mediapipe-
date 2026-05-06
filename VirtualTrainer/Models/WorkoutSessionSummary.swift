import Foundation

nonisolated enum WorkoutSessionSummaryMode: String, Codable, Equatable {
    case freeAnalysis
    case plannedWorkout

    var displayName: String {
        switch self {
        case .freeAnalysis:
            return "Free Analysis"
        case .plannedWorkout:
            return "Planned Workout"
        }
    }
}

nonisolated struct CueEvent: Codable, Equatable {
    let timestamp: Date
    let exerciseType: ExerciseType
    let cueMessage: String
    let severity: CoachCue.Severity
    let metricKey: String?

    init(
        timestamp: Date,
        exerciseType: ExerciseType,
        cueMessage: String,
        severity: CoachCue.Severity,
        metricKey: String? = nil
    ) {
        self.timestamp = timestamp
        self.exerciseType = exerciseType
        self.cueMessage = cueMessage
        self.severity = severity
        self.metricKey = metricKey
    }
}

nonisolated struct ExerciseSetSummary: Codable, Equatable {
    let exerciseType: ExerciseType
    let setIndex: Int?
    let target: WorkoutTarget?
    let achievedReps: Int
    let achievedHoldSeconds: Int
    let averageFormScore: Double?
    let cueEvents: [CueEvent]
    let restExtended: Bool
    let skipped: Bool

    init(
        exerciseType: ExerciseType,
        setIndex: Int? = nil,
        target: WorkoutTarget? = nil,
        achievedReps: Int,
        achievedHoldSeconds: Int,
        averageFormScore: Double?,
        cueEvents: [CueEvent] = [],
        restExtended: Bool = false,
        skipped: Bool = false
    ) {
        self.exerciseType = exerciseType
        self.setIndex = setIndex
        self.target = target
        self.achievedReps = achievedReps
        self.achievedHoldSeconds = achievedHoldSeconds
        self.averageFormScore = averageFormScore
        self.cueEvents = cueEvents
        self.restExtended = restExtended
        self.skipped = skipped
    }
}

nonisolated struct WorkoutSessionSummary: Identifiable, Codable, Equatable {
    let id: UUID
    let mode: WorkoutSessionSummaryMode
    let planId: UUID?
    let title: String
    let goal: String?
    let coach: CoachPersonality
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let totalReps: Int
    let totalHoldSeconds: Int
    let averageFormScore: Double?
    let completionPercent: Double?
    let exerciseSummaries: [ExerciseSetSummary]
    let topCue: CueEvent?
    let effortSummary: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        mode: WorkoutSessionSummaryMode,
        planId: UUID? = nil,
        title: String,
        goal: String? = nil,
        coach: CoachPersonality,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        totalReps: Int,
        totalHoldSeconds: Int,
        averageFormScore: Double?,
        completionPercent: Double? = nil,
        exerciseSummaries: [ExerciseSetSummary],
        topCue: CueEvent?,
        effortSummary: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.mode = mode
        self.planId = planId
        self.title = title
        self.goal = goal
        self.coach = coach
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = max(durationSeconds, 0)
        self.totalReps = max(totalReps, 0)
        self.totalHoldSeconds = max(totalHoldSeconds, 0)
        self.averageFormScore = averageFormScore
        self.completionPercent = completionPercent
        self.exerciseSummaries = exerciseSummaries
        self.topCue = topCue
        self.effortSummary = effortSummary
        self.createdAt = createdAt
    }

    var primaryExerciseType: ExerciseType? {
        exerciseSummaries.first?.exerciseType
    }
}

nonisolated extension WorkoutSessionSummary {
    static func freeAnalysis(
        from summary: FreeAnalysisSummary,
        createdAt: Date = Date()
    ) -> WorkoutSessionSummary {
        let exerciseSummary = ExerciseSetSummary(
            exerciseType: summary.exerciseType,
            achievedReps: summary.reps,
            achievedHoldSeconds: Int(summary.holdDuration.rounded()),
            averageFormScore: summary.latestFormScore.map { Double($0.score) },
            cueEvents: summary.cueEvents
        )

        return WorkoutSessionSummary(
            id: summary.id,
            mode: .freeAnalysis,
            title: summary.exerciseType.displayName,
            coach: summary.coach,
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            durationSeconds: Int(summary.duration.rounded()),
            totalReps: summary.reps,
            totalHoldSeconds: Int(summary.holdDuration.rounded()),
            averageFormScore: summary.latestFormScore.map { Double($0.score) },
            exerciseSummaries: [exerciseSummary],
            topCue: topCue(from: summary.cueEvents),
            effortSummary: effortSummary(peakEffort: summary.peakEffort),
            createdAt: createdAt
        )
    }

    static func plannedWorkout(
        plan: WorkoutPlanV2,
        startedAt: Date,
        completedSets: [PlannedWorkoutSetSummary],
        restOutcomes: [UUID: PlannedWorkoutRestResult] = [:],
        completedAt fallbackCompletedAt: Date = Date(),
        createdAt: Date = Date()
    ) -> WorkoutSessionSummary {
        let plannedSetCount = plan.blocks
            .flatMap(\.exercises)
            .reduce(0) { $0 + $1.sets.count }

        let endedAt = completedSets.map(\.completedAt).max() ?? fallbackCompletedAt
        let activeDuration = completedSets.reduce(0) { $0 + max($1.duration, 0) }
        let wallDuration = max(endedAt.timeIntervalSince(startedAt), 0)
        let durationSeconds = Int(max(wallDuration, activeDuration).rounded())

        let exerciseSummaries = completedSets.map { setSummary in
            let cueEvents = normalizedCueEvents(from: setSummary)
            let restOutcome = restOutcomes[setSummary.id]
            return ExerciseSetSummary(
                exerciseType: setSummary.exerciseType,
                setIndex: setSummary.setIndex,
                target: setSummary.target,
                achievedReps: setSummary.reps,
                achievedHoldSeconds: Int(setSummary.holdDuration.rounded()),
                averageFormScore: setSummary.latestFormScore.map { Double($0.score) },
                cueEvents: cueEvents,
                restExtended: restOutcome?.restExtended ?? false,
                skipped: restOutcome?.skipped ?? false
            )
        }

        let formScores = completedSets.compactMap { $0.latestFormScore?.score }
        let allCueEvents = exerciseSummaries.flatMap(\.cueEvents)
        let completionPercent = plannedSetCount > 0
            ? min(Double(completedSets.count) / Double(plannedSetCount), 1.0)
            : nil

        return WorkoutSessionSummary(
            mode: .plannedWorkout,
            planId: plan.id,
            title: plan.title,
            goal: plan.goal,
            coach: plan.coach,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            totalReps: completedSets.reduce(0) { $0 + max($1.reps, 0) },
            totalHoldSeconds: Int(completedSets.reduce(0) { $0 + max($1.holdDuration, 0) }.rounded()),
            averageFormScore: averageScore(from: formScores),
            completionPercent: completionPercent,
            exerciseSummaries: exerciseSummaries,
            topCue: topCue(from: allCueEvents),
            effortSummary: effortSummary(
                peakEffort: completedSets.map(\.peakEffort).max() ?? 0
            ),
            createdAt: createdAt
        )
    }
}

nonisolated private extension WorkoutSessionSummary {
    static func normalizedCueEvents(
        from setSummary: PlannedWorkoutSetSummary
    ) -> [CueEvent] {
        if !setSummary.cueEvents.isEmpty {
            return setSummary.cueEvents
        }

        var uniqueCues: [CoachCue] = []
        for cue in [setSummary.worstCue, setSummary.lastCue, setSummary.bestCue].compactMap({ $0 }) {
            guard !uniqueCues.contains(where: {
                $0.message == cue.message && $0.severity == cue.severity
            }) else { continue }
            uniqueCues.append(cue)
        }

        return uniqueCues.map { cue in
            CueEvent(
                timestamp: setSummary.completedAt,
                exerciseType: setSummary.exerciseType,
                cueMessage: cue.message,
                severity: cue.severity
            )
        }
    }

    static func averageScore(from scores: [Int]) -> Double? {
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    static func topCue(from events: [CueEvent]) -> CueEvent? {
        events.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return lhs.timestamp < rhs.timestamp
        }.first
    }

    static func effortSummary(peakEffort: Double) -> String {
        let percent = Int((max(0, min(peakEffort, 1)) * 100).rounded())
        switch peakEffort {
        case 0.75...:
            return "Peak effort hit \(percent)%. High strain captured near the end."
        case 0.45..<0.75:
            return "Peak effort reached \(percent)%. Solid working intensity."
        case 0.01..<0.45:
            return "Peak effort stayed around \(percent)%. Controlled session."
        default:
            return "No face-effort signal was captured for this session."
        }
    }
}
