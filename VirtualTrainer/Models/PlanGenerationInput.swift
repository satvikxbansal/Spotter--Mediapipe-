import Foundation

nonisolated enum PlanSessionLength: Int, Codable, CaseIterable, Identifiable, Hashable {
    case seven = 7
    case fifteen = 15
    case twentyFive = 25
    case thirtyFive = 35

    var id: Int { rawValue }

    init(rawMinutes: Int) {
        switch rawMinutes {
        case 7:
            self = .seven
        case 15:
            self = .fifteen
        case 25:
            self = .twentyFive
        case 35:
            self = .thirtyFive
        default:
            self = .fifteen
        }
    }

    var maxExercises: Int {
        switch self {
        case .seven:
            return 4
        case .fifteen:
            return 5
        case .twentyFive:
            return 7
        case .thirtyFive:
            return 8
        }
    }

    var maxCameraSwitches: Int {
        switch self {
        case .seven:
            return 0
        case .fifteen:
            return 1
        case .twentyFive, .thirtyFive:
            return 2
        }
    }

    var mainSetCount: Int {
        switch self {
        case .seven:
            return 1
        case .fifteen, .twentyFive:
            return 2
        case .thirtyFive:
            return 3
        }
    }
}

nonisolated struct RecentWorkoutHistoryItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let exerciseType: ExerciseType
    let completedAt: Date

    init(
        id: UUID = UUID(),
        exerciseType: ExerciseType,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.exerciseType = exerciseType
        self.completedAt = completedAt
    }
}

nonisolated struct PlanGenerationInput: Codable, Equatable {
    let profile: UserProfile
    let goal: FitnessGoal
    let fitnessLevel: FitnessLevel
    let ageBracket: AgeBracket
    let equipment: Set<EquipmentOption>
    let sessionLength: PlanSessionLength
    let preferredCoach: CoachPreference
    let recentWorkoutHistory: [RecentWorkoutHistoryItem]
    let excludedExercises: Set<ExerciseType>
    let focusBodyRegions: Set<BodyRegion>
    let focusMovementPatterns: Set<MovementPattern>
    let variantSeed: String?

    var effectiveEquipment: Set<EquipmentOption> {
        var effective = equipment
        effective.insert(.bodyweight)
        return effective
    }

    init(
        profile: UserProfile,
        goal: FitnessGoal? = nil,
        fitnessLevel: FitnessLevel? = nil,
        sessionLength: PlanSessionLength = .twentyFive,
        recentWorkoutHistory: [RecentWorkoutHistoryItem] = [],
        excludedExercises: Set<ExerciseType> = [],
        focusBodyRegions: Set<BodyRegion> = [],
        focusMovementPatterns: Set<MovementPattern> = [],
        variantSeed: String? = nil
    ) {
        self.profile = profile
        self.goal = goal ?? profile.primaryGoal
        self.fitnessLevel = fitnessLevel ?? profile.fitnessLevel
        self.ageBracket = profile.ageBracket
        self.equipment = Set(profile.equipment)
        self.sessionLength = sessionLength
        self.preferredCoach = profile.preferredCoach
        self.recentWorkoutHistory = recentWorkoutHistory
        self.excludedExercises = excludedExercises
        self.focusBodyRegions = focusBodyRegions
        self.focusMovementPatterns = focusMovementPatterns
        self.variantSeed = variantSeed
    }

    init(
        profile: UserProfile,
        goal: FitnessGoal? = nil,
        fitnessLevel: FitnessLevel? = nil,
        sessionLengthMinutes: Int,
        recentWorkoutHistory: [RecentWorkoutHistoryItem] = [],
        excludedExercises: Set<ExerciseType> = [],
        focusBodyRegions: Set<BodyRegion> = [],
        focusMovementPatterns: Set<MovementPattern> = [],
        variantSeed: String? = nil
    ) {
        self.init(
            profile: profile,
            goal: goal,
            fitnessLevel: fitnessLevel,
            sessionLength: PlanSessionLength(rawMinutes: sessionLengthMinutes),
            recentWorkoutHistory: recentWorkoutHistory,
            excludedExercises: excludedExercises,
            focusBodyRegions: focusBodyRegions,
            focusMovementPatterns: focusMovementPatterns,
            variantSeed: variantSeed
        )
    }
}
