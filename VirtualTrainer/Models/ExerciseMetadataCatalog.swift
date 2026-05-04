import Foundation

nonisolated enum ExerciseMetadataCatalog {
    static let all: [ExercisePlanMetadata] = [
        // Lower Body
        entry(
            .squat,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.dumbbells],
            pattern: .squat,
            region: .lower,
            tags: [.strength, .longevity, .lowImpact, .beginnerFriendly, .bodyweight],
            contraindications: [.kneeSensitive],
            rest: 60,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .sumoSquat,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.dumbbells],
            pattern: .squat,
            region: .lower,
            tags: [.strength, .longevity, .lowImpact, .beginnerFriendly, .bodyweight],
            contraindications: [.kneeSensitive],
            rest: 60,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .lunge,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.dumbbells],
            pattern: .lunge,
            region: .lower,
            tags: [.strength, .performance, .lowImpact, .bodyweight],
            contraindications: [.kneeSensitive],
            rest: 60,
            beginnerTarget: 6,
            intermediateTarget: 10
        ),
        entry(
            .sideLunge,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.dumbbells],
            pattern: .lunge,
            region: .lower,
            tags: [.strength, .performance, .warmup, .lowImpact, .bodyweight],
            contraindications: [.kneeSensitive],
            rest: 60,
            beginnerTarget: 6,
            intermediateTarget: 10
        ),
        entry(
            .gluteBridge,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.mat, .dumbbells],
            pattern: .hinge,
            region: .lower,
            tags: [.strength, .longevity, .lowImpact, .beginnerFriendly, .bodyweight],
            rest: 45,
            beginnerTarget: 10,
            intermediateTarget: 15
        ),
        entry(
            .hipAbduction,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.chair],
            pattern: .balance,
            region: .lower,
            tags: [.strength, .longevity, .warmup, .lowImpact, .beginnerFriendly, .bodyweight],
            rest: 30,
            beginnerTarget: 10,
            intermediateTarget: 15
        ),
        entry(
            .legRaise,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .coreFlexion,
            region: .core,
            tags: [.strength, .lowImpact, .bodyweight],
            contraindications: [.lowerBackSensitive],
            rest: 45,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .wallSit,
            difficulty: .beginner,
            required: [.bodyweight, .wall],
            pattern: .squat,
            region: .lower,
            tags: [.strength, .longevity, .lowImpact, .beginnerFriendly, .bodyweight, .isometric],
            contraindications: [.kneeSensitive],
            rest: 60,
            beginnerTarget: 20,
            intermediateTarget: 45
        ),
        entry(
            .deadlift,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.dumbbells, .kettlebell],
            pattern: .hinge,
            region: .lower,
            tags: [.strength, .performance, .lowImpact, .bodyweight],
            contraindications: [.lowerBackSensitive],
            rest: 75,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .calfRaise,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.dumbbells, .wall],
            pattern: .balance,
            region: .lower,
            tags: [.strength, .longevity, .warmup, .lowImpact, .beginnerFriendly, .bodyweight],
            rest: 30,
            beginnerTarget: 12,
            intermediateTarget: 20
        ),
        entry(
            .romanianDeadlift,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.dumbbells, .kettlebell],
            pattern: .hinge,
            region: .lower,
            tags: [.strength, .performance, .lowImpact, .bodyweight],
            contraindications: [.lowerBackSensitive],
            rest: 75,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .chairSitToStand,
            difficulty: .beginner,
            required: [.bodyweight, .chair],
            pattern: .squat,
            region: .lower,
            tags: [.strength, .longevity, .lowImpact, .beginnerFriendly, .bodyweight],
            contraindications: [.kneeSensitive],
            rest: 45,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .hipThrust,
            difficulty: .intermediate,
            required: [.bodyweight, .bench],
            optional: [.dumbbells],
            pattern: .hinge,
            region: .lower,
            tags: [.strength, .performance, .lowImpact, .bodyweight],
            rest: 60,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .reverseLunge,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.dumbbells],
            pattern: .lunge,
            region: .lower,
            tags: [.strength, .performance, .lowImpact, .bodyweight],
            contraindications: [.kneeSensitive],
            rest: 60,
            beginnerTarget: 6,
            intermediateTarget: 10
        ),
        entry(
            .stepUp,
            difficulty: .intermediate,
            required: [.bodyweight, .step],
            optional: [.dumbbells, .bench],
            pattern: .lunge,
            region: .lower,
            tags: [.strength, .performance, .lowImpact, .bodyweight],
            contraindications: [.kneeSensitive],
            rest: 60,
            beginnerTarget: 6,
            intermediateTarget: 10
        ),
        entry(
            .donkeyKick,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .hinge,
            region: .lower,
            tags: [.strength, .longevity, .lowImpact, .beginnerFriendly, .bodyweight],
            rest: 45,
            beginnerTarget: 10,
            intermediateTarget: 15
        ),

        // Upper Body
        entry(
            .bicepCurl,
            difficulty: .beginner,
            required: [.dumbbells],
            pattern: .pull,
            region: .upper,
            tags: [.strength, .lowImpact, .beginnerFriendly, .dumbbell],
            rest: 45,
            beginnerTarget: 10,
            intermediateTarget: 12
        ),
        entry(
            .pushup,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .push,
            region: .upper,
            tags: [.strength, .performance, .lowImpact, .bodyweight],
            contraindications: [.shoulderSensitive, .wristSensitive],
            rest: 60,
            beginnerTarget: 6,
            intermediateTarget: 12
        ),
        entry(
            .lateralRaise,
            difficulty: .intermediate,
            required: [.dumbbells],
            pattern: .push,
            region: .upper,
            tags: [.strength, .lowImpact, .dumbbell],
            contraindications: [.shoulderSensitive],
            rest: 45,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .frontRaise,
            difficulty: .intermediate,
            required: [.dumbbells],
            pattern: .push,
            region: .upper,
            tags: [.strength, .lowImpact, .dumbbell],
            contraindications: [.shoulderSensitive, .lowerBackSensitive],
            rest: 45,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .overheadPress,
            difficulty: .intermediate,
            required: [.dumbbells],
            pattern: .push,
            region: .upper,
            tags: [.strength, .performance, .lowImpact, .dumbbell],
            contraindications: [.shoulderSensitive, .lowerBackSensitive],
            rest: 60,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .cobraWings,
            difficulty: .beginner,
            required: [.bodyweight],
            pattern: .mobility,
            region: .upper,
            tags: [.longevity, .warmup, .lowImpact, .beginnerFriendly, .bodyweight],
            contraindications: [.shoulderSensitive],
            rest: 30,
            beginnerTarget: 10,
            intermediateTarget: 15
        ),
        entry(
            .overarmReach,
            difficulty: .beginner,
            required: [.bodyweight],
            pattern: .mobility,
            region: .upper,
            tags: [.longevity, .warmup, .lowImpact, .beginnerFriendly, .bodyweight],
            contraindications: [.shoulderSensitive],
            rest: 30,
            beginnerTarget: 10,
            intermediateTarget: 15
        ),
        entry(
            .hammerCurl,
            difficulty: .beginner,
            required: [.dumbbells],
            pattern: .pull,
            region: .upper,
            tags: [.strength, .lowImpact, .beginnerFriendly, .dumbbell],
            rest: 45,
            beginnerTarget: 10,
            intermediateTarget: 12
        ),
        entry(
            .shoulderPress,
            difficulty: .intermediate,
            required: [.dumbbells],
            pattern: .push,
            region: .upper,
            tags: [.strength, .performance, .lowImpact, .dumbbell],
            contraindications: [.shoulderSensitive, .lowerBackSensitive],
            rest: 60,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .tricepDip,
            difficulty: .intermediate,
            required: [.bodyweight, .chair],
            optional: [.bench],
            pattern: .push,
            region: .upper,
            tags: [.strength, .lowImpact, .bodyweight],
            contraindications: [.shoulderSensitive, .wristSensitive],
            rest: 60,
            beginnerTarget: 6,
            intermediateTarget: 10
        ),
        entry(
            .inclinePushup,
            difficulty: .beginner,
            required: [.bodyweight, .wall],
            optional: [.bench],
            pattern: .push,
            region: .upper,
            tags: [.strength, .longevity, .lowImpact, .beginnerFriendly, .bodyweight],
            contraindications: [.shoulderSensitive, .wristSensitive],
            rest: 45,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),

        // Full Body and Core
        entry(
            .jumpingJack,
            difficulty: .beginner,
            required: [.bodyweight],
            pattern: .cardio,
            region: .fullBody,
            tags: [.performance, .warmup, .finisher, .highImpact, .beginnerFriendly, .bodyweight],
            contraindications: [.kneeSensitive, .highImpact],
            rest: 30,
            beginnerTarget: 20,
            intermediateTarget: 40
        ),
        entry(
            .kneeRaise,
            difficulty: .beginner,
            required: [.bodyweight],
            pattern: .coreFlexion,
            region: .core,
            tags: [.performance, .longevity, .warmup, .lowImpact, .beginnerFriendly, .bodyweight],
            rest: 30,
            beginnerTarget: 12,
            intermediateTarget: 20
        ),
        entry(
            .sitUp,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .coreFlexion,
            region: .core,
            tags: [.strength, .lowImpact, .bodyweight],
            contraindications: [.lowerBackSensitive],
            rest: 45,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .vUp,
            difficulty: .advanced,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .coreFlexion,
            region: .core,
            tags: [.strength, .performance, .finisher, .lowImpact, .bodyweight],
            contraindications: [.lowerBackSensitive],
            rest: 60,
            beginnerTarget: 5,
            intermediateTarget: 10
        ),
        entry(
            .plank,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .coreAntiExtension,
            region: .core,
            tags: [.strength, .longevity, .lowImpact, .beginnerFriendly, .bodyweight, .isometric],
            contraindications: [.shoulderSensitive, .wristSensitive, .lowerBackSensitive],
            rest: 45,
            beginnerTarget: 20,
            intermediateTarget: 45
        ),
        entry(
            .highKnees,
            difficulty: .intermediate,
            required: [.bodyweight],
            pattern: .cardio,
            region: .fullBody,
            tags: [.performance, .warmup, .finisher, .highImpact, .bodyweight],
            contraindications: [.kneeSensitive, .highImpact],
            rest: 30,
            beginnerTarget: 20,
            intermediateTarget: 40
        ),
        entry(
            .mountainClimber,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .coreAntiExtension,
            region: .fullBody,
            tags: [.performance, .finisher, .highImpact, .bodyweight],
            contraindications: [.shoulderSensitive, .wristSensitive, .lowerBackSensitive, .highImpact],
            rest: 45,
            beginnerTarget: 12,
            intermediateTarget: 24
        ),
        entry(
            .reverseCrunch,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .coreFlexion,
            region: .core,
            tags: [.strength, .lowImpact, .beginnerFriendly, .bodyweight],
            contraindications: [.lowerBackSensitive],
            rest: 45,
            beginnerTarget: 10,
            intermediateTarget: 15
        ),
        entry(
            .russianTwist,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.mat, .dumbbells],
            pattern: .coreRotation,
            region: .core,
            tags: [.strength, .performance, .finisher, .lowImpact, .bodyweight],
            contraindications: [.lowerBackSensitive],
            rest: 45,
            beginnerTarget: 12,
            intermediateTarget: 20
        ),
        entry(
            .birdDog,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .coreAntiExtension,
            region: .core,
            tags: [.strength, .longevity, .warmup, .lowImpact, .beginnerFriendly, .bodyweight],
            rest: 30,
            beginnerTarget: 8,
            intermediateTarget: 12
        ),
        entry(
            .sidePlank,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .coreAntiExtension,
            region: .core,
            tags: [.strength, .performance, .lowImpact, .bodyweight, .isometric],
            contraindications: [.shoulderSensitive, .wristSensitive, .lowerBackSensitive],
            rest: 45,
            beginnerTarget: 15,
            intermediateTarget: 30
        ),

        // Yoga and Mobility
        entry(
            .downwardDog,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .yogaHold,
            region: .mobility,
            tags: [.longevity, .warmup, .lowImpact, .beginnerFriendly, .bodyweight, .isometric],
            contraindications: [.shoulderSensitive, .wristSensitive],
            rest: 30,
            beginnerTarget: 20,
            intermediateTarget: 45
        ),
        entry(
            .warrior,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .yogaHold,
            region: .mobility,
            tags: [.longevity, .performance, .lowImpact, .beginnerFriendly, .bodyweight, .isometric],
            contraindications: [.kneeSensitive],
            rest: 30,
            beginnerTarget: 20,
            intermediateTarget: 45
        ),
        entry(
            .chairPose,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .yogaHold,
            region: .mobility,
            tags: [.strength, .longevity, .lowImpact, .bodyweight, .isometric],
            contraindications: [.kneeSensitive],
            rest: 45,
            beginnerTarget: 15,
            intermediateTarget: 35
        ),
        entry(
            .treePose,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .balance,
            region: .mobility,
            tags: [.longevity, .warmup, .lowImpact, .beginnerFriendly, .bodyweight, .isometric],
            rest: 30,
            beginnerTarget: 20,
            intermediateTarget: 45
        ),
        entry(
            .trianglePose,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .yogaHold,
            region: .mobility,
            tags: [.longevity, .warmup, .lowImpact, .bodyweight, .isometric],
            rest: 30,
            beginnerTarget: 20,
            intermediateTarget: 45
        ),
        entry(
            .warriorOne,
            difficulty: .intermediate,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .yogaHold,
            region: .mobility,
            tags: [.longevity, .performance, .lowImpact, .bodyweight, .isometric],
            contraindications: [.kneeSensitive, .lowerBackSensitive],
            rest: 30,
            beginnerTarget: 20,
            intermediateTarget: 45
        ),
        entry(
            .warriorThree,
            difficulty: .advanced,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .balance,
            region: .mobility,
            tags: [.strength, .performance, .longevity, .lowImpact, .bodyweight, .isometric],
            contraindications: [.lowerBackSensitive],
            rest: 45,
            beginnerTarget: 10,
            intermediateTarget: 25
        ),
        entry(
            .cobraPose,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .yogaHold,
            region: .mobility,
            tags: [.longevity, .warmup, .lowImpact, .beginnerFriendly, .bodyweight, .isometric],
            contraindications: [.shoulderSensitive, .wristSensitive, .lowerBackSensitive],
            rest: 30,
            beginnerTarget: 20,
            intermediateTarget: 45
        ),
        entry(
            .mountainPose,
            difficulty: .beginner,
            required: [.bodyweight],
            optional: [.mat],
            pattern: .yogaHold,
            region: .mobility,
            tags: [.longevity, .warmup, .lowImpact, .beginnerFriendly, .bodyweight, .isometric],
            rest: 30,
            beginnerTarget: 30,
            intermediateTarget: 60
        ),
    ]

    static let allByExerciseType: [ExerciseType: ExercisePlanMetadata] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.exerciseType, $0) }
    )

    static var plannedWorkoutMetadata: [ExercisePlanMetadata] {
        all.filter { $0.supportsPlannedWorkout }
    }

    static var freeAnalysisMetadata: [ExercisePlanMetadata] {
        all.filter { $0.supportsFreeAnalysis }
    }

    static func metadata(for exerciseType: ExerciseType) -> ExercisePlanMetadata? {
        allByExerciseType[exerciseType]
    }

    private static func entry(
        _ exerciseType: ExerciseType,
        difficulty: ExerciseDifficulty?,
        required: Set<EquipmentOption>,
        optional: Set<EquipmentOption> = [],
        pattern: MovementPattern,
        region: BodyRegion,
        tags: Set<PlanTag>,
        contraindications: Set<ContraindicationTag> = [],
        supportsFreeAnalysis: Bool = true,
        supportsPlannedWorkout: Bool = true,
        rest: Int,
        beginnerTarget: Int,
        intermediateTarget: Int
    ) -> ExercisePlanMetadata {
        ExercisePlanMetadata(
            exerciseType: exerciseType,
            difficulty: difficulty,
            requiredEquipment: required,
            optionalEquipment: optional,
            movementPattern: pattern,
            bodyRegion: region,
            planTags: tags,
            contraindicationTags: contraindications,
            supportsFreeAnalysis: supportsFreeAnalysis,
            supportsPlannedWorkout: supportsPlannedWorkout,
            defaultRestSeconds: rest,
            defaultBeginnerTarget: beginnerTarget,
            defaultIntermediateTarget: intermediateTarget
        )
    }
}
