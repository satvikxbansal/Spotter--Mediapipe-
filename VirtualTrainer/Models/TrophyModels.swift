import Foundation
import Combine

nonisolated enum TrophyCategory: String, Codable, CaseIterable, Hashable {
    case starter
    case consistency
    case form
    case volume
    case muscleGroup
    case goal
    case calibration
    case timeOfDay
    case elite
    case comingSoon

    var displayName: String {
        switch self {
        case .starter: "Starter"
        case .consistency: "Consistency"
        case .form: "Form"
        case .volume: "Volume"
        case .muscleGroup: "Muscle Group"
        case .goal: "Goal"
        case .calibration: "Calibration"
        case .timeOfDay: "Time of Day"
        case .elite: "Elite"
        case .comingSoon: "Coming Soon"
        }
    }
}

nonisolated enum TrophyRarity: String, Codable, CaseIterable, Hashable {
    case common
    case rare
    case epic
    case legendary

    var displayName: String {
        rawValue.capitalized
    }
}

nonisolated enum TrophyDataRequirement: String, Codable, CaseIterable, Hashable {
    case workoutHistory
    case repQualityEvents
    case calibration
    case heartRate
    case externalLoad
    case unsupportedExercise
    case none
}

nonisolated enum TrophyProgressConfidence: String, Codable, CaseIterable, Hashable {
    case exact
    case estimated
    case unavailable

    var displayName: String {
        switch self {
        case .exact: "Exact"
        case .estimated: "Estimated"
        case .unavailable: "Unavailable"
        }
    }
}

nonisolated enum TrophyCelebrationStyle: String, Codable, Hashable {
    case standard
    case milestone
    case legendary
    case comingSoon
}

nonisolated enum TrophyUnlockRuleKind: String, Codable, Hashable {
    case firstSavedWorkout
    case calibrationCompleted
    case uniqueWorkoutDays
    case totalReps
    case singleSessionExerciseReps
    case repsForExerciseTypes
    case repsForBodyRegion
    case repsForMovementPattern
    case coreHoldSeconds
    case excellentFormReps
    case lowCueSets
    case mobilitySessions
    case weekendBothDays
    case workoutsBeforeHour
    case workoutsAtOrAfterHour
    case allEligibleNonComingSoonTrophies
    case unavailableMetric
}

nonisolated struct TrophyUnlockRule: Codable, Equatable, Hashable {
    let kind: TrophyUnlockRuleKind
    let count: Int?
    let exerciseTypes: [ExerciseType]
    let bodyRegion: BodyRegion?
    let movementPattern: MovementPattern?
    let minimumScore: Int?
    let minimumAverageFormScore: Double?
    let maximumHighSeverityCues: Int?
    let hour: Int?

    init(
        kind: TrophyUnlockRuleKind,
        count: Int? = nil,
        exerciseTypes: [ExerciseType] = [],
        bodyRegion: BodyRegion? = nil,
        movementPattern: MovementPattern? = nil,
        minimumScore: Int? = nil,
        minimumAverageFormScore: Double? = nil,
        maximumHighSeverityCues: Int? = nil,
        hour: Int? = nil
    ) {
        self.kind = kind
        self.count = count
        self.exerciseTypes = exerciseTypes
        self.bodyRegion = bodyRegion
        self.movementPattern = movementPattern
        self.minimumScore = minimumScore
        self.minimumAverageFormScore = minimumAverageFormScore
        self.maximumHighSeverityCues = maximumHighSeverityCues
        self.hour = hour
    }
}

nonisolated struct TrophyDefinition: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let longDescription: String
    let category: TrophyCategory
    let rarity: TrophyRarity
    let targetValue: Double
    let unit: String
    let iconName: String
    let designThemeHint: String
    let unlockRule: TrophyUnlockRule
    let dataRequirement: TrophyDataRequirement
    let isComingSoon: Bool
    let sortOrder: Int
    let definitionVersion: Int

    init(
        id: String,
        title: String,
        subtitle: String,
        longDescription: String,
        category: TrophyCategory,
        rarity: TrophyRarity,
        targetValue: Double,
        unit: String,
        iconName: String,
        designThemeHint: String,
        unlockRule: TrophyUnlockRule,
        dataRequirement: TrophyDataRequirement,
        isComingSoon: Bool = false,
        sortOrder: Int,
        definitionVersion: Int = TrophyDefinitionCatalog.version
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.longDescription = longDescription
        self.category = category
        self.rarity = rarity
        self.targetValue = targetValue
        self.unit = unit
        self.iconName = iconName
        self.designThemeHint = designThemeHint
        self.unlockRule = unlockRule
        self.dataRequirement = dataRequirement
        self.isComingSoon = isComingSoon
        self.sortOrder = sortOrder
        self.definitionVersion = definitionVersion
    }
}

nonisolated struct TrophyProgress: Identifiable, Codable, Equatable {
    var id: String { trophyId }

    let trophyId: String
    let currentValue: Double
    let targetValue: Double
    let earned: Bool
    let earnedAt: Date?
    let lastUpdatedAt: Date
    let confidence: TrophyProgressConfidence
    let progressLabel: String
    let accountId: String?
    var syncMetadata: SyncMetadata

    init(
        trophyId: String,
        currentValue: Double,
        targetValue: Double,
        earned: Bool,
        earnedAt: Date?,
        lastUpdatedAt: Date,
        confidence: TrophyProgressConfidence,
        progressLabel: String,
        accountId: String? = nil,
        syncMetadata: SyncMetadata? = nil
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.trophyId = trophyId
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.earned = earned
        self.earnedAt = earnedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.confidence = confidence
        self.progressLabel = progressLabel
        self.accountId = normalizedAccountId
        self.syncMetadata = syncMetadata ?? (
            normalizedAccountId == nil
                ? .initialLocalOnly(now: lastUpdatedAt)
                : .initialPendingUpload(operationId: nil, now: lastUpdatedAt)
        )
    }

    var progressFraction: Double {
        guard targetValue > 0 else { return earned ? 1 : 0 }
        return min(max(currentValue / targetValue, 0), 1)
    }

    func withAccountId(
        _ accountId: String?,
        operationId: UUID? = nil,
        now: Date = Date()
    ) -> TrophyProgress {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        return TrophyProgress(
            trophyId: trophyId,
            currentValue: currentValue,
            targetValue: targetValue,
            earned: earned,
            earnedAt: earnedAt,
            lastUpdatedAt: lastUpdatedAt,
            confidence: confidence,
            progressLabel: progressLabel,
            accountId: normalizedAccountId,
            syncMetadata: syncMetadata.markedForLocalMutation(
                accountId: normalizedAccountId,
                operationId: operationId,
                now: now
            )
        )
    }
}

nonisolated extension TrophyProgress {
    private enum CodingKeys: String, CodingKey {
        case trophyId
        case currentValue
        case targetValue
        case earned
        case earnedAt
        case lastUpdatedAt
        case confidence
        case progressLabel
        case accountId
        case syncMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lastUpdatedAt = try container.decode(Date.self, forKey: .lastUpdatedAt)

        self.init(
            trophyId: try container.decode(String.self, forKey: .trophyId),
            currentValue: try container.decode(Double.self, forKey: .currentValue),
            targetValue: try container.decode(Double.self, forKey: .targetValue),
            earned: try container.decode(Bool.self, forKey: .earned),
            earnedAt: try container.decodeIfPresent(Date.self, forKey: .earnedAt),
            lastUpdatedAt: lastUpdatedAt,
            confidence: try container.decode(TrophyProgressConfidence.self, forKey: .confidence),
            progressLabel: try container.decode(String.self, forKey: .progressLabel),
            accountId: try container.decodeIfPresent(String.self, forKey: .accountId),
            syncMetadata: try container.decodeIfPresent(SyncMetadata.self, forKey: .syncMetadata)
                ?? .initialLocalOnly(now: lastUpdatedAt)
        )
    }
}

nonisolated struct TrophyUnlockEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let accountId: String?
    let dedupeKey: String
    let trophyId: String
    let title: String
    let subtitle: String
    let earnedAt: Date
    let serverEarnedAt: Date?
    let retractedAt: Date?
    let reason: String
    let celebrationStyle: TrophyCelebrationStyle
    var syncMetadata: SyncMetadata

    init(
        id: UUID = UUID(),
        accountId: String? = nil,
        dedupeKey: String? = nil,
        trophyId: String,
        title: String,
        subtitle: String,
        earnedAt: Date,
        serverEarnedAt: Date? = nil,
        retractedAt: Date? = nil,
        reason: String,
        celebrationStyle: TrophyCelebrationStyle,
        syncMetadata: SyncMetadata? = nil
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.id = id
        self.accountId = normalizedAccountId
        self.dedupeKey = dedupeKey ?? Self.defaultDedupeKey(trophyId: trophyId)
        self.trophyId = trophyId
        self.title = title
        self.subtitle = subtitle
        self.earnedAt = earnedAt
        self.serverEarnedAt = serverEarnedAt
        self.retractedAt = retractedAt
        self.reason = reason
        self.celebrationStyle = celebrationStyle
        self.syncMetadata = syncMetadata ?? (
            normalizedAccountId == nil
                ? .initialLocalOnly(now: earnedAt)
                : .initialPendingUpload(operationId: nil, now: earnedAt)
        )
    }

    var authoritativeEarnedAt: Date {
        serverEarnedAt ?? earnedAt
    }

    var isRetracted: Bool {
        retractedAt != nil
    }

    func withAccountId(
        _ accountId: String?,
        operationId: UUID? = nil,
        now: Date = Date()
    ) -> TrophyUnlockEvent {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        return TrophyUnlockEvent(
            id: id,
            accountId: normalizedAccountId,
            dedupeKey: dedupeKey,
            trophyId: trophyId,
            title: title,
            subtitle: subtitle,
            earnedAt: earnedAt,
            serverEarnedAt: serverEarnedAt,
            retractedAt: retractedAt,
            reason: reason,
            celebrationStyle: celebrationStyle,
            syncMetadata: syncMetadata.markedForLocalMutation(
                accountId: normalizedAccountId,
                operationId: operationId,
                now: now
            )
        )
    }

    func retracted(
        at retractedAt: Date,
        operationId: UUID? = nil,
        now: Date = Date()
    ) -> TrophyUnlockEvent {
        TrophyUnlockEvent(
            id: id,
            accountId: accountId,
            dedupeKey: dedupeKey,
            trophyId: trophyId,
            title: title,
            subtitle: subtitle,
            earnedAt: earnedAt,
            serverEarnedAt: serverEarnedAt,
            retractedAt: retractedAt,
            reason: reason,
            celebrationStyle: celebrationStyle,
            syncMetadata: syncMetadata.markedForLocalMutation(
                accountId: accountId,
                operationId: operationId,
                now: now
            )
        )
    }

    static func defaultDedupeKey(trophyId: String) -> String {
        "trophy-unlock:\(trophyId)"
    }
}

