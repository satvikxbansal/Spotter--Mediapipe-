import Foundation

nonisolated enum CalibrationStatus: String, Codable, Equatable {
    case notStarted
    case completed
    case skipped
    case failed

    var displayName: String {
        switch self {
        case .notStarted:
            return "Not Started"
        case .completed:
            return "Completed"
        case .skipped:
            return "Skipped"
        case .failed:
            return "Failed"
        }
    }
}

nonisolated enum CalibrationDefaults {
    static let exerciseType: ExerciseType = .squat
    static let targetReps = 3
}

nonisolated struct CalibrationRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let status: CalibrationStatus
    let exerciseType: ExerciseType
    let targetReps: Int
    let completedReps: Int
    let startedAt: Date
    let completedAt: Date
    let visibilityPassed: Bool
    let averageFormScore: Double?
    let notes: String?

    init(
        id: UUID = UUID(),
        status: CalibrationStatus,
        exerciseType: ExerciseType,
        targetReps: Int,
        completedReps: Int,
        startedAt: Date,
        completedAt: Date,
        visibilityPassed: Bool,
        averageFormScore: Double?,
        notes: String? = nil
    ) {
        self.id = id
        self.status = status
        self.exerciseType = exerciseType
        self.targetReps = max(targetReps, 0)
        self.completedReps = max(completedReps, 0)
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.visibilityPassed = visibilityPassed
        self.averageFormScore = averageFormScore.map { max(0, min($0, 100)) }
        self.notes = notes
    }

    var isSuccessfulCalibration: Bool {
        status == .completed &&
            targetReps > 0 &&
            completedReps >= targetReps &&
            visibilityPassed
    }

    static func completed(
        id: UUID = UUID(),
        exerciseType: ExerciseType = CalibrationDefaults.exerciseType,
        targetReps: Int = CalibrationDefaults.targetReps,
        completedReps: Int,
        startedAt: Date,
        completedAt: Date,
        visibilityPassed: Bool,
        averageFormScore: Double?,
        notes: String? = nil
    ) -> CalibrationRecord {
        CalibrationRecord(
            id: id,
            status: .completed,
            exerciseType: exerciseType,
            targetReps: targetReps,
            completedReps: completedReps,
            startedAt: startedAt,
            completedAt: completedAt,
            visibilityPassed: visibilityPassed,
            averageFormScore: averageFormScore,
            notes: notes
        )
    }

    static func skipped(
        at date: Date = Date(),
        exerciseType: ExerciseType = CalibrationDefaults.exerciseType,
        targetReps: Int = CalibrationDefaults.targetReps,
        notes: String? = "Skipped during setup."
    ) -> CalibrationRecord {
        CalibrationRecord(
            status: .skipped,
            exerciseType: exerciseType,
            targetReps: targetReps,
            completedReps: 0,
            startedAt: date,
            completedAt: date,
            visibilityPassed: false,
            averageFormScore: nil,
            notes: notes
        )
    }

    static func failed(
        exerciseType: ExerciseType = CalibrationDefaults.exerciseType,
        targetReps: Int = CalibrationDefaults.targetReps,
        completedReps: Int = 0,
        startedAt: Date = Date(),
        completedAt: Date = Date(),
        visibilityPassed: Bool = false,
        averageFormScore: Double? = nil,
        notes: String
    ) -> CalibrationRecord {
        CalibrationRecord(
            status: .failed,
            exerciseType: exerciseType,
            targetReps: targetReps,
            completedReps: completedReps,
            startedAt: startedAt,
            completedAt: completedAt,
            visibilityPassed: visibilityPassed,
            averageFormScore: averageFormScore,
            notes: notes
        )
    }
}
