import Foundation

nonisolated enum TrainingSignalType: String, Codable, CaseIterable, Hashable {
    case consistency
    case formImprovement
    case formDropOff
    case volumeIncrease
    case volumeDrop
    case completion
    case fatigue
    case restBehavior
    case skippedExercise
    case repeatedCue
    case exerciseMastery
    case exerciseStruggle
    case planFit
    case trophyProximity
    case cameraFriction
    case qualityCapacity
    case targetFit
    case movementBalance
    case cueCluster
    case restResponse
    case progressionReadiness
    case sessionFit
    case exerciseReacquisition
    case exercisePreference
    case qualityPR
}

nonisolated enum SignalConfidence: String, Codable, CaseIterable, Hashable {
    case high
    case medium
    case low
}

nonisolated enum TrendWindow: String, Codable, CaseIterable, Hashable {
    case latestWorkout
    case threeWorkout
    case sevenWorkout
    case currentWeek
    case currentMonth
}

nonisolated enum WeeklyConsistencyStatus: String, Codable, CaseIterable, Hashable {
    case noHistory
    case gettingStarted
    case building
    case aligned
    case aboveTarget
}

nonisolated enum TrainingTrendDirection: String, Codable, CaseIterable, Hashable {
    case unavailable
    case improving
    case declining
    case steady
    case increasing
    case decreasing
    case elevated
}

nonisolated enum TrendMetric: String, Codable, CaseIterable, Hashable {
    case totalReps
    case holdSeconds
    case formScore
    case durationSeconds
    case volumeUnits
}

nonisolated struct TrendComparisonSummary: Codable, Equatable {
    let window: TrendWindow
    let metric: TrendMetric
    let latestValue: Double?
    let comparisonValue: Double?
    let delta: Double?

    static func unavailable(window: TrendWindow, metric: TrendMetric) -> TrendComparisonSummary {
        TrendComparisonSummary(
            window: window,
            metric: metric,
            latestValue: nil,
            comparisonValue: nil,
            delta: nil
        )
    }
}

nonisolated struct TrainingEvidenceRef: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let summaryId: UUID?
    let exerciseType: ExerciseType?
    let setIndex: Int?
    let repIndex: Int?
    let date: Date?
    let label: String

    init(
        id: String? = nil,
        summaryId: UUID? = nil,
        exerciseType: ExerciseType? = nil,
        setIndex: Int? = nil,
        repIndex: Int? = nil,
        date: Date? = nil,
        label: String
    ) {
        self.summaryId = summaryId
        self.exerciseType = exerciseType
        self.setIndex = setIndex
        self.repIndex = repIndex
        self.date = date
        self.label = label
        self.id = id ?? Self.makeID(
            summaryId: summaryId,
            exerciseType: exerciseType,
            setIndex: setIndex,
            repIndex: repIndex,
            date: date,
            label: label
        )
    }

    private static func makeID(
        summaryId: UUID?,
        exerciseType: ExerciseType?,
        setIndex: Int?,
        repIndex: Int?,
        date: Date?,
        label: String
    ) -> String {
        [
            summaryId?.uuidString,
            exerciseType?.rawValue,
            setIndex.map { "set-\($0)" },
            repIndex.map { "rep-\($0)" },
            date.map { "date-\(Int($0.timeIntervalSince1970))" },
            label
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }
}

nonisolated struct UserTrainingSignal: Identifiable, Codable, Equatable {
    let id: String
    let type: TrainingSignalType
    let exerciseType: ExerciseType?
    let movementPattern: MovementPattern?
    let goal: FitnessGoal?
    let title: String
    let value: String
    let comparisonValue: String?
    let delta: Double?
    let confidence: SignalConfidence
    let evidenceRefs: [TrainingEvidenceRef]
    let createdAt: Date

    init(
        id: String? = nil,
        type: TrainingSignalType,
        exerciseType: ExerciseType? = nil,
        movementPattern: MovementPattern? = nil,
        goal: FitnessGoal? = nil,
        title: String,
        value: String,
        comparisonValue: String? = nil,
        delta: Double? = nil,
        confidence: SignalConfidence,
        evidenceRefs: [TrainingEvidenceRef],
        createdAt: Date
    ) {
        self.type = type
        self.exerciseType = exerciseType
        self.movementPattern = movementPattern
        self.goal = goal
        self.title = title
        self.value = value
        self.comparisonValue = comparisonValue
        self.delta = delta
        self.confidence = confidence
        self.evidenceRefs = evidenceRefs
        self.createdAt = createdAt
        self.id = id ?? Self.makeID(
            type: type,
            exerciseType: exerciseType,
            movementPattern: movementPattern,
            goal: goal,
            title: title,
            evidenceRefs: evidenceRefs
        )
    }

    private static func makeID(
        type: TrainingSignalType,
        exerciseType: ExerciseType?,
        movementPattern: MovementPattern?,
        goal: FitnessGoal?,
        title: String,
        evidenceRefs: [TrainingEvidenceRef]
    ) -> String {
        [
            type.rawValue,
            exerciseType?.rawValue,
            movementPattern?.rawValue,
            goal?.rawValue,
            title,
            evidenceRefs.map(\.id).joined(separator: ",")
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }
}

nonisolated struct TrophyNearMiss: Identifiable, Codable, Equatable {
    let trophyId: String
    let title: String
    let currentValue: Double
    let targetValue: Double
    let remainingValue: Double
    let progressFraction: Double
    let unit: String

    var id: String { trophyId }
}

nonisolated struct ExerciseTrendSummary: Identifiable, Codable, Equatable {
    var id: ExerciseType { exerciseType }

    let exerciseType: ExerciseType
    let sessions: Int
    let totalReps: Int
    let totalHoldSeconds: Int
    let averageFormScore: Double?
    let bestFormScore: Double?
    let recentFormDelta: Double?
    let mostCommonCue: String?
    let breakdownRepIndex: Int?
    let improvementRepIndex: Int?
    let goodFormRepCount: Int
    let excellentFormRepCount: Int
    let highSeverityCueCount: Int
    let formDropOffSetCount: Int
    let skippedSetCount: Int
    let restExtendedSetCount: Int
    let cameraFrictionCueCount: Int
}

nonisolated struct UserTrainingTrendSnapshot: Codable, Equatable {
    let generatedAt: Date
    let totalWorkouts: Int
    let currentStreak: Int
    let workoutsThisWeek: Int
    let workoutDaysThisWeek: Int
    let weeklyConsistencyStatus: WeeklyConsistencyStatus
    let overallFormTrend: TrainingTrendDirection
    let volumeTrend: TrainingTrendDirection
    let fatigueTrend: TrainingTrendDirection
    let strongestExercise: ExerciseType?
    let improvingExercise: ExerciseType?
    let strugglingExercise: ExerciseType?
    let mostRepeatedCue: String?
    let trophyNearMisses: [TrophyNearMiss]
    let cameraFrictionCount: Int
    let exerciseTrends: [ExerciseTrendSummary]
}

nonisolated struct WorkoutCalendarDay: Identifiable, Codable, Equatable, Hashable {
    let date: Date
    let isInCurrentMonth: Bool
    let workoutCount: Int
    let totalReps: Int
    let totalHoldSeconds: Int
    let averageFormScore: Double?

    var id: Date { date }
    var isCompleted: Bool { workoutCount > 0 }
}

nonisolated struct WorkoutCalendarSnapshot: Codable, Equatable {
    let days: [WorkoutCalendarDay]
    let currentMonth: Date
    let completedDays: [Date]
    let streak: Int
    let timeZoneIdentifier: String
}
