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

    var progressFraction: Double {
        guard targetValue > 0 else { return earned ? 1 : 0 }
        return min(max(currentValue / targetValue, 0), 1)
    }
}

nonisolated struct TrophyUnlockEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let trophyId: String
    let title: String
    let subtitle: String
    let earnedAt: Date
    let reason: String
    let celebrationStyle: TrophyCelebrationStyle

    init(
        id: UUID = UUID(),
        trophyId: String,
        title: String,
        subtitle: String,
        earnedAt: Date,
        reason: String,
        celebrationStyle: TrophyCelebrationStyle
    ) {
        self.id = id
        self.trophyId = trophyId
        self.title = title
        self.subtitle = subtitle
        self.earnedAt = earnedAt
        self.reason = reason
        self.celebrationStyle = celebrationStyle
    }
}

nonisolated struct TrophyProgressSnapshot: Codable, Equatable {
    let catalogVersion: Int
    let generatedAt: Date
    let progress: [TrophyProgress]
    let newlyEarnedEvents: [TrophyUnlockEvent]

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
        now: Date = Date()
    ) -> TrophyEngineResult {
        updateAll(
            history: history.contains(where: { $0.id == summary.id }) ? history : history + [summary],
            calibrationStatus: calibrationStatus,
            previousSnapshot: previousSnapshot,
            now: now
        )
    }

    func updateAll(
        history: [WorkoutSessionSummary],
        calibrationStatus: CalibrationStatus,
        previousSnapshot: TrophyProgressSnapshot? = nil,
        now: Date = Date()
    ) -> TrophyEngineResult {
        let sortedHistory = history.sorted {
            if $0.endedAt == $1.endedAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.endedAt < $1.endedAt
        }
        let previousById = previousSnapshot?.progressByTrophyId ?? [:]
        var mergedById: [String: TrophyProgress] = [:]

        for definition in TrophyDefinitionCatalog.all where definition.unlockRule.kind != .allEligibleNonComingSoonTrophies {
            let computed = computeProgress(
                for: definition,
                history: sortedHistory,
                calibrationStatus: calibrationStatus,
                previous: previousById[definition.id],
                now: now
            )
            mergedById[definition.id] = merge(
                computed: computed,
                previous: previousById[definition.id],
                definition: definition,
                now: now
            )
        }

        for definition in TrophyDefinitionCatalog.capstoneDefinitions {
            let computed = computeCapstoneProgress(
                for: definition,
                regularProgressById: mergedById,
                previous: previousById[definition.id],
                now: now
            )
            mergedById[definition.id] = merge(
                computed: computed,
                previous: previousById[definition.id],
                definition: definition,
                now: now
            )
        }

        let orderedProgress = TrophyDefinitionCatalog.all.compactMap { mergedById[$0.id] }
        let events = newlyEarnedEvents(
            previousById: previousById,
            currentProgress: orderedProgress,
            now: now
        )
        let snapshot = TrophyProgressSnapshot(
            catalogVersion: TrophyDefinitionCatalog.version,
            generatedAt: now,
            progress: orderedProgress,
            newlyEarnedEvents: events
        )

        return TrophyEngineResult(snapshot: snapshot, newlyEarnedEvents: events)
    }

    private func computeProgress(
        for definition: TrophyDefinition,
        history: [WorkoutSessionSummary],
        calibrationStatus: CalibrationStatus,
        previous: TrophyProgress?,
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
        let earned = metric.value >= target && target > 0

        return TrophyProgress(
            trophyId: definition.id,
            currentValue: min(metric.value, target),
            targetValue: target,
            earned: earned,
            earnedAt: earned ? (previous?.earnedAt ?? now) : nil,
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
        previous: TrophyProgress?,
        now: Date
    ) -> TrophyProgress {
        let eligibleDefinitions = TrophyDefinitionCatalog.regularEligibleDefinitions
        let target = Double(eligibleDefinitions.count)
        let earnedCount = eligibleDefinitions.reduce(0) { count, definition in
            count + ((regularProgressById[definition.id]?.earned == true) ? 1 : 0)
        }
        let earned = target > 0 && Double(earnedCount) >= target

        return TrophyProgress(
            trophyId: definition.id,
            currentValue: Double(earnedCount),
            targetValue: target,
            earned: earned,
            earnedAt: earned ? (previous?.earnedAt ?? now) : nil,
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

    private func merge(
        computed: TrophyProgress,
        previous: TrophyProgress?,
        definition: TrophyDefinition,
        now: Date
    ) -> TrophyProgress {
        guard !definition.isComingSoon,
              let previous,
              previous.earned
        else { return computed }

        return TrophyProgress(
            trophyId: computed.trophyId,
            currentValue: max(computed.currentValue, computed.targetValue),
            targetValue: computed.targetValue,
            earned: true,
            earnedAt: previous.earnedAt ?? computed.earnedAt ?? now,
            lastUpdatedAt: now,
            confidence: computed.confidence,
            progressLabel: "Earned"
        )
    }

    private func newlyEarnedEvents(
        previousById: [String: TrophyProgress],
        currentProgress: [TrophyProgress],
        now: Date
    ) -> [TrophyUnlockEvent] {
        currentProgress.compactMap { progress in
            guard progress.earned,
                  previousById[progress.trophyId]?.earned != true,
                  let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId),
                  !definition.isComingSoon
            else { return nil }

            return TrophyUnlockEvent(
                trophyId: definition.id,
                title: definition.title,
                subtitle: definition.subtitle,
                earnedAt: progress.earnedAt ?? now,
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
        Set(history.map { calendar.startOfDay(for: $0.endedAt) })
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
            let weekday = calendar.component(.weekday, from: summary.endedAt)
            guard weekday == 1 || weekday == 7 else { return }

            let weekendAnchor = weekday == 1
                ? calendar.date(byAdding: .day, value: -1, to: summary.endedAt) ?? summary.endedAt
                : summary.endedAt
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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil, calendar: Calendar = .current) {
        self.fileURL = fileURL ?? Self.defaultTrophyURL()
        self.engine = TrophyEngine(calendar: calendar)
        self.snapshot = engine.updateAll(
            history: [],
            calibrationStatus: .notStarted,
            previousSnapshot: nil
        ).snapshot
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadSnapshot()
    }

    nonisolated deinit {}

    @discardableResult
    func update(
        after summary: WorkoutSessionSummary,
        history: [WorkoutSessionSummary],
        calibrationStatus: CalibrationStatus,
        now: Date = Date()
    ) -> [TrophyUnlockEvent] {
        let result = engine.update(
            after: summary,
            history: history,
            calibrationStatus: calibrationStatus,
            previousSnapshot: snapshot,
            now: now
        )
        apply(result)
        return result.newlyEarnedEvents
    }

    @discardableResult
    func updateAll(
        history: [WorkoutSessionSummary],
        calibrationStatus: CalibrationStatus,
        now: Date = Date()
    ) -> [TrophyUnlockEvent] {
        let result = engine.updateAll(
            history: history,
            calibrationStatus: calibrationStatus,
            previousSnapshot: snapshot,
            now: now
        )
        apply(result)
        return result.newlyEarnedEvents
    }

    func clearLatestUnlockEvents() {
        latestUnlockEvents = []
        snapshot = TrophyProgressSnapshot(
            catalogVersion: snapshot.catalogVersion,
            generatedAt: snapshot.generatedAt,
            progress: snapshot.progress,
            newlyEarnedEvents: []
        )
    }

    func reload() {
        loadSnapshot()
    }

    private func apply(_ result: TrophyEngineResult) {
        snapshot = result.snapshot
        latestUnlockEvents = result.newlyEarnedEvents
        persist()
    }

    private func loadSnapshot() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            snapshot = try decoder.decode(TrophyProgressSnapshot.self, from: data)
            latestUnlockEvents = []
            persistenceError = nil
        } catch {
            persistenceError = "Could not load trophies: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let persistedSnapshot = TrophyProgressSnapshot(
                catalogVersion: snapshot.catalogVersion,
                generatedAt: snapshot.generatedAt,
                progress: snapshot.progress,
                newlyEarnedEvents: []
            )
            let data = try encoder.encode(persistedSnapshot)
            try data.write(to: fileURL, options: [.atomic])
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Could not save trophies: \(error.localizedDescription)"
            return false
        }
    }

    private static func defaultTrophyURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("TrophyProgress.json")
    }
}
