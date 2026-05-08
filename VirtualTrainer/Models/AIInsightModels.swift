import Foundation

nonisolated enum InsightType: String, Codable, CaseIterable, Hashable {
    case planSpecific
    case workoutSpecific
    case dayOverDayTrend
    case growthCelebration
    case formCorrection
    case planAdjustment
    case trophyProgress
    case consistency
    case recovery
    case safety
}

nonisolated enum InsightAction: String, Codable, CaseIterable, Hashable {
    case continuePlan
    case repeatTarget
    case increaseTarget
    case decreaseTarget
    case increaseRest
    case reduceRest
    case swapExerciseLater
    case useEasierVariant
    case useHarderVariant
    case focusCue
    case takeMobilityDay
    case protectStreakWithSmartStart
    case celebrate
    case noActionNeeded
}

nonisolated enum InsightSeverity: String, Codable, CaseIterable, Hashable {
    case positive
    case neutral
    case caution
    case important
}

nonisolated enum InsightEmotionalIntent: String, Codable, CaseIterable, Hashable {
    case celebrateGrowth
    case buildConfidence
    case giveToughLove
    case preventOverreach
    case explainPlan
    case reinforceConsistency
    case unlockMotivation
}

nonisolated enum InsightSurface: String, Codable, CaseIterable, Hashable {
    case dashboard
    case workoutPreview
    case workoutSummary
    case profile
    case trophyScreen
}

