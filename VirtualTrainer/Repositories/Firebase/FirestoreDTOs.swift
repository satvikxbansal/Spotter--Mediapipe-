import Foundation

nonisolated enum FirestoreDTOSchema {
    static let currentVersion = 1
}

nonisolated struct FirestoreSyncMetadataFields: Codable, Equatable {
    let localUpdatedAt: Date
    let lastSyncedAt: Date?
    let serverVersion: String?
    let syncState: String
    let pendingOperationId: String?
}

nonisolated struct FirestoreWorkoutTargetDTO: Codable, Equatable {
    let kind: String
    let value: Int?
}

nonisolated struct FirestoreCueEventDTO: Codable, Equatable {
    let id: String
    let timestamp: Date
    let exerciseType: String
    let cueMessage: String
    let severity: String
    let setIndex: Int?
    let repIndex: Int?
    let secondsIntoSet: TimeInterval?
    let formScoreAtEvent: Int?
    let metricKey: String?
    let metricValue: Double?
}

nonisolated struct FirestoreRepQualityEventDTO: Codable, Equatable {
    let id: String
    let exerciseType: String
    let setIndex: Int?
    let repIndex: Int
    let timestamp: Date
    let secondsIntoSet: TimeInterval
    let formScore: Int?
    let formGrade: String?
    let phase: String?
    let cueMessageNearRep: String?
    let cueSeverityNearRep: String?
    let effortAtRep: Double?
}

nonisolated struct FirestoreSetQualitySummaryDTO: Codable, Equatable {
    let totalScoredReps: Int
    let goodFormReps: Int
    let excellentFormReps: Int
    let minFormScore: Double?
    let maxFormScore: Double?
    let averageFormScore: Double?
    let firstHalfAverageFormScore: Double?
    let secondHalfAverageFormScore: Double?
    let breakdownRepIndex: Int?
    let improvementRepIndex: Int?
    let highSeverityCueCount: Int
    let mostRepeatedCue: String?
    let qualityTrend: String
}

nonisolated struct FirestoreStructuredEffortSummaryDTO: Codable, Equatable {
    let averageEffort: Double?
    let peakEffort: Double?
    let trend: String
    let source: String
}

nonisolated struct FirestoreInsightEvidenceDTO: Codable, Equatable {
    let id: String
    let metric: String
    let value: String
    let comparison: String?
    let workoutId: String?
    let exerciseType: String?
    let setIndex: Int?
    let repIndex: Int?
    let signalId: String?
    let confidence: Double
}

nonisolated struct FirestoreTrophyProgressDTO: Codable, Equatable {
    let trophyId: String
    let currentValue: Double
    let targetValue: Double
    let earned: Bool
    let earnedAt: Date?
    let lastUpdatedAt: Date
    let confidence: String
    let progressLabel: String
    let accountId: String
    let syncMetadata: FirestoreSyncMetadataFields?
}

nonisolated struct FirestorePlannedSetDTO: Codable, Equatable {
    let setIndex: Int
    let target: FirestoreWorkoutTargetDTO
}

nonisolated struct FirestorePlannedExerciseDTO: Codable, Equatable {
    let exerciseType: String
    let sets: [FirestorePlannedSetDTO]
    let restSeconds: Int
    let coachingFocus: String
    let cameraPosition: String
    let allowSwap: Bool
}

nonisolated struct FirestoreWorkoutBlockDTO: Codable, Equatable {
    let title: String
    let type: String
    let exercises: [FirestorePlannedExerciseDTO]
}

nonisolated struct FirestoreProfileDocument: Codable, Equatable {
    let schemaVersion: Int
    let accountId: String
    let profileId: String
    let displayName: String?
    let genderIdentity: String
    let age: Int
    let height: Double
    let heightUnit: String
    let weight: Double
    let weightUnit: String
    let primaryGoal: String
    let fitnessLevel: String
    let equipment: [String]
    let preferredCoach: String
    let selectedTheme: String
    let limitations: [String]
    let preferredSessionLength: Int
    let workoutDaysPerWeek: Int?
    let reminderPreference: String
    let timezoneIdentifier: String
    let avatarStyle: String?
    let onboardingSchemaVersion: Int
    let profileSchemaVersion: Int
    let onboardingCompletedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let serverUpdatedAt: Date?
    let deletedAt: Date?
    let syncMetadata: FirestoreSyncMetadataFields?
    let operationId: UUID
}

nonisolated struct FirestoreWorkoutDocument: Codable, Equatable {
    let schemaVersion: Int
    let accountId: String
    let workoutId: String
    let summarySchemaVersion: Int
    let appBuildVersion: String?
    let mode: String
    let planId: String?
    let planTitle: String?
    let title: String
    let goal: String?
    let coach: String
    let startedAt: Date
    let endedAt: Date
    let serverEndedAt: Date?
    let durationSeconds: Int
    let totalReps: Int
    let totalHoldSeconds: Int
    let averageFormScore: Double?
    let completionPercent: Double?
    let setCount: Int
    let repQualityEventCount: Int
    let cueEventCount: Int
    let topCue: FirestoreCueEventDTO?
    let effortSummary: String
    let workoutOutcome: String
    let structuredEffortSummary: FirestoreStructuredEffortSummaryDTO?
    let totalGoodFormReps: Int
    let totalExcellentFormReps: Int
    let totalHighSeverityCues: Int
    let createdAt: Date
    let deletedAt: Date?
    let syncMetadata: FirestoreSyncMetadataFields?
    let operationId: UUID
}

