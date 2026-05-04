import Foundation

nonisolated enum ExerciseDifficulty: String, Codable, CaseIterable, Hashable {
    case beginner
    case intermediate
    case advanced
}

nonisolated enum MovementPattern: String, Codable, CaseIterable, Hashable {
    case squat
    case hinge
    case lunge
    case push
    case pull
    case carry
    case coreFlexion
    case coreAntiExtension
    case coreRotation
    case balance
    case mobility
    case cardio
    case yogaHold
}

nonisolated enum BodyRegion: String, Codable, CaseIterable, Hashable {
    case upper
    case lower
    case core
    case fullBody
    case mobility
}

nonisolated enum PlanTag: String, Codable, CaseIterable, Hashable {
    case strength
    case performance
    case longevity
    case warmup
    case finisher
    case lowImpact
    case highImpact
    case beginnerFriendly
    case dumbbell
    case bodyweight
    case isometric
}

nonisolated enum ContraindicationTag: String, Codable, CaseIterable, Hashable {
    case kneeSensitive
    case shoulderSensitive
    case wristSensitive
    case lowerBackSensitive
    case highImpact
}

/// Product metadata used by future workout planning.
/// ExerciseLibrary remains the source of truth for biomechanics and tracking.
nonisolated struct ExercisePlanMetadata: Codable, Equatable, Identifiable {
    var id: ExerciseType { exerciseType }

    let exerciseType: ExerciseType
    let difficulty: ExerciseDifficulty?
    let requiredEquipment: Set<EquipmentOption>
    let optionalEquipment: Set<EquipmentOption>
    let movementPattern: MovementPattern
    let bodyRegion: BodyRegion
    let planTags: Set<PlanTag>
    let contraindicationTags: Set<ContraindicationTag>
    let supportsFreeAnalysis: Bool
    let supportsPlannedWorkout: Bool

    /// Reps for repetition exercises, seconds for isometric holds.
    let defaultRestSeconds: Int
    let defaultBeginnerTarget: Int
    let defaultIntermediateTarget: Int
}
