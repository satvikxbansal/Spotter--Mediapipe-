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
    let accountId: String?
    let status: CalibrationStatus
    let exerciseType: ExerciseType
    let targetReps: Int
    let completedReps: Int
    let startedAt: Date
    let completedAt: Date
    let serverCompletedAt: Date?
    let visibilityPassed: Bool
    let averageFormScore: Double?
    let notes: String?
    let deletedAt: Date?
    var syncMetadata: SyncMetadata

    init(
        id: UUID = UUID(),
        accountId: String? = nil,
        status: CalibrationStatus,
        exerciseType: ExerciseType,
        targetReps: Int,
        completedReps: Int,
        startedAt: Date,
        completedAt: Date,
        serverCompletedAt: Date? = nil,
        visibilityPassed: Bool,
        averageFormScore: Double?,
        notes: String? = nil,
        deletedAt: Date? = nil,
        syncMetadata: SyncMetadata? = nil
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.id = id
        self.accountId = normalizedAccountId
        self.status = status
        self.exerciseType = exerciseType
        self.targetReps = max(targetReps, 0)
        self.completedReps = max(completedReps, 0)
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.serverCompletedAt = serverCompletedAt
        self.visibilityPassed = visibilityPassed
        self.averageFormScore = averageFormScore.map { max(0, min($0, 100)) }
        self.notes = notes
        self.deletedAt = deletedAt
        self.syncMetadata = syncMetadata ?? (
            normalizedAccountId == nil
                ? .initialLocalOnly(now: completedAt)
                : .initialPendingUpload(operationId: nil, now: completedAt)
        )
    }

    var isSuccessfulCalibration: Bool {
        !isDeleted &&
            status == .completed &&
            targetReps > 0 &&
            completedReps >= targetReps &&
            visibilityPassed
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    var authoritativeCompletedAt: Date {
        serverCompletedAt ?? completedAt
    }

    func markedDeleted(at date: Date, operationId: UUID? = nil) -> CalibrationRecord {
        copy(
            accountId: accountId,
            deletedAt: date,
            syncMetadata: syncMetadata.markedForLocalMutation(
                accountId: accountId,
                operationId: operationId,
                now: date
            )
        )
    }

    func restored(operationId: UUID? = nil) -> CalibrationRecord {
        copy(
            accountId: accountId,
            deletedAt: nil,
            syncMetadata: syncMetadata.markedForLocalMutation(
                accountId: accountId,
                operationId: operationId
            )
        )
    }

    func withAccountId(
        _ accountId: String?,
        operationId: UUID? = nil,
        now: Date = Date()
    ) -> CalibrationRecord {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        return copy(
            accountId: normalizedAccountId,
            deletedAt: deletedAt,
            syncMetadata: syncMetadata.markedForLocalMutation(
                accountId: normalizedAccountId,
                operationId: operationId,
                now: now
            )
        )
    }

    static func completed(
        id: UUID = UUID(),
        accountId: String? = nil,
        exerciseType: ExerciseType = CalibrationDefaults.exerciseType,
        targetReps: Int = CalibrationDefaults.targetReps,
        completedReps: Int,
        startedAt: Date,
        completedAt: Date,
        serverCompletedAt: Date? = nil,
        visibilityPassed: Bool,
        averageFormScore: Double?,
        notes: String? = nil
    ) -> CalibrationRecord {
        CalibrationRecord(
            id: id,
            accountId: accountId,
            status: .completed,
            exerciseType: exerciseType,
            targetReps: targetReps,
            completedReps: completedReps,
            startedAt: startedAt,
            completedAt: completedAt,
            serverCompletedAt: serverCompletedAt,
            visibilityPassed: visibilityPassed,
            averageFormScore: averageFormScore,
            notes: notes
        )
    }

    static func skipped(
        at date: Date = Date(),
        accountId: String? = nil,
        exerciseType: ExerciseType = CalibrationDefaults.exerciseType,
        targetReps: Int = CalibrationDefaults.targetReps,
        notes: String? = "Skipped during setup."
    ) -> CalibrationRecord {
        CalibrationRecord(
            accountId: accountId,
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
        accountId: String? = nil,
        targetReps: Int = CalibrationDefaults.targetReps,
        completedReps: Int = 0,
        startedAt: Date = Date(),
        completedAt: Date = Date(),
        visibilityPassed: Bool = false,
        averageFormScore: Double? = nil,
        notes: String
    ) -> CalibrationRecord {
        CalibrationRecord(
            accountId: accountId,
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

nonisolated private extension CalibrationRecord {
    func copy(
        accountId: String?,
        deletedAt: Date?,
        syncMetadata: SyncMetadata
    ) -> CalibrationRecord {
        CalibrationRecord(
            id: id,
            accountId: accountId,
            status: status,
            exerciseType: exerciseType,
            targetReps: targetReps,
            completedReps: completedReps,
            startedAt: startedAt,
            completedAt: completedAt,
            serverCompletedAt: serverCompletedAt,
            visibilityPassed: visibilityPassed,
            averageFormScore: averageFormScore,
            notes: notes,
            deletedAt: deletedAt,
            syncMetadata: syncMetadata
        )
    }
}

nonisolated extension CalibrationRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case status
        case exerciseType
        case targetReps
        case completedReps
        case startedAt
        case completedAt
        case serverCompletedAt
        case visibilityPassed
        case averageFormScore
        case notes
        case deletedAt
        case syncMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let completedAt = try container.decode(Date.self, forKey: .completedAt)

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            accountId: try container.decodeIfPresent(String.self, forKey: .accountId),
            status: try container.decode(CalibrationStatus.self, forKey: .status),
            exerciseType: try container.decode(ExerciseType.self, forKey: .exerciseType),
            targetReps: try container.decode(Int.self, forKey: .targetReps),
            completedReps: try container.decode(Int.self, forKey: .completedReps),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            completedAt: completedAt,
            serverCompletedAt: try container.decodeIfPresent(Date.self, forKey: .serverCompletedAt),
            visibilityPassed: try container.decode(Bool.self, forKey: .visibilityPassed),
            averageFormScore: try container.decodeIfPresent(Double.self, forKey: .averageFormScore),
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            syncMetadata: try container.decodeIfPresent(SyncMetadata.self, forKey: .syncMetadata)
                ?? .initialLocalOnly(now: completedAt)
        )
    }
}