nonisolated struct FirestoreWorkoutSetDocument: Codable, Equatable {
    let schemaVersion: Int
    let accountId: String
    let workoutId: String
    let setId: String
    let exerciseType: String
    let setIndex: Int?
    let target: FirestoreWorkoutTargetDTO?
    let achievedReps: Int
    let achievedHoldSeconds: Int
    let averageFormScore: Double?
    let cueEvents: [FirestoreCueEventDTO]
    let restExtended: Bool
    let skipped: Bool
    let qualitySummary: FirestoreSetQualitySummaryDTO?
    let repQualityEvents: [FirestoreRepQualityEventDTO]
    let completionSource: String?
    let completedAt: Date?
    let serverCompletedAt: Date?
    let durationSeconds: Int?
    let peakEffort: Double?
    let bestCue: String?
    let worstCue: String?
    let createdAt: Date?
    let deletedAt: Date?
    let syncMetadata: FirestoreSyncMetadataFields?
    let operationId: UUID
}

nonisolated struct FirestoreTrophyEventDocument: Codable, Equatable {
    let schemaVersion: Int
    let accountId: String
    let eventId: String
    let dedupeKey: String
    let trophyId: String
    let title: String
    let subtitle: String
    let earnedAt: Date
    let serverEarnedAt: Date?
    let retractedAt: Date?
    let reason: String
    let celebrationStyle: String
    let deletedAt: Date?
    let syncMetadata: FirestoreSyncMetadataFields?
    let operationId: UUID
}

nonisolated struct FirestoreTrophyProgressCacheDocument: Codable, Equatable {
    let schemaVersion: Int
    let accountId: String
    let catalogVersion: Int
    let generatedAt: Date
    let serverGeneratedAt: Date?
    let progress: [FirestoreTrophyProgressDTO]
    let earnedCount: Int
    let deletedAt: Date?
    let syncMetadata: FirestoreSyncMetadataFields?
    let operationId: UUID
}

nonisolated struct FirestoreInsightDocument: Codable, Equatable {
    let schemaVersion: Int
    let accountId: String
    let insightId: String
    let type: String
    let headline: String
    let message: String
    let shortMessage: String
    let evidence: [FirestoreInsightEvidenceDTO]
    let recommendedAction: String
    let severity: String
    let emotionalIntent: String
    let userValueScore: Double
    let confidence: Double
    let surfaces: [String]
    let relatedExerciseType: String?
    let relatedGoal: String?
    let createdAt: Date
    let serverCreatedAt: Date?
    let sourcePolicyVersion: String
    let expiresAt: Date?
    let dedupeKey: String
    let deletedAt: Date?
    let syncMetadata: FirestoreSyncMetadataFields?
    let operationId: UUID
}

nonisolated struct FirestoreInsightDeliveryDocument: Codable, Equatable {
    let schemaVersion: Int
    let accountId: String
    let dedupeKey: String
    let firstPresentedAt: Date
    let lastPresentedAt: Date
    let serverLastPresentedAt: Date?
    let presentationCount: Int
    let surfaceLastPresentedAt: [String: Date]
    let deletedAt: Date?
    let syncMetadata: FirestoreSyncMetadataFields?
    let operationId: UUID
}

nonisolated struct FirestoreInsightEngagementDocument: Codable, Equatable {
    let schemaVersion: Int
    let accountId: String
    let dedupeKey: String
    let engagementCounts: [String: Int]
    let lastEngagementDates: [String: Date]
    let serverLastEngagedAt: Date?
    let deletedAt: Date?
    let syncMetadata: FirestoreSyncMetadataFields?
    let operationId: UUID
}

nonisolated struct FirestoreCalibrationDocument: Codable, Equatable {
    let schemaVersion: Int
    let accountId: String
    let calibrationId: String
    let status: String
    let exerciseType: String
    let targetReps: Int
    let completedReps: Int
    let startedAt: Date
    let completedAt: Date
    let serverCompletedAt: Date?
    let visibilityPassed: Bool
    let averageFormScore: Double?
    let notes: String?
    let deletedAt: Date?
    let syncMetadata: FirestoreSyncMetadataFields?
    let operationId: UUID
}

nonisolated struct FirestorePlanDocument: Codable, Equatable {
    let schemaVersion: Int
    let accountId: String
    let planId: String
    let title: String
    let subtitle: String
    let goal: String
    let estimatedMinutes: Int
    let difficulty: String
    let coach: String
    let blocks: [FirestoreWorkoutBlockDTO]
    let generatedAt: Date
    let serverGeneratedAt: Date?
    let planReason: String
    let source: String
    let deletedAt: Date?
    let syncMetadata: FirestoreSyncMetadataFields?
    let operationId: UUID
}