nonisolated struct InsightEvidence: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let metric: String
    let value: String
    let comparison: String?
    let workoutId: UUID?
    let exerciseType: ExerciseType?
    let setIndex: Int?
    let repIndex: Int?
    let signalId: String?
    let confidence: Double

    init(
        id: String? = nil,
        metric: String,
        value: String,
        comparison: String? = nil,
        workoutId: UUID? = nil,
        exerciseType: ExerciseType? = nil,
        setIndex: Int? = nil,
        repIndex: Int? = nil,
        signalId: String? = nil,
        confidence: Double
    ) {
        self.metric = metric
        self.value = value
        self.comparison = comparison
        self.workoutId = workoutId
        self.exerciseType = exerciseType
        self.setIndex = setIndex
        self.repIndex = repIndex
        self.signalId = signalId
        self.confidence = Self.clampedConfidence(confidence)
        self.id = id ?? Self.makeID(
            metric: metric,
            value: value,
            comparison: comparison,
            workoutId: workoutId,
            exerciseType: exerciseType,
            setIndex: setIndex,
            repIndex: repIndex,
            signalId: signalId
        )
    }

    private static func clampedConfidence(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func makeID(
        metric: String,
        value: String,
        comparison: String?,
        workoutId: UUID?,
        exerciseType: ExerciseType?,
        setIndex: Int?,
        repIndex: Int?,
        signalId: String?
    ) -> String {
        [
            metric,
            value,
            comparison,
            workoutId?.uuidString,
            exerciseType?.rawValue,
            setIndex.map { "set-\($0)" },
            repIndex.map { "rep-\($0)" },
            signalId
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }
}

nonisolated struct AIInsight: Identifiable, Codable, Equatable {
    static let currentSourcePolicyVersion = "phase14.local.deterministic.v1"

    let id: String
    let accountId: String?
    let type: InsightType
    let headline: String
    let message: String
    let shortMessage: String
    let evidence: [InsightEvidence]
    let recommendedAction: InsightAction
    let severity: InsightSeverity
    let emotionalIntent: InsightEmotionalIntent
    let userValueScore: Double
    let confidence: Double
    let surfaces: [InsightSurface]
    let relatedExerciseType: ExerciseType?
    let relatedGoal: FitnessGoal?
    let createdAt: Date
    let sourcePolicyVersion: String
    let expiresAt: Date?
    let dedupeKey: String
    let deletedAt: Date?
    var syncMetadata: SyncMetadata

    init(
        id: String? = nil,
        accountId: String? = nil,
        type: InsightType,
        headline: String,
        message: String,
        shortMessage: String,
        evidence: [InsightEvidence],
        recommendedAction: InsightAction,
        severity: InsightSeverity,
        emotionalIntent: InsightEmotionalIntent,
        userValueScore: Double,
        confidence: Double,
        surfaces: [InsightSurface],
        relatedExerciseType: ExerciseType? = nil,
        relatedGoal: FitnessGoal? = nil,
        createdAt: Date = Date(),
        sourcePolicyVersion: String = AIInsight.currentSourcePolicyVersion,
        expiresAt: Date? = nil,
        dedupeKey: String,
        deletedAt: Date? = nil,
        syncMetadata: SyncMetadata? = nil
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.accountId = normalizedAccountId
        self.type = type
        self.headline = headline
        self.message = message
        self.shortMessage = shortMessage
        self.evidence = evidence
        self.recommendedAction = recommendedAction
        self.severity = severity
        self.emotionalIntent = emotionalIntent
        self.userValueScore = userValueScore
        self.confidence = min(max(confidence, 0), 1)
        self.surfaces = surfaces
        self.relatedExerciseType = relatedExerciseType
        self.relatedGoal = relatedGoal
        self.createdAt = createdAt
        self.sourcePolicyVersion = sourcePolicyVersion
        self.expiresAt = expiresAt
        self.dedupeKey = dedupeKey
        self.deletedAt = deletedAt
        self.syncMetadata = syncMetadata ?? (
            normalizedAccountId == nil
                ? .initialLocalOnly(now: createdAt)
                : .initialPendingUpload(operationId: nil, now: createdAt)
        )
        self.id = id ?? Self.makeID(
            dedupeKey: dedupeKey,
            createdAt: createdAt,
            sourcePolicyVersion: sourcePolicyVersion
        )
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    func markedDeleted(at date: Date, operationId: UUID? = nil) -> AIInsight {
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

    func restored(operationId: UUID? = nil) -> AIInsight {
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
    ) -> AIInsight {
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

    func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    private static func makeID(
        dedupeKey: String,
        createdAt: Date,
        sourcePolicyVersion: String
    ) -> String {
        [
            sourcePolicyVersion,
            dedupeKey,
            "\(Int(createdAt.timeIntervalSince1970))"
        ].joined(separator: "|")
    }
}

nonisolated private extension AIInsight {
    func copy(
        accountId: String?,
        deletedAt: Date?,
        syncMetadata: SyncMetadata
    ) -> AIInsight {
        AIInsight(
            id: id,
            accountId: accountId,
            type: type,
            headline: headline,
            message: message,
            shortMessage: shortMessage,
            evidence: evidence,
            recommendedAction: recommendedAction,
            severity: severity,
            emotionalIntent: emotionalIntent,
            userValueScore: userValueScore,
            confidence: confidence,
            surfaces: surfaces,
            relatedExerciseType: relatedExerciseType,
            relatedGoal: relatedGoal,
            createdAt: createdAt,
            sourcePolicyVersion: sourcePolicyVersion,
            expiresAt: expiresAt,
            dedupeKey: dedupeKey,
            deletedAt: deletedAt,
            syncMetadata: syncMetadata
        )
    }
}

nonisolated extension AIInsight {
    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case type
        case headline
        case message
        case shortMessage
        case evidence
        case recommendedAction
        case severity
        case emotionalIntent
        case userValueScore
        case confidence
        case surfaces
        case relatedExerciseType
        case relatedGoal
        case createdAt
        case sourcePolicyVersion
        case expiresAt
        case dedupeKey
        case deletedAt
        case syncMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)

        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            accountId: try container.decodeIfPresent(String.self, forKey: .accountId),
            type: try container.decode(InsightType.self, forKey: .type),
            headline: try container.decode(String.self, forKey: .headline),
            message: try container.decode(String.self, forKey: .message),
            shortMessage: try container.decode(String.self, forKey: .shortMessage),
            evidence: try container.decode([InsightEvidence].self, forKey: .evidence),
            recommendedAction: try container.decode(InsightAction.self, forKey: .recommendedAction),
            severity: try container.decode(InsightSeverity.self, forKey: .severity),
            emotionalIntent: try container.decode(InsightEmotionalIntent.self, forKey: .emotionalIntent),
            userValueScore: try container.decode(Double.self, forKey: .userValueScore),
            confidence: try container.decode(Double.self, forKey: .confidence),
            surfaces: try container.decode([InsightSurface].self, forKey: .surfaces),
            relatedExerciseType: try container.decodeIfPresent(ExerciseType.self, forKey: .relatedExerciseType),
            relatedGoal: try container.decodeIfPresent(FitnessGoal.self, forKey: .relatedGoal),
            createdAt: createdAt,
            sourcePolicyVersion: try container.decode(String.self, forKey: .sourcePolicyVersion),
            expiresAt: try container.decodeIfPresent(Date.self, forKey: .expiresAt),
            dedupeKey: try container.decode(String.self, forKey: .dedupeKey),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            syncMetadata: try container.decodeIfPresent(SyncMetadata.self, forKey: .syncMetadata)
                ?? .initialLocalOnly(now: createdAt)
        )
    }
}

nonisolated struct InsightLLMContext: Codable, Equatable {
    let dedupeKey: String
    let type: InsightType
    let severity: InsightSeverity
    let action: InsightAction
    let exerciseDisplayName: String?
    let evidenceRefsJSON: String
    let deterministicHeadline: String
    let deterministicMessage: String
    let coachPersonality: CoachPersonality?
    let profileGoal: FitnessGoal?
    let profileLimitations: [PhysicalLimitation]
    let sanitizationBlocklist: [String]
}

nonisolated extension AIInsight {
    func toLLMContext() -> InsightLLMContext {
        makeLLMContext(
            coachPersonality: nil,
            profileGoal: relatedGoal,
            profileLimitations: []
        )
    }

    func toLLMContext(
        profile: UserProfile,
        coachPersonality: CoachPersonality? = nil
    ) -> InsightLLMContext {
        makeLLMContext(
            coachPersonality: coachPersonality ?? profile.preferredCoach.coachPersonality,
            profileGoal: profile.primaryGoal,
            profileLimitations: profile.limitations.sorted { $0.rawValue < $1.rawValue }
        )
    }

    private func makeLLMContext(
        coachPersonality: CoachPersonality?,
        profileGoal: FitnessGoal?,
        profileLimitations: [PhysicalLimitation]
    ) -> InsightLLMContext {
        InsightLLMContext(
            dedupeKey: dedupeKey,
            type: type,
            severity: severity,
            action: recommendedAction,
            exerciseDisplayName: exerciseDisplayName,
            evidenceRefsJSON: evidenceRefsJSON,
            deterministicHeadline: headline,
            deterministicMessage: message,
            coachPersonality: coachPersonality,
            profileGoal: profileGoal,
            profileLimitations: profileLimitations,
            sanitizationBlocklist: InsightTextSanitizer.blocklist
        )
    }

    private var exerciseDisplayName: String? {
        relatedExerciseType?.displayName ??
            evidence.first { $0.exerciseType != nil }?.exerciseType?.displayName
    }

    private var evidenceRefsJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(evidence),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }
}