nonisolated extension TrophyUnlockEvent {
    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case dedupeKey
        case trophyId
        case title
        case subtitle
        case earnedAt
        case serverEarnedAt
        case retractedAt
        case reason
        case celebrationStyle
        case syncMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let earnedAt = try container.decode(Date.self, forKey: .earnedAt)

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            accountId: try container.decodeIfPresent(String.self, forKey: .accountId),
            dedupeKey: try container.decodeIfPresent(String.self, forKey: .dedupeKey),
            trophyId: try container.decode(String.self, forKey: .trophyId),
            title: try container.decode(String.self, forKey: .title),
            subtitle: try container.decode(String.self, forKey: .subtitle),
            earnedAt: earnedAt,
            serverEarnedAt: try container.decodeIfPresent(Date.self, forKey: .serverEarnedAt),
            retractedAt: try container.decodeIfPresent(Date.self, forKey: .retractedAt),
            reason: try container.decode(String.self, forKey: .reason),
            celebrationStyle: try container.decode(TrophyCelebrationStyle.self, forKey: .celebrationStyle),
            syncMetadata: try container.decodeIfPresent(SyncMetadata.self, forKey: .syncMetadata)
                ?? .initialLocalOnly(now: earnedAt)
        )
    }
}

nonisolated struct TrophyProgressSnapshot: Codable, Equatable {
    let accountId: String?
    let catalogVersion: Int
    let generatedAt: Date
    let progress: [TrophyProgress]
    let unlockEventLog: [TrophyUnlockEvent]
    let newlyEarnedEvents: [TrophyUnlockEvent]

    init(
        accountId: String? = nil,
        catalogVersion: Int,
        generatedAt: Date,
        progress: [TrophyProgress],
        unlockEventLog: [TrophyUnlockEvent] = [],
        newlyEarnedEvents: [TrophyUnlockEvent]
    ) {
        self.accountId = AccountOwnership.normalizedAccountId(accountId)
        self.catalogVersion = catalogVersion
        self.generatedAt = generatedAt
        self.progress = progress
        self.unlockEventLog = unlockEventLog
        self.newlyEarnedEvents = newlyEarnedEvents
    }

    var progressByTrophyId: [String: TrophyProgress] {
        progress.reduce(into: [String: TrophyProgress]()) { result, progress in
            if let existing = result[progress.trophyId] {
                result[progress.trophyId] = Self.preferredProgress(existing, progress)
            } else {
                result[progress.trophyId] = progress
            }
        }
    }

    var earnedProgress: [TrophyProgress] {
        progress.filter { $0.earned }
    }

    var availableProgress: [TrophyProgress] {
        progress.filter { progress in
            guard let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId) else { return false }
            return !definition.isComingSoon
        }
    }

    var inProgress: [TrophyProgress] {
        progress.filter { progress in
            guard let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId) else { return false }
            return !definition.isComingSoon && !progress.earned
        }
    }

    var comingSoonProgress: [TrophyProgress] {
        progress.filter { progress in
            TrophyDefinitionCatalog.definition(for: progress.trophyId)?.isComingSoon == true
        }
    }

    var nearestInProgress: TrophyProgress? {
        inProgress
            .filter { $0.confidence != .unavailable }
            .max {
                if $0.progressFraction == $1.progressFraction {
                    return (TrophyDefinitionCatalog.definition(for: $0.trophyId)?.sortOrder ?? 0)
                        > (TrophyDefinitionCatalog.definition(for: $1.trophyId)?.sortOrder ?? 0)
                }
                return $0.progressFraction < $1.progressFraction
            }
    }

    func progress(for trophyId: String) -> TrophyProgress? {
        progressByTrophyId[trophyId]
    }

    private static func preferredProgress(
        _ lhs: TrophyProgress,
        _ rhs: TrophyProgress
    ) -> TrophyProgress {
        if lhs.earned != rhs.earned {
            return lhs.earned ? lhs : rhs
        }

        if lhs.earned {
            switch (lhs.earnedAt, rhs.earnedAt) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate < rhsDate ? lhs : rhs
            case (nil, _?):
                return rhs
            case (_?, nil):
                return lhs
            default:
                break
            }
        }

        if lhs.lastUpdatedAt != rhs.lastUpdatedAt {
            return lhs.lastUpdatedAt > rhs.lastUpdatedAt ? lhs : rhs
        }

        if lhs.progressFraction != rhs.progressFraction {
            return lhs.progressFraction > rhs.progressFraction ? lhs : rhs
        }

        return lhs
    }

    static func empty(now: Date = Date()) -> TrophyProgressSnapshot {
        TrophyEngine().updateAll(
            history: [],
            calibrationStatus: .notStarted,
            previousSnapshot: nil,
            now: now
        ).snapshot
    }
}