nonisolated struct InsightCandidate: Identifiable, Equatable {
    let id: String
    let sourceSignalIds: [String]
    let type: InsightType
    let candidateHeadline: String
    let candidateAction: InsightAction
    let evidence: [InsightEvidence]
    let rawScore: Double
    let confidence: Double
    let surfaces: [InsightSurface]
    let severity: InsightSeverity
    let emotionalIntent: InsightEmotionalIntent
    let relatedExerciseType: ExerciseType?
    let relatedGoal: FitnessGoal?
    let createdAt: Date
    let expiresAt: Date?
    let dedupeKey: String
    let context: [String: String]

    init(
        id: String? = nil,
        sourceSignalIds: [String] = [],
        type: InsightType,
        candidateHeadline: String,
        candidateAction: InsightAction,
        evidence: [InsightEvidence],
        rawScore: Double,
        confidence: Double,
        surfaces: [InsightSurface],
        severity: InsightSeverity,
        emotionalIntent: InsightEmotionalIntent,
        relatedExerciseType: ExerciseType? = nil,
        relatedGoal: FitnessGoal? = nil,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        dedupeKey: String,
        context: [String: String] = [:]
    ) {
        self.sourceSignalIds = sourceSignalIds
        self.type = type
        self.candidateHeadline = candidateHeadline
        self.candidateAction = candidateAction
        self.evidence = evidence
        self.rawScore = rawScore
        self.confidence = min(max(confidence, 0), 1)
        self.surfaces = surfaces
        self.severity = severity
        self.emotionalIntent = emotionalIntent
        self.relatedExerciseType = relatedExerciseType
        self.relatedGoal = relatedGoal
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.dedupeKey = dedupeKey
        self.context = context
        self.id = id ?? Self.makeID(
            type: type,
            headline: candidateHeadline,
            dedupeKey: dedupeKey,
            evidence: evidence
        )
    }

    private static func makeID(
        type: InsightType,
        headline: String,
        dedupeKey: String,
        evidence: [InsightEvidence]
    ) -> String {
        [
            type.rawValue,
            headline,
            dedupeKey,
            evidence.map(\.id).joined(separator: ",")
        ].joined(separator: "|")
    }
}