nonisolated extension TrophyProgressSnapshot {
    private enum CodingKeys: String, CodingKey {
        case accountId
        case catalogVersion
        case generatedAt
        case progress
        case unlockEventLog
        case newlyEarnedEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let newlyEarnedEvents = try container.decodeIfPresent(
            [TrophyUnlockEvent].self,
            forKey: .newlyEarnedEvents
        ) ?? []

        self.init(
            accountId: try container.decodeIfPresent(String.self, forKey: .accountId),
            catalogVersion: try container.decode(Int.self, forKey: .catalogVersion),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            progress: try container.decode([TrophyProgress].self, forKey: .progress),
            unlockEventLog: try container.decodeIfPresent(
                [TrophyUnlockEvent].self,
                forKey: .unlockEventLog
            ) ?? newlyEarnedEvents,
            newlyEarnedEvents: newlyEarnedEvents
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(accountId, forKey: .accountId)
        try container.encode(catalogVersion, forKey: .catalogVersion)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(progress, forKey: .progress)
        try container.encode(unlockEventLog, forKey: .unlockEventLog)
        try container.encode(newlyEarnedEvents, forKey: .newlyEarnedEvents)
    }
}

nonisolated enum TrophyDefinitionCatalog {
    static let version = 1

    enum ID {
        static let spark = "the-spark"
        static let calibrated = "calibrated"
        static let sevenDayInferno = "seven-day-inferno"
        static let ironWill = "iron-will"
        static let theMachine = "the-machine"
        static let weekendFlex = "weekend-flex"
        static let morningGlory = "morning-glory"
        static let nightOwl = "night-owl"
        static let formArchitect = "form-architect"
        static let eliteForm = "elite-form"
        static let oneKClub = "one-k-club"
        static let squatKing = "squat-king"
        static let legDayLegend = "leg-day-legend"
        static let titanArms = "titan-arms"
        static let chestCmdr = "chest-cmdr"
        static let coreCrusader = "core-crusader"
        static let zenMaster = "zen-master"
        static let neonPulse = "neon-pulse"
        static let heavyMetal = "heavy-metal"
        static let burpeeBeast = "burpee-beast"
        static let apexSpotter = "apex-spotter"
        static let alphaSpotter = "alpha-spotter"
    }

    static let all: [TrophyDefinition] = [
        TrophyDefinition(
            id: ID.spark,
            title: "The Spark",
            subtitle: "First workout complete",
            longDescription: "Save your first workout or form-check session to start your collection.",
            category: .starter,
            rarity: .common,
            targetValue: 1,
            unit: "workout",
            iconName: "bolt.fill",
            designThemeHint: "accent",
            unlockRule: TrophyUnlockRule(kind: .firstSavedWorkout, count: 1),
            dataRequirement: .workoutHistory,
            sortOrder: 10
        ),
        TrophyDefinition(
            id: ID.calibrated,
            title: "Calibrated",
            subtitle: "Space setup verified",
            longDescription: "Complete calibration so Spotter knows your camera setup is usable.",
            category: .calibration,
            rarity: .common,
            targetValue: 1,
            unit: "calibration",
            iconName: "camera.viewfinder",
            designThemeHint: "cyan",
            unlockRule: TrophyUnlockRule(kind: .calibrationCompleted, count: 1),
            dataRequirement: .calibration,
            sortOrder: 20
        ),
        TrophyDefinition(
            id: ID.sevenDayInferno,
            title: "7-Day Inferno",
            subtitle: "7 unique workout days",
            longDescription: "Train on seven different calendar days. They do not need to be consecutive.",
            category: .consistency,
            rarity: .rare,
            targetValue: 7,
            unit: "days",
            iconName: "flame.fill",
            designThemeHint: "red",
            unlockRule: TrophyUnlockRule(kind: .uniqueWorkoutDays, count: 7),
            dataRequirement: .workoutHistory,
            sortOrder: 100
        ),
        TrophyDefinition(
            id: ID.ironWill,
            title: "Iron Will",
            subtitle: "30 active training days",
            longDescription: "Show up for thirty different workout days, with rest days fully allowed.",
            category: .consistency,
            rarity: .epic,
            targetValue: 30,
            unit: "days",
            iconName: "infinity",
            designThemeHint: "cyan",
            unlockRule: TrophyUnlockRule(kind: .uniqueWorkoutDays, count: 30),
            dataRequirement: .workoutHistory,
            sortOrder: 110
        ),
        TrophyDefinition(
            id: ID.theMachine,
            title: "The Machine",
            subtitle: "14 active training days",
            longDescription: "Build a durable routine across fourteen different workout days. This trophy does not punish missed days.",
            category: .consistency,
            rarity: .epic,
            targetValue: 14,
            unit: "days",
            iconName: "gearshape.2.fill",
            designThemeHint: "slate",
            unlockRule: TrophyUnlockRule(kind: .uniqueWorkoutDays, count: 14),
            dataRequirement: .workoutHistory,
            sortOrder: 120
        ),
        TrophyDefinition(
            id: ID.weekendFlex,
            title: "Weekend Flex",
            subtitle: "Work out on Saturday and Sunday",
            longDescription: "Complete workouts on both days of the same weekend.",
            category: .consistency,
            rarity: .rare,
            targetValue: 2,
            unit: "weekend days",
            iconName: "star.fill",
            designThemeHint: "pink",
            unlockRule: TrophyUnlockRule(kind: .weekendBothDays, count: 2),
            dataRequirement: .workoutHistory,
            sortOrder: 130
        ),
        TrophyDefinition(
            id: ID.morningGlory,
            title: "Morning Glory",
            subtitle: "5 workouts before 7AM",
            longDescription: "Start five sessions before 7AM in your local calendar.",
            category: .timeOfDay,
            rarity: .rare,
            targetValue: 5,
            unit: "workouts",
            iconName: "sunrise.fill",
            designThemeHint: "orange",
            unlockRule: TrophyUnlockRule(kind: .workoutsBeforeHour, count: 5, hour: 7),
            dataRequirement: .workoutHistory,
            sortOrder: 140
        ),
        TrophyDefinition(
            id: ID.nightOwl,
            title: "Night Owl",
            subtitle: "Work out after 10PM",
            longDescription: "Start one saved workout at or after 10PM in your local calendar.",
            category: .timeOfDay,
            rarity: .common,
            targetValue: 1,
            unit: "workout",
            iconName: "moon.stars.fill",
            designThemeHint: "indigo",
            unlockRule: TrophyUnlockRule(kind: .workoutsAtOrAfterHour, count: 1, hour: 22),
            dataRequirement: .workoutHistory,
            sortOrder: 150
        ),
        TrophyDefinition(
            id: ID.formArchitect,
            title: "Form Architect",
            subtitle: "500 reps at 95%+ form",
            longDescription: "Log five hundred reps with a form score of 95 or higher. Rep-quality events are used when available.",
            category: .form,
            rarity: .epic,
            targetValue: 500,
            unit: "reps",
            iconName: "ruler.fill",
            designThemeHint: "cyan",
            unlockRule: TrophyUnlockRule(kind: .excellentFormReps, count: 500, minimumScore: 95),
            dataRequirement: .repQualityEvents,
            sortOrder: 200
        ),
        TrophyDefinition(
            id: ID.eliteForm,
            title: "Elite Form",
            subtitle: "10 zero or low-cue sets",
            longDescription: "Complete ten sets with strong form and no warning-or-critical cues.",
            category: .form,
            rarity: .epic,
            targetValue: 10,
            unit: "sets",
            iconName: "checkmark.seal.fill",
            designThemeHint: "accent",
            unlockRule: TrophyUnlockRule(
                kind: .lowCueSets,
                count: 10,
                minimumAverageFormScore: 90,
                maximumHighSeverityCues: 0
            ),
            dataRequirement: .repQualityEvents,
            sortOrder: 210
        ),
        TrophyDefinition(
            id: ID.oneKClub,
            title: "1K Club",
            subtitle: "1,000 total reps logged",
            longDescription: "Complete one thousand total counted reps across saved sessions.",
            category: .volume,
            rarity: .rare,
            targetValue: 1_000,
            unit: "reps",
            iconName: "target",
            designThemeHint: "red",
            unlockRule: TrophyUnlockRule(kind: .totalReps, count: 1_000),
            dataRequirement: .workoutHistory,
            sortOrder: 300
        ),
        TrophyDefinition(
            id: ID.squatKing,
            title: "Squat King",
            subtitle: "100 squats in one session",
            longDescription: "Complete one hundred camera-counted squats in a single saved session.",
            category: .volume,
            rarity: .epic,
            targetValue: 100,
            unit: "squats",
            iconName: "crown.fill",
            designThemeHint: "accent",
            unlockRule: TrophyUnlockRule(kind: .singleSessionExerciseReps, count: 100, exerciseTypes: [.squat]),
            dataRequirement: .workoutHistory,
            sortOrder: 310
        ),
        TrophyDefinition(
            id: ID.legDayLegend,
            title: "Leg Day Legend",
            subtitle: "1,000 lower-body reps",
            longDescription: "Log one thousand counted reps from lower-body movements.",
            category: .muscleGroup,
            rarity: .rare,
            targetValue: 1_000,
            unit: "reps",
            iconName: "figure.strengthtraining.traditional",
            designThemeHint: "orange",
            unlockRule: TrophyUnlockRule(kind: .repsForBodyRegion, count: 1_000, bodyRegion: .lower),
            dataRequirement: .workoutHistory,
            sortOrder: 320
        ),
        TrophyDefinition(
            id: ID.titanArms,
            title: "Titan Arms",
            subtitle: "500 bicep/tricep reps",
            longDescription: "Complete five hundred counted reps from arm-focused movements.",
            category: .muscleGroup,
            rarity: .rare,
            targetValue: 500,
            unit: "reps",
            iconName: "figure.arms.open",
            designThemeHint: "pink",
            unlockRule: TrophyUnlockRule(
                kind: .repsForExerciseTypes,
                count: 500,
                exerciseTypes: [.bicepCurl, .hammerCurl, .tricepDip]
            ),
            dataRequirement: .workoutHistory,
            sortOrder: 330
        ),
        TrophyDefinition(
            id: ID.chestCmdr,
            title: "Chest Cmdr",
            subtitle: "500 upper-body push reps",
            longDescription: "Complete five hundred counted reps from upper-body push exercises.",
            category: .muscleGroup,
            rarity: .rare,
            targetValue: 500,
            unit: "reps",
            iconName: "shield.lefthalf.filled",
            designThemeHint: "red",
            unlockRule: TrophyUnlockRule(kind: .repsForMovementPattern, count: 500, bodyRegion: .upper, movementPattern: .push),
            dataRequirement: .workoutHistory,
            sortOrder: 340
        ),
        TrophyDefinition(
            id: ID.coreCrusader,
            title: "Core Crusader",
            subtitle: "1 hour of plank holds",
            longDescription: "Accumulate one hour of plank or side-plank hold time.",
            category: .muscleGroup,
            rarity: .epic,
            targetValue: 3_600,
            unit: "seconds",
            iconName: "circle.lefthalf.filled",
            designThemeHint: "teal",
            unlockRule: TrophyUnlockRule(kind: .coreHoldSeconds, count: 3_600),
            dataRequirement: .workoutHistory,
            sortOrder: 350
        ),
        TrophyDefinition(
            id: ID.zenMaster,
            title: "Zen Master",
            subtitle: "10 mobility/longevity sessions",
            longDescription: "Complete ten sessions that are primarily mobility, yoga, or longevity-focused.",
            category: .goal,
            rarity: .rare,
            targetValue: 10,
            unit: "sessions",
            iconName: "leaf.fill",
            designThemeHint: "teal",
            unlockRule: TrophyUnlockRule(kind: .mobilitySessions, count: 10),
            dataRequirement: .workoutHistory,
            sortOrder: 400
        ),
        TrophyDefinition(
            id: ID.neonPulse,
            title: "Neon Pulse",
            subtitle: "150+ BPM for 20 minutes",
            longDescription: "Coming soon. Spotter does not currently connect to a heart-rate sensor, so face-effort proxy data is not used for BPM trophies.",
            category: .comingSoon,
            rarity: .epic,
            targetValue: 20,
            unit: "minutes",
            iconName: "heart.fill",
            designThemeHint: "magenta",
            unlockRule: TrophyUnlockRule(kind: .unavailableMetric, count: 20),
            dataRequirement: .heartRate,
            isComingSoon: true,
            sortOrder: 500
        ),
        TrophyDefinition(
            id: ID.heavyMetal,
            title: "Heavy Metal",
            subtitle: "10,000 KG total volume",
            longDescription: "Coming soon. Spotter does not currently collect dumbbell or kettlebell load, so KG volume is not estimated from equipment alone.",
            category: .comingSoon,
            rarity: .epic,
            targetValue: 10_000,
            unit: "kg",
            iconName: "dumbbell.fill",
            designThemeHint: "purple",
            unlockRule: TrophyUnlockRule(kind: .unavailableMetric, count: 10_000),
            dataRequirement: .externalLoad,
            isComingSoon: true,
            sortOrder: 510
        ),
        TrophyDefinition(
            id: ID.burpeeBeast,
            title: "Burpee Beast",
            subtitle: "50 burpees in 3 minutes",
            longDescription: "Coming soon. Burpees are not currently implemented and validated as a tracked exercise.",
            category: .comingSoon,
            rarity: .legendary,
            targetValue: 50,
            unit: "burpees",
            iconName: "figure.highintensity.intervaltraining",
            designThemeHint: "slate",
            unlockRule: TrophyUnlockRule(kind: .unavailableMetric, count: 50),
            dataRequirement: .unsupportedExercise,
            isComingSoon: true,
            sortOrder: 520
        ),
        TrophyDefinition(
            id: ID.apexSpotter,
            title: "Apex Spotter",
            subtitle: "Earn every eligible trophy",
            longDescription: "Unlock every currently supported non-coming-soon trophy. Coming-soon trophies are excluded until their data is real.",
            category: .elite,
            rarity: .legendary,
            targetValue: 1,
            unit: "collection",
            iconName: "asterisk",
            designThemeHint: "gold",
            unlockRule: TrophyUnlockRule(kind: .allEligibleNonComingSoonTrophies),
            dataRequirement: .none,
            sortOrder: 900
        ),
        TrophyDefinition(
            id: ID.alphaSpotter,
            title: "Alpha Spotter",
            subtitle: "Claim the ultimate title",
            longDescription: "A second title treatment for the all-supported-trophies capstone used by the trophy home screen design.",
            category: .elite,
            rarity: .legendary,
            targetValue: 1,
            unit: "collection",
            iconName: "crown.fill",
            designThemeHint: "gold",
            unlockRule: TrophyUnlockRule(kind: .allEligibleNonComingSoonTrophies),
            dataRequirement: .none,
            sortOrder: 910
        )
    ].sorted { $0.sortOrder < $1.sortOrder }

    static func definition(for trophyId: String) -> TrophyDefinition? {
        definitionsById[trophyId]
    }

    static var supportedDefinitions: [TrophyDefinition] {
        all.filter { !$0.isComingSoon }
    }

    static var comingSoonDefinitions: [TrophyDefinition] {
        all.filter(\.isComingSoon)
    }

    static var capstoneDefinitions: [TrophyDefinition] {
        all.filter { $0.unlockRule.kind == .allEligibleNonComingSoonTrophies }
    }

    static var regularEligibleDefinitions: [TrophyDefinition] {
        all.filter {
            !$0.isComingSoon &&
                $0.unlockRule.kind != .allEligibleNonComingSoonTrophies
        }
    }

    private static let definitionsById = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

nonisolated struct TrophyEngineResult: Equatable {
    let snapshot: TrophyProgressSnapshot
    let newlyEarnedEvents: [TrophyUnlockEvent]
}

nonisolated struct TrophyEngine {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func update(
        after summary: WorkoutSessionSummary,
        history: [WorkoutSessionSummary],
        calibrationStatus: CalibrationStatus,
        previousSnapshot: TrophyProgressSnapshot? = nil,
        canonicalUnlockEvents: [TrophyUnlockEvent] = [],
        now: Date = Date()
    ) -> TrophyEngineResult {
        updateAll(
            history: history.contains(where: { $0.id == summary.id }) ? history : history + [summary],
            calibrationStatus: calibrationStatus,
            previousSnapshot: previousSnapshot,
            canonicalUnlockEvents: canonicalUnlockEvents,
            now: now
        )
    }

    func updateAll(
        history: [WorkoutSessionSummary],
        calibrationStatus: CalibrationStatus,
        previousSnapshot: TrophyProgressSnapshot? = nil,
        canonicalUnlockEvents: [TrophyUnlockEvent] = [],
        now: Date = Date()
    ) -> TrophyEngineResult {
        let sortedHistory = history.sorted {
            if $0.authoritativeEndedAt == $1.authoritativeEndedAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.authoritativeEndedAt < $1.authoritativeEndedAt
        }
        let eventLog = mergedCanonicalUnlockEvents(
            canonicalUnlockEvents,
            previousSnapshot: previousSnapshot
        )
        let eventStateById = unlockEventStateByTrophyId(eventLog)
        var mergedById: [String: TrophyProgress] = [:]

        for definition in TrophyDefinitionCatalog.all where definition.unlockRule.kind != .allEligibleNonComingSoonTrophies {
            let eventState = eventStateById[definition.id]
            let computed = computeProgress(
                for: definition,
                history: sortedHistory,
                calibrationStatus: calibrationStatus,
                activeUnlockEvent: eventState?.activeEvent,
                isTombstoned: eventState?.isTombstoned == true,
                now: now
            )
            mergedById[definition.id] = computed
        }

        for definition in TrophyDefinitionCatalog.capstoneDefinitions {
            let eventState = eventStateById[definition.id]
            let computed = computeCapstoneProgress(
                for: definition,
                regularProgressById: mergedById,
                activeUnlockEvent: eventState?.activeEvent,
                isTombstoned: eventState?.isTombstoned == true,
                now: now
            )
            mergedById[definition.id] = computed
        }

        let orderedProgress = TrophyDefinitionCatalog.all.compactMap { mergedById[$0.id] }
        let events = newlyEarnedEvents(
            eventStateById: eventStateById,
            currentProgress: orderedProgress,
            now: now
        )
        let updatedEventLog = dedupedCanonicalUnlockEvents(eventLog + events)
        let snapshot = TrophyProgressSnapshot(
            catalogVersion: TrophyDefinitionCatalog.version,
            generatedAt: now,
            progress: orderedProgress,
            unlockEventLog: updatedEventLog,
            newlyEarnedEvents: events
        )

        return TrophyEngineResult(snapshot: snapshot, newlyEarnedEvents: events)
    }

    private struct UnlockEventState {
        let activeEvent: TrophyUnlockEvent?
        let hasRetraction: Bool

        var isTombstoned: Bool {
            activeEvent == nil && hasRetraction
        }
    }

    private func mergedCanonicalUnlockEvents(
        _ canonicalUnlockEvents: [TrophyUnlockEvent],
        previousSnapshot: TrophyProgressSnapshot?
    ) -> [TrophyUnlockEvent] {
        var events = canonicalUnlockEvents

        if events.isEmpty, let previousSnapshot {
            events = previousSnapshot.unlockEventLog.isEmpty
                ? previousSnapshot.newlyEarnedEvents
                : previousSnapshot.unlockEventLog
        }

        if let previousSnapshot {
            events.append(
                contentsOf: legacyUnlockEvents(
                    from: previousSnapshot,
                    excluding: events
                )
            )
        }

        return dedupedCanonicalUnlockEvents(events)
    }

    private func legacyUnlockEvents(
        from snapshot: TrophyProgressSnapshot,
        excluding existingEvents: [TrophyUnlockEvent]
    ) -> [TrophyUnlockEvent] {
        let existingStorageKeys = Set(
            existingEvents.map {
                AccountOwnership.storageKey(accountId: $0.accountId, recordId: $0.trophyId)
            }
        )

        return snapshot.progress.compactMap { progress in
            guard progress.earned,
                  !existingStorageKeys.contains(
                    AccountOwnership.storageKey(accountId: progress.accountId, recordId: progress.trophyId)
                  ),
                  let earnedAt = progress.earnedAt,
                  let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId),
                  !definition.isComingSoon
            else { return nil }

            return TrophyUnlockEvent(
                accountId: progress.accountId,
                trophyId: definition.id,
                title: definition.title,
                subtitle: definition.subtitle,
                earnedAt: earnedAt,
                reason: unlockReason(for: definition, progress: progress),
                celebrationStyle: celebrationStyle(for: definition),
                syncMetadata: progress.syncMetadata
            )
        }
    }

    private func unlockEventStateByTrophyId(
        _ eventLog: [TrophyUnlockEvent]
    ) -> [String: UnlockEventState] {
        Dictionary(grouping: eventLog, by: \.trophyId).mapValues { events in
            UnlockEventState(
                activeEvent: events.filter { !$0.isRetracted }.min(by: isEarlierUnlockEvent),
                hasRetraction: events.contains(where: \.isRetracted)
            )
        }
    }

    private func dedupedCanonicalUnlockEvents(
        _ events: [TrophyUnlockEvent]
    ) -> [TrophyUnlockEvent] {
        let operationDeduped = Dictionary(grouping: events, by: operationDedupeStorageKey)
            .values
            .compactMap(preferredUnlockEvent)

        return Dictionary(grouping: operationDeduped, by: trophyStorageKey)
            .values
            .compactMap(preferredUnlockEvent)
            .sorted(by: isEarlierUnlockEvent)
    }

    private func operationDedupeStorageKey(for event: TrophyUnlockEvent) -> String {
        let recordId = event.syncMetadata.pendingOperationId.map {
            "\(event.trophyId)|operation|\($0.uuidString)"
        } ?? "\(event.trophyId)|dedupe|\(event.dedupeKey)"
        return AccountOwnership.storageKey(accountId: event.accountId, recordId: recordId)
    }

    private func trophyStorageKey(for event: TrophyUnlockEvent) -> String {
        AccountOwnership.storageKey(accountId: event.accountId, recordId: event.trophyId)
    }

    private func preferredUnlockEvent(
        _ events: [TrophyUnlockEvent]
    ) -> TrophyUnlockEvent? {
        events.min { lhs, rhs in
            if lhs.isRetracted != rhs.isRetracted {
                return lhs.isRetracted
            }
            if lhs.isRetracted, rhs.isRetracted,
               lhs.syncMetadata.localUpdatedAt != rhs.syncMetadata.localUpdatedAt {
                return lhs.syncMetadata.localUpdatedAt > rhs.syncMetadata.localUpdatedAt
            }
            return isEarlierUnlockEvent(lhs, rhs)
        }
    }

    private func isEarlierUnlockEvent(
        _ lhs: TrophyUnlockEvent,
        _ rhs: TrophyUnlockEvent
    ) -> Bool {
        if lhs.authoritativeEarnedAt != rhs.authoritativeEarnedAt {
            return lhs.authoritativeEarnedAt < rhs.authoritativeEarnedAt
        }
        if lhs.earnedAt != rhs.earnedAt {
            return lhs.earnedAt < rhs.earnedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func computeProgress(
        for definition: TrophyDefinition,
        history: [WorkoutSessionSummary],
        calibrationStatus: CalibrationStatus,
        activeUnlockEvent: TrophyUnlockEvent?,
        isTombstoned: Bool,
        now: Date
    ) -> TrophyProgress {
        if definition.isComingSoon {
            return TrophyProgress(
                trophyId: definition.id,
                currentValue: 0,
                targetValue: definition.targetValue,
                earned: false,
                earnedAt: nil,
                lastUpdatedAt: now,
                confidence: .unavailable,
                progressLabel: "Coming Soon"
            )
        }

        let target = Double(definition.unlockRule.count ?? Int(definition.targetValue))
        let metric = metricValue(
            for: definition.unlockRule,
            history: history,
            calibrationStatus: calibrationStatus
        )
        let earnedByEvent = activeUnlockEvent != nil
        let earnedByMetric = metric.value >= target && target > 0 && !isTombstoned
        let earned = earnedByEvent || earnedByMetric
        let currentValue = earnedByEvent ? max(metric.value, target) : min(metric.value, target)

        return TrophyProgress(
            trophyId: definition.id,
            currentValue: currentValue,
            targetValue: target,
            earned: earned,
            earnedAt: activeUnlockEvent?.authoritativeEarnedAt ?? (earnedByMetric ? now : nil),
            lastUpdatedAt: now,
            confidence: metric.confidence,
            progressLabel: progressLabel(
                currentValue: metric.value,
                targetValue: target,
                unit: definition.unit,
                earned: earned,
                confidence: metric.confidence
            )
        )
    }

    private func computeCapstoneProgress(
        for definition: TrophyDefinition,
        regularProgressById: [String: TrophyProgress],
        activeUnlockEvent: TrophyUnlockEvent?,
        isTombstoned: Bool,
        now: Date
    ) -> TrophyProgress {
        let eligibleDefinitions = TrophyDefinitionCatalog.regularEligibleDefinitions
        let target = Double(eligibleDefinitions.count)
        let earnedCount = eligibleDefinitions.reduce(0) { count, definition in
            count + ((regularProgressById[definition.id]?.earned == true) ? 1 : 0)
        }
        let earnedByEvent = activeUnlockEvent != nil
        let earnedByMetric = target > 0 && Double(earnedCount) >= target && !isTombstoned
        let earned = earnedByEvent || earnedByMetric

        return TrophyProgress(
            trophyId: definition.id,
            currentValue: earnedByEvent ? target : Double(earnedCount),
            targetValue: target,
            earned: earned,
            earnedAt: activeUnlockEvent?.authoritativeEarnedAt ?? (earnedByMetric ? now : nil),
            lastUpdatedAt: now,
            confidence: .exact,
            progressLabel: progressLabel(
                currentValue: Double(earnedCount),
                targetValue: target,
                unit: "eligible trophies",
                earned: earned,
                confidence: .exact
            )
        )
    }

    private func newlyEarnedEvents(
        eventStateById: [String: UnlockEventState],
        currentProgress: [TrophyProgress],
        now: Date
    ) -> [TrophyUnlockEvent] {
        currentProgress.compactMap { progress in
            guard progress.earned,
                  eventStateById[progress.trophyId]?.activeEvent == nil,
                  eventStateById[progress.trophyId]?.isTombstoned != true,
                  let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId),
                  !definition.isComingSoon
            else { return nil }

            return TrophyUnlockEvent(
                trophyId: definition.id,
                title: definition.title,
                subtitle: definition.subtitle,
                earnedAt: progress.earnedAt ?? now,
                serverEarnedAt: nil,
                reason: unlockReason(for: definition, progress: progress),
                celebrationStyle: celebrationStyle(for: definition)
            )
        }
    }

    private func metricValue(
        for rule: TrophyUnlockRule,
        history: [WorkoutSessionSummary],
        calibrationStatus: CalibrationStatus
    ) -> (value: Double, confidence: TrophyProgressConfidence) {
        switch rule.kind {
        case .firstSavedWorkout:
            return (history.isEmpty ? 0 : 1, .exact)
        case .calibrationCompleted:
            return (calibrationStatus == .completed ? 1 : 0, .exact)
        case .uniqueWorkoutDays:
            return (Double(uniqueWorkoutDays(in: history).count), .exact)
        case .totalReps:
            return (Double(history.reduce(0) { $0 + $1.totalReps }), .exact)
        case .singleSessionExerciseReps:
            return (Double(maxSingleSessionReps(for: rule.exerciseTypes, in: history)), .exact)
        case .repsForExerciseTypes:
            return (Double(totalReps(for: Set(rule.exerciseTypes), in: history)), .exact)
        case .repsForBodyRegion:
            guard let bodyRegion = rule.bodyRegion else { return (0, .unavailable) }
            return (Double(totalReps(bodyRegion: bodyRegion, movementPattern: nil, in: history)), .exact)
        case .repsForMovementPattern:
            guard let movementPattern = rule.movementPattern else { return (0, .unavailable) }
            return (Double(totalReps(bodyRegion: rule.bodyRegion, movementPattern: movementPattern, in: history)), .exact)
        case .coreHoldSeconds:
            return (Double(coreHoldSeconds(in: history)), .exact)
        case .excellentFormReps:
            return excellentFormReps(minimumScore: rule.minimumScore ?? 95, in: history)
        case .lowCueSets:
            return (
                Double(
                    lowCueSetCount(
                        minimumAverageFormScore: rule.minimumAverageFormScore ?? 90,
                        maximumHighSeverityCues: rule.maximumHighSeverityCues ?? 0,
                        in: history
                    )
                ),
                .exact
            )
        case .mobilitySessions:
            return (Double(history.filter(isMobilitySession).count), .exact)
        case .weekendBothDays:
            return (Double(maxWeekendDayCoverage(in: history)), .exact)
        case .workoutsBeforeHour:
            return (Double(workouts(in: history, beforeHour: rule.hour ?? 7)), .exact)
        case .workoutsAtOrAfterHour:
            return (Double(workouts(in: history, atOrAfterHour: rule.hour ?? 22)), .exact)
        case .allEligibleNonComingSoonTrophies:
            return (0, .exact)
        case .unavailableMetric:
            return (0, .unavailable)
        }
    }

    private func uniqueWorkoutDays(in history: [WorkoutSessionSummary]) -> Set<Date> {
        Set(history.map { calendar.startOfDay(for: $0.authoritativeEndedAt) })
    }

    private func maxSingleSessionReps(
        for exerciseTypes: [ExerciseType],
        in history: [WorkoutSessionSummary]
    ) -> Int {
        let targetTypes = Set(exerciseTypes)
        return history.map { summary in
            summary.exerciseSummaries.reduce(0) { total, setSummary in
                targetTypes.contains(setSummary.exerciseType)
                    ? total + setSummary.achievedReps
                    : total
            }
        }.max() ?? 0
    }

    private func totalReps(
        for exerciseTypes: Set<ExerciseType>,
        in history: [WorkoutSessionSummary]
    ) -> Int {
        history
            .flatMap(\.exerciseSummaries)
            .filter { exerciseTypes.contains($0.exerciseType) }
            .reduce(0) { $0 + $1.achievedReps }
    }

    private func totalReps(
        bodyRegion: BodyRegion?,
        movementPattern: MovementPattern?,
        in history: [WorkoutSessionSummary]
    ) -> Int {
        history
            .flatMap(\.exerciseSummaries)
            .filter { setSummary in
                guard let metadata = ExerciseMetadataCatalog.metadata(for: setSummary.exerciseType) else {
                    return false
                }
                if let bodyRegion, metadata.bodyRegion != bodyRegion {
                    return false
                }
                if let movementPattern, metadata.movementPattern != movementPattern {
                    return false
                }
                return true
            }
            .reduce(0) { $0 + $1.achievedReps }
    }

    private func coreHoldSeconds(in history: [WorkoutSessionSummary]) -> Int {
        history
            .flatMap(\.exerciseSummaries)
            .filter { setSummary in
                setSummary.exerciseType == .plank || setSummary.exerciseType == .sidePlank
            }
            .reduce(0) { $0 + $1.achievedHoldSeconds }
    }

    private func excellentFormReps(
        minimumScore: Int,
        in history: [WorkoutSessionSummary]
    ) -> (value: Double, confidence: TrophyProgressConfidence) {
        let repEvents = history
            .flatMap(\.exerciseSummaries)
            .flatMap(\.repQualityEvents)

        if !repEvents.isEmpty {
            return (
                Double(repEvents.filter { ($0.formScore ?? -1) >= minimumScore }.count),
                .exact
            )
        }

        let scoredSetSummaries = history
            .flatMap(\.exerciseSummaries)
            .filter { $0.averageFormScore != nil }

        guard !scoredSetSummaries.isEmpty else {
            return (0, history.isEmpty ? .exact : .unavailable)
        }

        let estimatedReps = scoredSetSummaries.reduce(0) { total, setSummary in
            guard let averageFormScore = setSummary.averageFormScore,
                  averageFormScore >= Double(minimumScore)
            else { return total }
            return total + setSummary.achievedReps
        }

        return (Double(estimatedReps), .estimated)
    }

    private func lowCueSetCount(
        minimumAverageFormScore: Double,
        maximumHighSeverityCues: Int,
        in history: [WorkoutSessionSummary]
    ) -> Int {
        history
            .flatMap(\.exerciseSummaries)
            .filter { setSummary in
                let hasWork = setSummary.achievedReps > 0 || setSummary.achievedHoldSeconds > 0
                guard hasWork,
                      let averageFormScore = setSummary.averageFormScore,
                      averageFormScore >= minimumAverageFormScore
                else { return false }

                let qualityHighSeverity = setSummary.qualitySummary?.highSeverityCueCount
                let cueEventHighSeverity = setSummary.cueEvents.filter { $0.severity >= .warning }.count
                let repCueHighSeverity = setSummary.repQualityEvents.filter {
                    guard let severity = $0.cueSeverityNearRep else { return false }
                    return severity >= .warning
                }.count
                let highSeverity = qualityHighSeverity ?? (cueEventHighSeverity + repCueHighSeverity)

                return highSeverity <= maximumHighSeverityCues
            }
            .count
    }

    private func isMobilitySession(_ summary: WorkoutSessionSummary) -> Bool {
        let normalizedGoal = (summary.goal ?? summary.planTitle ?? summary.title)
            .lowercased()
        if normalizedGoal.contains("mobility") ||
            normalizedGoal.contains("longevity") ||
            normalizedGoal.contains("yoga") {
            return true
        }

        let exerciseSummaries = summary.exerciseSummaries
        guard !exerciseSummaries.isEmpty else { return false }

        let qualifyingCount = exerciseSummaries.filter { setSummary in
            guard let metadata = ExerciseMetadataCatalog.metadata(for: setSummary.exerciseType) else {
                return false
            }
            return metadata.bodyRegion == .mobility ||
                metadata.movementPattern == .mobility ||
                metadata.movementPattern == .yogaHold
        }.count

        return Double(qualifyingCount) / Double(exerciseSummaries.count) >= 0.5
    }

    private func maxWeekendDayCoverage(in history: [WorkoutSessionSummary]) -> Int {
        let weekendDaysByWeek = history.reduce(into: [String: Set<Int>]()) { result, summary in
            let endedAt = summary.authoritativeEndedAt
            let weekday = calendar.component(.weekday, from: endedAt)
            guard weekday == 1 || weekday == 7 else { return }

            let weekendAnchor = weekday == 1
                ? calendar.date(byAdding: .day, value: -1, to: endedAt) ?? endedAt
                : endedAt
            let weekKey = "\(calendar.startOfDay(for: weekendAnchor).timeIntervalSince1970)"
            result[weekKey, default: []].insert(weekday)
        }

        return weekendDaysByWeek.values.map(\.count).max() ?? 0
    }

    private func workouts(
        in history: [WorkoutSessionSummary],
        beforeHour hour: Int
    ) -> Int {
        history.filter {
            calendar.component(.hour, from: $0.startedAt) < hour
        }.count
    }

    private func workouts(
        in history: [WorkoutSessionSummary],
        atOrAfterHour hour: Int
    ) -> Int {
        history.filter {
            calendar.component(.hour, from: $0.startedAt) >= hour
        }.count
    }

    private func progressLabel(
        currentValue: Double,
        targetValue: Double,
        unit: String,
        earned: Bool,
        confidence: TrophyProgressConfidence
    ) -> String {
        if confidence == .unavailable {
            return "Coming Soon"
        }
        if earned {
            return "Earned"
        }
        return "\(format(currentValue))/\(format(targetValue)) \(unit)"
    }

    private func format(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private func unlockReason(
        for definition: TrophyDefinition,
        progress: TrophyProgress
    ) -> String {
        switch definition.unlockRule.kind {
        case .firstSavedWorkout:
            return "You saved your first workout."
        case .calibrationCompleted:
            return "Calibration is complete."
        case .allEligibleNonComingSoonTrophies:
            return "Every currently supported trophy is earned."
        default:
            return "You reached \(format(progress.targetValue)) \(definition.unit)."
        }
    }

    private func celebrationStyle(for definition: TrophyDefinition) -> TrophyCelebrationStyle {
        switch definition.rarity {
        case .common:
            return .standard
        case .rare, .epic:
            return .milestone
        case .legendary:
            return .legendary
        }
    }
}

@MainActor
final class TrophyStore: ObservableObject {
    @Published private(set) var snapshot: TrophyProgressSnapshot
    @Published private(set) var latestUnlockEvents: [TrophyUnlockEvent] = []
    @Published var persistenceError: String?

    private let fileURL: URL
    private let engine: TrophyEngine
    private let writeJournal: LocalWriteJournal
    private let decoder = JSONDecoder()
    private let persistenceActor: PersistenceActor
    private var currentAccountId: String?
    private var allProgress: [TrophyProgress] = []
    private var eventLog: [TrophyUnlockEvent] = []

    init(
        fileURL: URL? = nil,
        calendar: Calendar = .current,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let resolvedFileURL = fileURL ?? Self.defaultTrophyURL()
        self.fileURL = resolvedFileURL
        self.engine = TrophyEngine(calendar: calendar)
        self.writeJournal = writeJournal ?? LocalWriteJournal(
            fileURL: LocalWriteJournal.defaultJournalURL(alongside: resolvedFileURL),
            persistenceActor: persistenceActor
        )
        self.persistenceActor = persistenceActor
        self.currentAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.snapshot = engine.updateAll(
            history: [],
            calibrationStatus: .notStarted,
            previousSnapshot: nil
        ).snapshot
        decoder.dateDecodingStrategy = .iso8601
        loadSnapshot()
    }

    nonisolated deinit {}

    func setCurrentAccountId(_ accountId: String?) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        guard currentAccountId != normalizedAccountId else { return }
        currentAccountId = normalizedAccountId
        applyVisibleSnapshot()
    }

    func unlockEvents(for trophyId: String) -> [TrophyUnlockEvent] {
        visibleUnlockEvents()
            .filter { $0.trophyId == trophyId }
    }

    func allUnlockEvents() -> [TrophyUnlockEvent] {
        visibleUnlockEvents()
    }

    func unlockEvents(in interval: DateInterval) -> [TrophyUnlockEvent] {
        visibleUnlockEvents()
            .filter { interval.contains($0.authoritativeEarnedAt) }
    }

    @discardableResult
    func update(
        after summary: WorkoutSessionSummary,
        history: [WorkoutSessionSummary],
        calibrationStatus: CalibrationStatus,
        now: Date = Date(),
        operationId: UUID? = nil
    ) async -> [TrophyUnlockEvent] {
        let writeOperationId = operationId ?? UUID()
        guard !(await writeJournal.contains(operationId: writeOperationId)) else { return [] }

        let result = engine.update(
            after: summary,
            history: history,
            calibrationStatus: calibrationStatus,
            previousSnapshot: snapshot,
            canonicalUnlockEvents: visibleUnlockEvents(),
            now: now
        )
        return await apply(result, operationId: writeOperationId, createdAt: now)
            ? latestUnlockEvents
            : []
    }

    @discardableResult
    func updateAll(
        history: [WorkoutSessionSummary],
        calibrationStatus: CalibrationStatus,
        now: Date = Date(),
        operationId: UUID? = nil
    ) async -> [TrophyUnlockEvent] {
        let writeOperationId = operationId ?? UUID()
        guard !(await writeJournal.contains(operationId: writeOperationId)) else { return [] }

        let result = engine.updateAll(
            history: history,
            calibrationStatus: calibrationStatus,
            previousSnapshot: snapshot,
            canonicalUnlockEvents: visibleUnlockEvents(),
            now: now
        )
        return await apply(result, operationId: writeOperationId, createdAt: now)
            ? latestUnlockEvents
            : []
    }

    @discardableResult
    func recalculateForDebug(
        history: [WorkoutSessionSummary],
        calibrationStatus: CalibrationStatus,
        now: Date = Date(),
        operationId: UUID? = nil
    ) async -> Bool {
        let writeOperationId = operationId ?? UUID()
        guard !(await writeJournal.contains(operationId: writeOperationId)) else { return true }

        let previousSnapshot = snapshot
        let previousUnlockEvents = latestUnlockEvents
        let previousAllProgress = allProgress
        let previousEventLog = eventLog
        let result = engine.updateAll(
            history: history,
            calibrationStatus: calibrationStatus,
            previousSnapshot: nil,
            now: now
        )
        let rawProgressById = result.snapshot.progressByTrophyId
        let visibleActiveEvents = visibleUnlockEvents().filter { !$0.isRetracted }
        let retractedEvents = visibleActiveEvents.compactMap { event -> TrophyUnlockEvent? in
            guard rawProgressById[event.trophyId]?.earned != true else { return nil }
            return event.retracted(
                at: now,
                operationId: writeOperationId,
                now: now
            )
        }

        replaceUnlockEvents(retractedEvents)

        let canonicalResult = engine.updateAll(
            history: history,
            calibrationStatus: calibrationStatus,
            previousSnapshot: nil,
            canonicalUnlockEvents: visibleUnlockEvents(),
            now: now
        )
        let stampedProgress = canonicalResult.snapshot.progress.map {
            $0.withAccountId(currentAccountId, operationId: writeOperationId, now: now)
        }
        let newEvents = canonicalResult.newlyEarnedEvents.map {
            $0.withAccountId(currentAccountId, operationId: writeOperationId, now: now)
        }
        _ = mergeUnlockEventsIntoLog(newEvents)
        snapshot = TrophyProgressSnapshot(
            accountId: currentAccountId,
            catalogVersion: canonicalResult.snapshot.catalogVersion,
            generatedAt: canonicalResult.snapshot.generatedAt,
            progress: stampedProgress,
            unlockEventLog: visibleUnlockEvents(),
            newlyEarnedEvents: newEvents
        )
        mergeCurrentProgressIntoAll(stampedProgress)
        latestUnlockEvents = newEvents

        guard await persist() != nil else {
            allProgress = previousAllProgress
            eventLog = previousEventLog
            snapshot = previousSnapshot
            latestUnlockEvents = previousUnlockEvents
            return false
        }
        await recordWriteOperation(writeOperationId, createdAt: now)
        return true
    }

    @discardableResult
    func retractUnlockEvent(
        for trophyId: String,
        retractedAt: Date = Date(),
        operationId: UUID? = nil
    ) async -> Bool {
        let writeOperationId = operationId ?? UUID()
        guard !(await writeJournal.contains(operationId: writeOperationId)) else { return true }

        let activeEvents = visibleUnlockEvents()
            .filter { $0.trophyId == trophyId && !$0.isRetracted }
        guard !activeEvents.isEmpty else { return true }

        let previousSnapshot = snapshot
        let previousUnlockEvents = latestUnlockEvents
        let previousEventLog = eventLog

        replaceUnlockEvents(
            activeEvents.map {
                $0.retracted(
                    at: retractedAt,
                    operationId: writeOperationId,
                    now: retractedAt
                )
            }
        )
        latestUnlockEvents.removeAll { $0.trophyId == trophyId }
        applyVisibleSnapshot(generatedAt: retractedAt, events: latestUnlockEvents)

        guard await persist() != nil else {
            eventLog = previousEventLog
            snapshot = previousSnapshot
            latestUnlockEvents = previousUnlockEvents
            return false
        }
        await recordWriteOperation(writeOperationId, createdAt: retractedAt)
        return true
    }

    func clearLatestUnlockEvents() {
        latestUnlockEvents = []
        snapshot = TrophyProgressSnapshot(
            accountId: currentAccountId,
            catalogVersion: snapshot.catalogVersion,
            generatedAt: snapshot.generatedAt,
            progress: snapshot.progress,
            unlockEventLog: visibleUnlockEvents(),
            newlyEarnedEvents: []
        )
    }

    func reload() {
        loadSnapshot()
    }

    @discardableResult
    func claimLocalDataForAccount(id accountId: String, operationId: UUID? = nil) async -> Bool {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            persistenceError = "Account id is required before local trophy data can be claimed."
            return false
        }
        guard allProgress.contains(where: { $0.accountId == nil }) ||
                eventLog.contains(where: { $0.accountId == nil })
        else { return true }

        let writeOperationId = operationId ?? UUID()
        guard !(await writeJournal.contains(operationId: writeOperationId)) else { return true }

        let writeCreatedAt = Date()
        let previousAllProgress = allProgress
        let previousEventLog = eventLog
        allProgress = dedupedProgressByStorageKey(
            allProgress.map { progress in
                progress.accountId == nil
                    ? progress.withAccountId(
                        normalizedAccountId,
                        operationId: writeOperationId,
                        now: writeCreatedAt
                    )
                    : progress
            }
        )
        eventLog = dedupedUnlockEventsByStorageKey(
            eventLog.map { event in
                event.accountId == nil
                    ? event.withAccountId(
                        normalizedAccountId,
                        operationId: writeOperationId,
                        now: writeCreatedAt
                    )
                    : event
            }
        )
        applyVisibleSnapshot()

        guard await persist() != nil else {
            allProgress = previousAllProgress
            eventLog = previousEventLog
            applyVisibleSnapshot()
            return false
        }
        await recordWriteOperation(writeOperationId, createdAt: writeCreatedAt)
        return true
    }

    @discardableResult
    private func apply(
        _ result: TrophyEngineResult,
        operationId: UUID,
        createdAt: Date
    ) async -> Bool {
        let previousSnapshot = snapshot
        let previousUnlockEvents = latestUnlockEvents
        let previousAllProgress = allProgress
        let previousEventLog = eventLog
        let stampedProgress = result.snapshot.progress.map {
            $0.withAccountId(currentAccountId, operationId: operationId, now: createdAt)
        }
        let stampedEvents = result.newlyEarnedEvents.map {
            $0.withAccountId(currentAccountId, operationId: operationId, now: createdAt)
        }
        mergeCurrentProgressIntoAll(stampedProgress)
        let canonicalNewEvents = mergeUnlockEventsIntoLog(stampedEvents)
        snapshot = TrophyProgressSnapshot(
            accountId: currentAccountId,
            catalogVersion: result.snapshot.catalogVersion,
            generatedAt: result.snapshot.generatedAt,
            progress: visibleProgress(fallbackGeneratedAt: result.snapshot.generatedAt),
            unlockEventLog: visibleUnlockEvents(),
            newlyEarnedEvents: canonicalNewEvents
        )
        latestUnlockEvents = canonicalNewEvents
        guard await persist() != nil else {
            allProgress = previousAllProgress
            eventLog = previousEventLog
            snapshot = previousSnapshot
            latestUnlockEvents = previousUnlockEvents
            return false
        }
        await recordWriteOperation(operationId, createdAt: createdAt)
        return true
    }

    private func recordWriteOperation(_ operationId: UUID, createdAt: Date) async {
        _ = await writeJournal.record(
            operationId: operationId,
            entityKind: .trophyEvent,
            createdAt: createdAt
        )
    }

    private func loadSnapshot() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            allProgress = []
            eventLog = []
            applyVisibleSnapshot(events: [])
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let persistedSnapshot = try decoder.decode(TrophyProgressSnapshot.self, from: data)
            allProgress = dedupedProgressByStorageKey(persistedSnapshot.progress)
            eventLog = dedupedUnlockEventsByStorageKey(
                persistedSnapshot.unlockEventLog +
                    legacyUnlockEvents(from: persistedSnapshot, excluding: persistedSnapshot.unlockEventLog)
            )
            applyVisibleSnapshot(generatedAt: persistedSnapshot.generatedAt, events: [])
            persistenceError = nil
        } catch {
            persistenceError = "Could not load trophies: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func persist() async -> PersistenceWriteOutcome? {
        do {
            let persistedSnapshot = TrophyProgressSnapshot(
                accountId: nil,
                catalogVersion: snapshot.catalogVersion,
                generatedAt: snapshot.generatedAt,
                progress: dedupedProgressByStorageKey(allProgress),
                unlockEventLog: dedupedUnlockEventsByStorageKey(eventLog),
                newlyEarnedEvents: []
            )
            let data = try await persistenceActor.encode(
                persistedSnapshot,
                outputFormatting: [.prettyPrinted, .sortedKeys]
            )
            let outcome = try await persistenceActor.writeLatest(data, to: fileURL, options: [.atomic])
            persistenceError = nil
            return outcome
        } catch {
            persistenceError = "Could not save trophies: \(error.localizedDescription)"
            return nil
        }
    }

    private func mergeCurrentProgressIntoAll(_ progress: [TrophyProgress]) {
        let accountId = currentAccountId
        allProgress.removeAll {
            AccountOwnership.normalizedAccountId($0.accountId) == accountId
        }
        allProgress.append(contentsOf: progress)
        allProgress = dedupedProgressByStorageKey(allProgress)
    }

    private func applyVisibleSnapshot(
        generatedAt: Date? = nil,
        events: [TrophyUnlockEvent]? = nil
    ) {
        snapshot = TrophyProgressSnapshot(
            accountId: currentAccountId,
            catalogVersion: TrophyDefinitionCatalog.version,
            generatedAt: generatedAt ?? snapshot.generatedAt,
            progress: visibleProgress(fallbackGeneratedAt: generatedAt ?? snapshot.generatedAt),
            unlockEventLog: visibleUnlockEvents(),
            newlyEarnedEvents: events ?? latestUnlockEvents.filter(isVisible)
        )
        latestUnlockEvents = snapshot.newlyEarnedEvents
    }

    private func visibleProgress(fallbackGeneratedAt: Date) -> [TrophyProgress] {
        let visibleProgress = allProgress.filter(isVisible)
        guard !visibleProgress.isEmpty else {
            return engine.updateAll(
                history: [],
                calibrationStatus: .notStarted,
                previousSnapshot: nil,
                canonicalUnlockEvents: visibleUnlockEvents(),
                now: fallbackGeneratedAt
            ).snapshot.progress.map { $0.withAccountId(currentAccountId) }
        }

        let progressById = TrophyProgressSnapshot(
            accountId: currentAccountId,
            catalogVersion: TrophyDefinitionCatalog.version,
            generatedAt: fallbackGeneratedAt,
            progress: visibleProgress,
            unlockEventLog: visibleUnlockEvents(),
            newlyEarnedEvents: []
        ).progressByTrophyId

        let eventStateById = visibleUnlockEventStateByTrophyId()

        return TrophyDefinitionCatalog.all.compactMap { definition in
            guard let progress = progressById[definition.id] else { return nil }
            guard !definition.isComingSoon else { return progress }

            if let activeEvent = eventStateById[definition.id]?.activeEvent {
                return progressWithCanonicalUnlock(progress, event: activeEvent)
            }

            if eventStateById[definition.id]?.isTombstoned == true {
                return progressWithRetraction(progress)
            }

            return progress
        }
    }

    private struct StoreUnlockEventState {
        let activeEvent: TrophyUnlockEvent?
        let hasRetraction: Bool

        var isTombstoned: Bool {
            activeEvent == nil && hasRetraction
        }
    }

    @discardableResult
    private func mergeUnlockEventsIntoLog(_ events: [TrophyUnlockEvent]) -> [TrophyUnlockEvent] {
        guard !events.isEmpty else { return [] }
        eventLog.append(contentsOf: events)
        eventLog = dedupedUnlockEventsByStorageKey(eventLog)

        let eventIds = Set(eventLog.map(\.id))
        return events.filter { eventIds.contains($0.id) && !$0.isRetracted }
    }

    private func replaceUnlockEvents(_ events: [TrophyUnlockEvent]) {
        guard !events.isEmpty else { return }

        let replacementIds = Set(events.map(\.id))
        eventLog.removeAll { replacementIds.contains($0.id) }
        eventLog.append(contentsOf: events)
        eventLog = dedupedUnlockEventsByStorageKey(eventLog)
    }

    private func visibleUnlockEvents() -> [TrophyUnlockEvent] {
        eventLog
            .filter(isVisible)
            .sorted(by: isEarlierUnlockEvent)
    }

    private func visibleUnlockEventStateByTrophyId() -> [String: StoreUnlockEventState] {
        Dictionary(grouping: visibleUnlockEvents(), by: \.trophyId).mapValues { events in
            StoreUnlockEventState(
                activeEvent: events.filter { !$0.isRetracted }.min(by: isEarlierUnlockEvent),
                hasRetraction: events.contains(where: \.isRetracted)
            )
        }
    }

    private func progressWithCanonicalUnlock(
        _ progress: TrophyProgress,
        event: TrophyUnlockEvent
    ) -> TrophyProgress {
        TrophyProgress(
            trophyId: progress.trophyId,
            currentValue: max(progress.currentValue, progress.targetValue),
            targetValue: progress.targetValue,
            earned: true,
            earnedAt: event.authoritativeEarnedAt,
            lastUpdatedAt: progress.lastUpdatedAt,
            confidence: progress.confidence,
            progressLabel: "Earned",
            accountId: progress.accountId,
            syncMetadata: progress.syncMetadata
        )
    }

    private func progressWithRetraction(_ progress: TrophyProgress) -> TrophyProgress {
        TrophyProgress(
            trophyId: progress.trophyId,
            currentValue: min(progress.currentValue, progress.targetValue),
            targetValue: progress.targetValue,
            earned: false,
            earnedAt: nil,
            lastUpdatedAt: progress.lastUpdatedAt,
            confidence: progress.confidence,
            progressLabel: progress.progressLabel == "Earned" ? "Retracted" : progress.progressLabel,
            accountId: progress.accountId,
            syncMetadata: progress.syncMetadata
        )
    }

    private func legacyUnlockEvents(
        from snapshot: TrophyProgressSnapshot,
        excluding existingEvents: [TrophyUnlockEvent]
    ) -> [TrophyUnlockEvent] {
        let existingStorageKeys = Set(
            existingEvents.map {
                AccountOwnership.storageKey(accountId: $0.accountId, recordId: $0.trophyId)
            }
        )

        return snapshot.progress.compactMap { progress in
            guard progress.earned,
                  !existingStorageKeys.contains(
                    AccountOwnership.storageKey(accountId: progress.accountId, recordId: progress.trophyId)
                  ),
                  let earnedAt = progress.earnedAt,
                  let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId),
                  !definition.isComingSoon
            else { return nil }

            return TrophyUnlockEvent(
                accountId: progress.accountId,
                trophyId: definition.id,
                title: definition.title,
                subtitle: definition.subtitle,
                earnedAt: earnedAt,
                reason: unlockReason(for: definition, progress: progress),
                celebrationStyle: celebrationStyle(for: definition),
                syncMetadata: progress.syncMetadata
            )
        }
    }

    private func dedupedUnlockEventsByStorageKey(_ events: [TrophyUnlockEvent]) -> [TrophyUnlockEvent] {
        let operationDeduped = Dictionary(grouping: events, by: operationDedupeStorageKey)
            .values
            .compactMap(preferredUnlockEvent)

        return Dictionary(grouping: operationDeduped, by: trophyEventStorageKey)
            .values
            .compactMap(preferredUnlockEvent)
            .sorted(by: isEarlierUnlockEvent)
    }

    private func operationDedupeStorageKey(for event: TrophyUnlockEvent) -> String {
        let recordId = event.syncMetadata.pendingOperationId.map {
            "\(event.trophyId)|operation|\($0.uuidString)"
        } ?? "\(event.trophyId)|dedupe|\(event.dedupeKey)"
        return AccountOwnership.storageKey(accountId: event.accountId, recordId: recordId)
    }

    private func trophyEventStorageKey(for event: TrophyUnlockEvent) -> String {
        AccountOwnership.storageKey(accountId: event.accountId, recordId: event.trophyId)
    }

    private func preferredUnlockEvent(_ events: [TrophyUnlockEvent]) -> TrophyUnlockEvent? {
        events.min { lhs, rhs in
            if lhs.isRetracted != rhs.isRetracted {
                return lhs.isRetracted
            }
            if lhs.isRetracted, rhs.isRetracted,
               lhs.syncMetadata.localUpdatedAt != rhs.syncMetadata.localUpdatedAt {
                return lhs.syncMetadata.localUpdatedAt > rhs.syncMetadata.localUpdatedAt
            }
            return isEarlierUnlockEvent(lhs, rhs)
        }
    }

    private func isEarlierUnlockEvent(_ lhs: TrophyUnlockEvent, _ rhs: TrophyUnlockEvent) -> Bool {
        let leftSortOrder = TrophyDefinitionCatalog.definition(for: lhs.trophyId)?.sortOrder ?? 0
        let rightSortOrder = TrophyDefinitionCatalog.definition(for: rhs.trophyId)?.sortOrder ?? 0
        if leftSortOrder != rightSortOrder {
            return leftSortOrder < rightSortOrder
        }
        if lhs.authoritativeEarnedAt != rhs.authoritativeEarnedAt {
            return lhs.authoritativeEarnedAt < rhs.authoritativeEarnedAt
        }
        if lhs.earnedAt != rhs.earnedAt {
            return lhs.earnedAt < rhs.earnedAt
        }
        if (lhs.accountId ?? "") != (rhs.accountId ?? "") {
            return (lhs.accountId ?? "") < (rhs.accountId ?? "")
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func unlockReason(
        for definition: TrophyDefinition,
        progress: TrophyProgress
    ) -> String {
        switch definition.unlockRule.kind {
        case .firstSavedWorkout:
            return "You saved your first workout."
        case .calibrationCompleted:
            return "Calibration is complete."
        case .allEligibleNonComingSoonTrophies:
            return "Every currently supported trophy is earned."
        default:
            return "You reached \(format(progress.targetValue)) \(definition.unit)."
        }
    }

    private func celebrationStyle(for definition: TrophyDefinition) -> TrophyCelebrationStyle {
        switch definition.rarity {
        case .common:
            return .standard
        case .rare, .epic:
            return .milestone
        case .legendary:
            return .legendary
        }
    }

    private func format(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private func dedupedProgressByStorageKey(_ progress: [TrophyProgress]) -> [TrophyProgress] {
        let groupedProgress = Dictionary(grouping: progress) {
            AccountOwnership.storageKey(accountId: $0.accountId, recordId: $0.trophyId)
        }
        return groupedProgress.values.flatMap { entries in
            TrophyProgressSnapshot(
                catalogVersion: TrophyDefinitionCatalog.version,
                generatedAt: entries.map(\.lastUpdatedAt).max() ?? Date(),
                progress: entries,
                newlyEarnedEvents: []
            ).progressByTrophyId.values
        }
        .sorted {
            let leftSortOrder = TrophyDefinitionCatalog.definition(for: $0.trophyId)?.sortOrder ?? 0
            let rightSortOrder = TrophyDefinitionCatalog.definition(for: $1.trophyId)?.sortOrder ?? 0
            if leftSortOrder == rightSortOrder {
                return ($0.accountId ?? "") < ($1.accountId ?? "")
            }
            return leftSortOrder < rightSortOrder
        }
    }

    private func isVisible(_ progress: TrophyProgress) -> Bool {
        AccountOwnership.isVisible(
            recordAccountId: progress.accountId,
            currentAccountId: currentAccountId
        )
    }

    private func isVisible(_ event: TrophyUnlockEvent) -> Bool {
        AccountOwnership.isVisible(
            recordAccountId: event.accountId,
            currentAccountId: currentAccountId
        )
    }

    private static func defaultTrophyURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("TrophyProgress.json")
    }
}
