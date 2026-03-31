import Foundation

// ────────────────────────────────────────────────────────────────────
// MARK: - Exercise Category
// ────────────────────────────────────────────────────────────────────

/// Top-level grouping shown on the home dashboard.
enum ExerciseCategory: String, CaseIterable, Identifiable {
    case upperBody
    case lowerBody
    case fullBody
    case yoga

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .upperBody: "Upper Body"
        case .lowerBody: "Lower Body"
        case .fullBody:  "Full Body"
        case .yoga:      "Yoga"
        }
    }

    var icon: String {
        switch self {
        case .upperBody: "figure.arms.open"
        case .lowerBody: "figure.strengthtraining.traditional"
        case .fullBody:  "figure.run"
        case .yoga:      "figure.yoga"
        }
    }

    var subtitle: String {
        switch self {
        case .upperBody: "Chest, arms & shoulders"
        case .lowerBody: "Quads, glutes & calves"
        case .fullBody:  "Hit everything at once"
        case .yoga:      "Flexibility & balance"
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Camera Position
// ────────────────────────────────────────────────────────────────────

/// Which way the user should face the camera for optimal tracking.
enum CameraPosition: String, Codable {
    /// User faces the camera directly (front-facing selfie cam).
    case front
    /// User stands sideways to the camera.
    case side
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Movement Type
// ────────────────────────────────────────────────────────────────────

/// Whether the exercise counts reps or holds a position.
enum MovementType: String, Codable {
    /// Repeated concentric/eccentric cycles (squats, curls, etc.)
    case repetition
    /// Static hold scored by duration (plank, yoga poses)
    case isometric
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Angle Definition
// ────────────────────────────────────────────────────────────────────

/// Defines how to measure a specific joint angle using three body landmarks.
/// The angle is measured at `midJoint` between vectors from `startJoint`
/// and `endJoint`.
struct AngleDefinition: Codable, Equatable {
    /// Human-readable key for the angle dictionary (e.g. "kneeAngle").
    let key: String

    /// Display label shown on the ROM overlay (e.g. "Knee").
    let label: String

    /// First landmark (vector origin A).
    let startJoint: String
    /// Vertex landmark where the angle is measured.
    let midJoint: String
    /// Second landmark (vector origin B).
    let endJoint: String

    /// Which side(s) to measure. `.both` averages left and right.
    let side: MeasurementSide

    enum MeasurementSide: String, Codable {
        case left
        case right
        case both
        /// Use whichever side has more visible joints.
        case bestAvailable
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Phase Threshold
// ────────────────────────────────────────────────────────────────────

/// Defines the angle range that triggers a specific rep phase.
struct PhaseThreshold: Codable, Equatable {
    /// The angle key this threshold applies to (matches AngleDefinition.key).
    let angleKey: String

    /// Phase enters when the angle crosses below this value.
    let enterBelow: Double?

    /// Phase enters when the angle crosses above this value.
    let enterAbove: Double?
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Form Rule
// ────────────────────────────────────────────────────────────────────

/// A biomechanical constraint checked every frame during an exercise.
/// When violated, the engine generates a coach cue.
struct FormRule: Codable, Equatable, Identifiable {
    let id: String

    /// The angle key to check.
    let angleKey: String

    /// Minimum acceptable value (degrees). Below = violation.
    let minAngle: Double?

    /// Maximum acceptable value (degrees). Above = violation.
    let maxAngle: Double?

    /// Only check this rule during these phases. Empty = always.
    let activeDuringPhases: [String]

    /// Feedback shown when rule is violated — keyed by coach personality.
    let feedbackGood: String
    let feedbackDrill: String

    /// How severe the violation is.
    let severity: String // "info", "warning", "critical"

    /// Seconds before this rule can fire again.
    let cooldownSeconds: Double
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Positional Check
// ────────────────────────────────────────────────────────────────────

/// A spatial / landmark-relative check that goes beyond simple
/// 3-point angle comparisons. Evaluated by `AngleCalculator` and
/// consumed by `FormFeedbackEngine`.
struct PositionalCheck: Codable, Equatable, Identifiable {
    let id: String

    let checkType: CheckType

    /// Numeric threshold whose meaning depends on `checkType`.
    let threshold: Double?

    /// Optional landmark operands for joint-vs-joint checks.
    let jointA: JointName?
    let jointB: JointName?

    /// Only run during these phases. Empty = always.
    let activeDuringPhases: [String]

    let feedbackGood: String
    let feedbackDrill: String
    let severity: String
    let cooldownSeconds: Double

    enum CheckType: String, Codable {
        case kneeValgus
        case heelRise
        case jointAboveJoint
        case jointAlignedX
        case shoulderLevel
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Exercise Definition
// ────────────────────────────────────────────────────────────────────

/// Complete specification for a single exercise. Contains everything
/// needed to count reps, check form, render ROM overlays, and
/// generate coaching feedback.
struct ExerciseDefinition: Identifiable, Equatable {
    /// Matches the ExerciseType rawValue.
    let id: String

    /// Human-readable name.
    let displayName: String

    /// Category for dashboard grouping.
    let category: ExerciseCategory

    /// Rep-based or hold-based.
    let movementType: MovementType

    /// How the user should face the camera.
    let cameraPosition: CameraPosition

    /// Instruction shown before starting (e.g. "Stand facing camera").
    let setupInstruction: String

    /// Joints that must be visible for tracking.
    let requiredJoints: [JointName]

    /// Hint shown in the visibility banner.
    let visibilityHint: String

    /// All angles this exercise tracks.
    let angles: [AngleDefinition]

    /// The primary angle key used for rep counting.
    let primaryAngleKey: String

    /// Angle thresholds for the "down" (eccentric) phase.
    let downThreshold: PhaseThreshold

    /// Angle thresholds for the "up" (concentric) phase.
    let upThreshold: PhaseThreshold

    /// Target depth/range for a quality rep (used for depth cues).
    let qualityTarget: Double?

    /// Whether quality target is a minimum (must go above) or maximum (must go below).
    let qualityTargetIsMinimum: Bool

    /// Biomechanical form rules checked every frame.
    let formRules: [FormRule]

    /// Spatial / positional checks that use landmark positions
    /// rather than 3-point angles.
    let positionalChecks: [PositionalCheck]

    /// Muscles targeted (for info display).
    let targetMuscles: [String]

    init(
        id: String,
        displayName: String,
        category: ExerciseCategory,
        movementType: MovementType,
        cameraPosition: CameraPosition,
        setupInstruction: String,
        requiredJoints: [JointName],
        visibilityHint: String,
        angles: [AngleDefinition],
        primaryAngleKey: String,
        downThreshold: PhaseThreshold,
        upThreshold: PhaseThreshold,
        qualityTarget: Double?,
        qualityTargetIsMinimum: Bool,
        formRules: [FormRule],
        positionalChecks: [PositionalCheck] = [],
        targetMuscles: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.movementType = movementType
        self.cameraPosition = cameraPosition
        self.setupInstruction = setupInstruction
        self.requiredJoints = requiredJoints
        self.visibilityHint = visibilityHint
        self.angles = angles
        self.primaryAngleKey = primaryAngleKey
        self.downThreshold = downThreshold
        self.upThreshold = upThreshold
        self.qualityTarget = qualityTarget
        self.qualityTargetIsMinimum = qualityTargetIsMinimum
        self.formRules = formRules
        self.positionalChecks = positionalChecks
        self.targetMuscles = targetMuscles
    }

    static func == (lhs: ExerciseDefinition, rhs: ExerciseDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Exercise Library
// ────────────────────────────────────────────────────────────────────

/// Central registry of every exercise the app supports.
/// Each entry contains complete biomechanical data for rep counting,
/// form feedback, and ROM display.
enum ExerciseLibrary {

    /// All registered exercises.
    static let all: [ExerciseDefinition] = [
        // Lower Body
        squats, sumoSquats, lunges, sideLunges, gluteBridge,
        hipAbductionStanding, legRaises,
        // Upper Body
        bicepCurls, pushUps, lateralRaises, frontRaises,
        overheadDumbbellPress, cobraWings, overarmReachBilateral,
        // Full Body
        jumpingJacks, kneeRaisesBilateral, sitUps, vUps, plank,
        // Yoga
        downwardDog, warrior,
    ]

    /// Lookup by exercise ID.
    static func definition(for id: String) -> ExerciseDefinition? {
        all.first { $0.id == id }
    }

    /// Exercises filtered by category.
    static func exercises(in category: ExerciseCategory) -> [ExerciseDefinition] {
        all.filter { $0.category == category }
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - LOWER BODY
    // ────────────────────────────────────────────────────────────────

    // MARK: Squats

    static let squats = ExerciseDefinition(
        id: "squat",
        displayName: "Squats",
        category: .lowerBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera with feet shoulder-width apart",
        requiredJoints: [.leftHip, .rightHip, .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle, .leftShoulder, .rightShoulder],
        visibilityHint: "Full body — shoulders to ankles",
        angles: [
            AngleDefinition(key: "kneeAngle", label: "Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .both),
            AngleDefinition(key: "hipAngle", label: "Hip",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "knee",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "kneeAngle",
        downThreshold: PhaseThreshold(angleKey: "kneeAngle", enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "kneeAngle", enterBelow: nil, enterAbove: 160),
        qualityTarget: 90,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "squat_depth", angleKey: "kneeAngle",
                     minAngle: nil, maxAngle: 90,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Try to go a bit deeper — aim for thighs parallel!",
                     feedbackDrill: "That's a half rep at best. Get your ass DOWN!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "squat_back_straight", angleKey: "hipAngle",
                     minAngle: 65, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Keep your chest up and back straight!",
                     feedbackDrill: "Stop hunching over like a shrimp! Chest UP!",
                     severity: "warning", cooldownSeconds: 10),
        ],
        positionalChecks: [
            PositionalCheck(id: "squat_valgus", checkType: .kneeValgus,
                            threshold: 0.15, jointA: nil, jointB: nil,
                            activeDuringPhases: ["down"],
                            feedbackGood: "Push your knees out over your toes — don't let them cave in!",
                            feedbackDrill: "Knees OUT! They're caving in like a cheap tent!",
                            severity: "warning", cooldownSeconds: 10),
            PositionalCheck(id: "squat_heel", checkType: .heelRise,
                            threshold: 0.02, jointA: nil, jointB: nil,
                            activeDuringPhases: ["down"],
                            feedbackGood: "Keep your heels flat on the ground!",
                            feedbackDrill: "Heels DOWN! You're not doing calf raises!",
                            severity: "warning", cooldownSeconds: 10),
        ],
        targetMuscles: ["Quadriceps", "Glutes", "Hamstrings", "Core"]
    )

    // MARK: Sumo Squats

    static let sumoSquats = ExerciseDefinition(
        id: "sumoSquat",
        displayName: "Sumo Squats",
        category: .lowerBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing camera with feet wider than shoulder-width, toes pointed out",
        requiredJoints: [.leftHip, .rightHip, .leftKnee, .rightKnee,
                         .leftShoulder, .rightShoulder, .leftAnkle, .rightAnkle],
        visibilityHint: "Full lower body — shoulders to ankles",
        angles: [
            AngleDefinition(key: "kneeAngle", label: "Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .both),
            AngleDefinition(key: "hipAngle", label: "Hip",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "knee",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "kneeAngle",
        downThreshold: PhaseThreshold(angleKey: "kneeAngle", enterBelow: 95, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "kneeAngle", enterBelow: nil, enterAbove: 160),
        qualityTarget: 85,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "sumo_depth", angleKey: "kneeAngle",
                     minAngle: nil, maxAngle: 85,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Go wider and deeper — feel that inner thigh stretch!",
                     feedbackDrill: "My grandmother squats deeper than that. LOWER!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "sumo_upright", angleKey: "hipAngle",
                     minAngle: 70, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Keep your torso upright — don't lean forward!",
                     feedbackDrill: "Stand up straight! You're not picking up pennies!",
                     severity: "warning", cooldownSeconds: 10),
        ],
        positionalChecks: [
            PositionalCheck(id: "sumo_valgus", checkType: .kneeValgus,
                            threshold: 0.12, jointA: nil, jointB: nil,
                            activeDuringPhases: ["down"],
                            feedbackGood: "Push knees out toward your toes!",
                            feedbackDrill: "Knees are collapsing! Push them OUT!",
                            severity: "warning", cooldownSeconds: 10),
        ],
        targetMuscles: ["Inner Thighs", "Glutes", "Quadriceps", "Core"]
    )

    // MARK: Lunges

    static let lunges = ExerciseDefinition(
        id: "lunge",
        displayName: "Lunges",
        category: .lowerBody,
        movementType: .repetition,
        cameraPosition: .side,
        setupInstruction: "Stand sideways to the camera — step forward to begin",
        requiredJoints: [.leftHip, .rightHip, .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle, .leftShoulder, .rightShoulder],
        visibilityHint: "Full body from the side — shoulder to ankle",
        angles: [
            AngleDefinition(key: "frontKneeAngle", label: "Front Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .bestAvailable),
            AngleDefinition(key: "hipAngle", label: "Hip",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "knee",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "frontKneeAngle",
        downThreshold: PhaseThreshold(angleKey: "frontKneeAngle", enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "frontKneeAngle", enterBelow: nil, enterAbove: 155),
        qualityTarget: 90,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "lunge_depth", angleKey: "frontKneeAngle",
                     minAngle: nil, maxAngle: 90,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Drop that back knee a little lower!",
                     feedbackDrill: "That's barely a curtsy. Get DOWN there!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "lunge_torso", angleKey: "hipAngle",
                     minAngle: 75, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Keep your torso upright — eyes forward!",
                     feedbackDrill: "Stop leaning! You look like the Tower of Pisa!",
                     severity: "warning", cooldownSeconds: 10),
        ],
        targetMuscles: ["Quadriceps", "Glutes", "Hamstrings", "Calves"]
    )

    // MARK: Side Lunges

    static let sideLunges = ExerciseDefinition(
        id: "sideLunge",
        displayName: "Side Lunges",
        category: .lowerBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera with feet together",
        requiredJoints: [.leftHip, .rightHip, .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle, .leftShoulder, .rightShoulder],
        visibilityHint: "Full body — shoulders to ankles",
        angles: [
            AngleDefinition(key: "kneeAngle", label: "Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .bestAvailable),
            AngleDefinition(key: "trailingKneeAngle", label: "Trailing Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .both),
        ],
        primaryAngleKey: "kneeAngle",
        downThreshold: PhaseThreshold(angleKey: "kneeAngle", enterBelow: 105, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "kneeAngle", enterBelow: nil, enterAbove: 155),
        qualityTarget: 90,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "sidelunge_depth", angleKey: "kneeAngle",
                     minAngle: nil, maxAngle: 90,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Sink a bit deeper into the lunge!",
                     feedbackDrill: "That was pathetic. Sit INTO it!",
                     severity: "warning", cooldownSeconds: 8),
        ],
        positionalChecks: [
            PositionalCheck(id: "sidelunge_shoulders", checkType: .shoulderLevel,
                            threshold: 0.04, jointA: nil, jointB: nil,
                            activeDuringPhases: ["down"],
                            feedbackGood: "Keep your shoulders level — don't lean to one side!",
                            feedbackDrill: "You're tilting! Keep those shoulders LEVEL!",
                            severity: "info", cooldownSeconds: 10),
        ],
        targetMuscles: ["Inner Thighs", "Quadriceps", "Glutes", "Hip Flexors"]
    )

    // MARK: Glute Bridge

    static let gluteBridge = ExerciseDefinition(
        id: "gluteBridge",
        displayName: "Glute Bridge",
        category: .lowerBody,
        movementType: .repetition,
        cameraPosition: .side,
        setupInstruction: "Lie on your back sideways to the camera, knees bent",
        requiredJoints: [.leftShoulder, .rightShoulder, .leftHip, .rightHip,
                         .leftKnee, .rightKnee, .leftAnkle, .rightAnkle],
        visibilityHint: "Full body from the side — shoulder to ankle",
        angles: [
            AngleDefinition(key: "hipAngle", label: "Hip",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "knee",
                            side: .bestAvailable),
            AngleDefinition(key: "kneeAngle", label: "Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "hipAngle",
        downThreshold: PhaseThreshold(angleKey: "hipAngle", enterBelow: nil, enterAbove: 160),
        upThreshold: PhaseThreshold(angleKey: "hipAngle", enterBelow: 130, enterAbove: nil),
        qualityTarget: 170,
        qualityTargetIsMinimum: true,
        formRules: [
            FormRule(id: "bridge_height", angleKey: "hipAngle",
                     minAngle: 170, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Squeeze your glutes and push those hips higher!",
                     feedbackDrill: "Higher! Your hips are barely off the ground!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "bridge_kneeangle", angleKey: "kneeAngle",
                     minAngle: 75, maxAngle: 105,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Keep your knees at roughly 90 degrees!",
                     feedbackDrill: "Fix your knee angle — not too wide, not too narrow!",
                     severity: "info", cooldownSeconds: 12),
        ],
        targetMuscles: ["Glutes", "Hamstrings", "Core", "Lower Back"]
    )

    // MARK: Hip Abduction Standing

    static let hipAbductionStanding = ExerciseDefinition(
        id: "hipAbduction",
        displayName: "Hip Abduction Standing",
        category: .lowerBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera — lift one leg out to the side",
        requiredJoints: [.leftHip, .rightHip, .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle, .leftShoulder, .rightShoulder],
        visibilityHint: "Full body — shoulders to ankles",
        angles: [
            AngleDefinition(key: "legAbductionAngle", label: "Leg Spread",
                            startJoint: "ankle_left", midJoint: "hip_center", endJoint: "ankle_right",
                            side: .both),
        ],
        primaryAngleKey: "legAbductionAngle",
        downThreshold: PhaseThreshold(angleKey: "legAbductionAngle", enterBelow: nil, enterAbove: 25),
        upThreshold: PhaseThreshold(angleKey: "legAbductionAngle", enterBelow: 12, enterAbove: nil),
        qualityTarget: 35,
        qualityTargetIsMinimum: true,
        formRules: [
            FormRule(id: "hipab_range", angleKey: "legAbductionAngle",
                     minAngle: 35, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Lift that leg a bit higher — feel the burn!",
                     feedbackDrill: "Higher! You're barely moving that leg!",
                     severity: "warning", cooldownSeconds: 8),
        ],
        positionalChecks: [
            PositionalCheck(id: "hipab_shoulders", checkType: .shoulderLevel,
                            threshold: 0.04, jointA: nil, jointB: nil,
                            activeDuringPhases: ["down"],
                            feedbackGood: "Keep your torso upright — don't lean sideways!",
                            feedbackDrill: "Stop leaning! Stand up STRAIGHT!",
                            severity: "info", cooldownSeconds: 10),
        ],
        targetMuscles: ["Hip Abductors", "Glutes", "Outer Thighs"]
    )

    // MARK: Leg Raises

    static let legRaises = ExerciseDefinition(
        id: "legRaise",
        displayName: "Leg Raises",
        category: .lowerBody,
        movementType: .repetition,
        cameraPosition: .side,
        setupInstruction: "Lie on your back sideways to the camera, legs straight",
        requiredJoints: [.leftShoulder, .rightShoulder, .leftHip, .rightHip,
                         .leftKnee, .rightKnee, .leftAnkle, .rightAnkle],
        visibilityHint: "Full body from the side",
        angles: [
            AngleDefinition(key: "hipFlexionAngle", label: "Hip",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "ankle",
                            side: .bestAvailable),
            AngleDefinition(key: "kneeAngle", label: "Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "hipFlexionAngle",
        downThreshold: PhaseThreshold(angleKey: "hipFlexionAngle", enterBelow: 110, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "hipFlexionAngle", enterBelow: nil, enterAbove: 160),
        qualityTarget: 95,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "legr_straight", angleKey: "kneeAngle",
                     minAngle: 165, maxAngle: nil,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Keep your legs straight — don't bend the knees!",
                     feedbackDrill: "Straight legs! Not banana legs!",
                     severity: "warning", cooldownSeconds: 10),
            FormRule(id: "legr_height", angleKey: "hipFlexionAngle",
                     minAngle: nil, maxAngle: 95,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Lift those legs a bit higher!",
                     feedbackDrill: "Higher! Your legs should be pointing at the ceiling!",
                     severity: "warning", cooldownSeconds: 8),
        ],
        targetMuscles: ["Lower Abs", "Hip Flexors", "Core"]
    )

    // ────────────────────────────────────────────────────────────────
    // MARK: - UPPER BODY
    // ────────────────────────────────────────────────────────────────

    // MARK: Bicep Curls

    static let bicepCurls = ExerciseDefinition(
        id: "bicepCurl",
        displayName: "Bicep Curls",
        category: .upperBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera, arms at your sides",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftElbow, .rightElbow,
                         .leftWrist, .rightWrist,
                         .leftHip, .rightHip],
        visibilityHint: "Arms — shoulders, elbows, and wrists",
        angles: [
            AngleDefinition(key: "elbowAngle", label: "Elbow",
                            startJoint: "shoulder", midJoint: "elbow", endJoint: "wrist",
                            side: .both),
            AngleDefinition(key: "shoulderAngle", label: "Shoulder",
                            startJoint: "hip", midJoint: "shoulder", endJoint: "elbow",
                            side: .both),
        ],
        primaryAngleKey: "elbowAngle",
        downThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: 55, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: nil, enterAbove: 150),
        qualityTarget: 40,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "curl_fullrange", angleKey: "elbowAngle",
                     minAngle: nil, maxAngle: 40,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Squeeze harder at the top — full contraction!",
                     feedbackDrill: "That's a half curl. Bring it ALL the way up!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "curl_swing", angleKey: "shoulderAngle",
                     minAngle: nil, maxAngle: 30,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Keep your elbows pinned to your sides — don't swing!",
                     feedbackDrill: "Stop swinging! You're not on a playground!",
                     severity: "warning", cooldownSeconds: 10),
            FormRule(id: "curl_fullextend", angleKey: "elbowAngle",
                     minAngle: 150, maxAngle: nil,
                     activeDuringPhases: ["up"],
                     feedbackGood: "Fully extend your arms at the bottom!",
                     feedbackDrill: "All the way down! Full range of motion!",
                     severity: "info", cooldownSeconds: 12),
        ],
        targetMuscles: ["Biceps", "Forearms"]
    )

    // MARK: Push Ups

    static let pushUps = ExerciseDefinition(
        id: "pushup",
        displayName: "Push Ups",
        category: .upperBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Get into plank position facing the camera (side view for more accuracy)",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftElbow, .rightElbow,
                         .leftWrist, .rightWrist,
                         .leftHip, .rightHip,
                         .leftAnkle, .rightAnkle],
        visibilityHint: "Full body — shoulders to ankles",
        angles: [
            AngleDefinition(key: "elbowAngle", label: "Elbow",
                            startJoint: "shoulder", midJoint: "elbow", endJoint: "wrist",
                            side: .bestAvailable),
            AngleDefinition(key: "shoulderAngle", label: "Shoulder",
                            startJoint: "hip", midJoint: "shoulder", endJoint: "elbow",
                            side: .bestAvailable),
            AngleDefinition(key: "bodyLineAngle", label: "Body Line",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "ankle",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "elbowAngle",
        downThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: nil, enterAbove: 155),
        qualityTarget: 85,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "pushup_depth", angleKey: "elbowAngle",
                     minAngle: nil, maxAngle: 85,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Go a bit deeper — chest towards the floor!",
                     feedbackDrill: "That's not a push-up, that's a head nod. LOWER!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "pushup_bodyline", angleKey: "bodyLineAngle",
                     minAngle: 160, maxAngle: 180,
                     activeDuringPhases: ["down", "up", "idle"],
                     feedbackGood: "Keep your body in a straight line — don't sag or pike!",
                     feedbackDrill: "Your body line is off! Tighten that core NOW!",
                     severity: "warning", cooldownSeconds: 12),
        ],
        targetMuscles: ["Chest", "Triceps", "Shoulders", "Core"]
    )

    // MARK: Lateral Raises

    static let lateralRaises = ExerciseDefinition(
        id: "lateralRaise",
        displayName: "Lateral Raises",
        category: .upperBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera, arms at your sides",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftElbow, .rightElbow,
                         .leftWrist, .rightWrist,
                         .leftHip, .rightHip],
        visibilityHint: "Upper body — shoulders to wrists",
        angles: [
            AngleDefinition(key: "shoulderAbductionAngle", label: "Arm Raise",
                            startJoint: "hip", midJoint: "shoulder", endJoint: "wrist",
                            side: .both),
            AngleDefinition(key: "elbowAngle", label: "Elbow",
                            startJoint: "shoulder", midJoint: "elbow", endJoint: "wrist",
                            side: .both),
        ],
        primaryAngleKey: "shoulderAbductionAngle",
        downThreshold: PhaseThreshold(angleKey: "shoulderAbductionAngle", enterBelow: nil, enterAbove: 75),
        upThreshold: PhaseThreshold(angleKey: "shoulderAbductionAngle", enterBelow: 30, enterAbove: nil),
        qualityTarget: 85,
        qualityTargetIsMinimum: true,
        formRules: [
            FormRule(id: "latrise_height", angleKey: "shoulderAbductionAngle",
                     minAngle: 85, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Raise your arms to shoulder height!",
                     feedbackDrill: "Higher! Your arms should be parallel to the floor!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "latrise_straight", angleKey: "elbowAngle",
                     minAngle: 155, maxAngle: nil,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Keep a slight bend but don't collapse the arms!",
                     feedbackDrill: "Straighten those noodle arms!",
                     severity: "info", cooldownSeconds: 12),
        ],
        positionalChecks: [
            PositionalCheck(id: "latrise_shrug", checkType: .shoulderLevel,
                            threshold: 0.05, jointA: nil, jointB: nil,
                            activeDuringPhases: ["down"],
                            feedbackGood: "Relax your traps — don't shrug your shoulders up!",
                            feedbackDrill: "Drop those shoulders! You're not earring shopping!",
                            severity: "info", cooldownSeconds: 12),
        ],
        targetMuscles: ["Lateral Deltoids", "Traps"]
    )

    // MARK: Front Raises

    static let frontRaises = ExerciseDefinition(
        id: "frontRaise",
        displayName: "Front Raises",
        category: .upperBody,
        movementType: .repetition,
        cameraPosition: .side,
        setupInstruction: "Stand sideways to the camera, arms at your sides",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftElbow, .rightElbow,
                         .leftWrist, .rightWrist,
                         .leftHip, .rightHip],
        visibilityHint: "Side view — shoulder to wrist",
        angles: [
            AngleDefinition(key: "shoulderFlexionAngle", label: "Arm Raise",
                            startJoint: "hip", midJoint: "shoulder", endJoint: "wrist",
                            side: .bestAvailable),
            AngleDefinition(key: "elbowAngle", label: "Elbow",
                            startJoint: "shoulder", midJoint: "elbow", endJoint: "wrist",
                            side: .bestAvailable),
            AngleDefinition(key: "hipAngle", label: "Trunk",
                            startJoint: "knee", midJoint: "hip", endJoint: "shoulder",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "shoulderFlexionAngle",
        downThreshold: PhaseThreshold(angleKey: "shoulderFlexionAngle", enterBelow: nil, enterAbove: 75),
        upThreshold: PhaseThreshold(angleKey: "shoulderFlexionAngle", enterBelow: 30, enterAbove: nil),
        qualityTarget: 85,
        qualityTargetIsMinimum: true,
        formRules: [
            FormRule(id: "frontrise_height", angleKey: "shoulderFlexionAngle",
                     minAngle: 85, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Lift to shoulder height — nice and controlled!",
                     feedbackDrill: "Higher! I said shoulder height, not belly button height!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "frontrise_elbow", angleKey: "elbowAngle",
                     minAngle: 155, maxAngle: nil,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Keep your arms straight!",
                     feedbackDrill: "Lock those elbows! This isn't bicep curls!",
                     severity: "info", cooldownSeconds: 12),
            FormRule(id: "frontrise_sway", angleKey: "hipAngle",
                     minAngle: 165, maxAngle: nil,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Stay upright — don't sway backwards!",
                     feedbackDrill: "Stop leaning back! Control the weight!",
                     severity: "info", cooldownSeconds: 12),
        ],
        targetMuscles: ["Anterior Deltoids", "Upper Chest"]
    )

    // MARK: Overhead Dumbbell Press

    static let overheadDumbbellPress = ExerciseDefinition(
        id: "overheadPress",
        displayName: "Overhead Dumbbell Press",
        category: .upperBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera, weights at shoulder height",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftElbow, .rightElbow,
                         .leftWrist, .rightWrist,
                         .leftHip, .rightHip],
        visibilityHint: "Upper body — shoulders, elbows, and wrists",
        angles: [
            AngleDefinition(key: "elbowAngle", label: "Elbow",
                            startJoint: "shoulder", midJoint: "elbow", endJoint: "wrist",
                            side: .both),
            AngleDefinition(key: "shoulderAbductionAngle", label: "Shoulder",
                            startJoint: "hip", midJoint: "shoulder", endJoint: "elbow",
                            side: .both),
        ],
        primaryAngleKey: "elbowAngle",
        downThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: nil, enterAbove: 155),
        upThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: 95, enterAbove: nil),
        qualityTarget: 170,
        qualityTargetIsMinimum: true,
        formRules: [
            FormRule(id: "ohp_lockout", angleKey: "elbowAngle",
                     minAngle: 170, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Press all the way up — full extension!",
                     feedbackDrill: "Lock it out! Halfway doesn't count!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "ohp_elbow_position", angleKey: "shoulderAbductionAngle",
                     minAngle: 60, maxAngle: nil,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Keep elbows at about 45 degrees from your body!",
                     feedbackDrill: "Elbows out! Don't tuck them in so tight!",
                     severity: "info", cooldownSeconds: 12),
        ],
        targetMuscles: ["Shoulders", "Triceps", "Upper Chest", "Traps"]
    )

    // MARK: Cobra Wings

    static let cobraWings = ExerciseDefinition(
        id: "cobraWings",
        displayName: "Cobra Wings",
        category: .upperBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing camera, arms bent at 90° in front of chest",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftElbow, .rightElbow,
                         .leftWrist, .rightWrist,
                         .leftHip, .rightHip],
        visibilityHint: "Upper body — shoulders, elbows, and wrists",
        angles: [
            AngleDefinition(key: "elbowAngle", label: "Elbow",
                            startJoint: "shoulder", midJoint: "elbow", endJoint: "wrist",
                            side: .both),
            AngleDefinition(key: "shoulderAngle", label: "Shoulder Squeeze",
                            startJoint: "hip", midJoint: "shoulder", endJoint: "elbow",
                            side: .both),
        ],
        primaryAngleKey: "shoulderAngle",
        downThreshold: PhaseThreshold(angleKey: "shoulderAngle", enterBelow: nil, enterAbove: 80),
        upThreshold: PhaseThreshold(angleKey: "shoulderAngle", enterBelow: 40, enterAbove: nil),
        qualityTarget: 90,
        qualityTargetIsMinimum: true,
        formRules: [
            FormRule(id: "cobra_squeeze", angleKey: "shoulderAngle",
                     minAngle: 90, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Squeeze those shoulder blades together!",
                     feedbackDrill: "Squeeze harder! Pretend there's a pencil between your shoulder blades!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "cobra_elbow", angleKey: "elbowAngle",
                     minAngle: 80, maxAngle: 110,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Maintain that 90-degree elbow bend!",
                     feedbackDrill: "Keep those elbows locked at 90! This isn't a flap!",
                     severity: "info", cooldownSeconds: 12),
        ],
        targetMuscles: ["Rear Deltoids", "Rhomboids", "Traps", "Rotator Cuff"]
    )

    // MARK: Overarm Reach Bilateral

    static let overarmReachBilateral = ExerciseDefinition(
        id: "overarmReach",
        displayName: "Overarm Reach Bilateral",
        category: .upperBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera, arms at your sides",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftElbow, .rightElbow,
                         .leftWrist, .rightWrist,
                         .leftHip, .rightHip],
        visibilityHint: "Upper body — shoulders to wrists",
        angles: [
            AngleDefinition(key: "shoulderFlexionAngle", label: "Arm Raise",
                            startJoint: "hip", midJoint: "shoulder", endJoint: "wrist",
                            side: .both),
            AngleDefinition(key: "elbowAngle", label: "Elbow",
                            startJoint: "shoulder", midJoint: "elbow", endJoint: "wrist",
                            side: .both),
        ],
        primaryAngleKey: "shoulderFlexionAngle",
        downThreshold: PhaseThreshold(angleKey: "shoulderFlexionAngle", enterBelow: nil, enterAbove: 150),
        upThreshold: PhaseThreshold(angleKey: "shoulderFlexionAngle", enterBelow: 40, enterAbove: nil),
        qualityTarget: 165,
        qualityTargetIsMinimum: true,
        formRules: [
            FormRule(id: "overarm_full", angleKey: "shoulderFlexionAngle",
                     minAngle: 165, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Reach all the way overhead — full stretch!",
                     feedbackDrill: "ALL the way up! Touch the ceiling!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "overarm_straight", angleKey: "elbowAngle",
                     minAngle: 160, maxAngle: nil,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Keep your arms straight as you reach!",
                     feedbackDrill: "Straight arms! You're not doing bicep curls!",
                     severity: "info", cooldownSeconds: 12),
        ],
        targetMuscles: ["Shoulders", "Lats", "Core", "Upper Back"]
    )

    // ────────────────────────────────────────────────────────────────
    // MARK: - FULL BODY
    // ────────────────────────────────────────────────────────────────

    // MARK: Jumping Jacks

    static let jumpingJacks = ExerciseDefinition(
        id: "jumpingJack",
        displayName: "Jumping Jacks",
        category: .fullBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera, arms at your sides, feet together",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftElbow, .rightElbow,
                         .leftWrist, .rightWrist,
                         .leftHip, .rightHip,
                         .leftAnkle, .rightAnkle],
        visibilityHint: "Full body — head to ankles",
        angles: [
            AngleDefinition(key: "armRaiseAngle", label: "Arms",
                            startJoint: "hip", midJoint: "shoulder", endJoint: "wrist",
                            side: .both),
            AngleDefinition(key: "legSpreadAngle", label: "Legs",
                            startJoint: "ankle_left", midJoint: "hip_center", endJoint: "ankle_right",
                            side: .both),
        ],
        primaryAngleKey: "armRaiseAngle",
        downThreshold: PhaseThreshold(angleKey: "armRaiseAngle", enterBelow: nil, enterAbove: 140),
        upThreshold: PhaseThreshold(angleKey: "armRaiseAngle", enterBelow: 40, enterAbove: nil),
        qualityTarget: 160,
        qualityTargetIsMinimum: true,
        formRules: [
            FormRule(id: "jj_arms", angleKey: "armRaiseAngle",
                     minAngle: 160, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Get those arms all the way overhead!",
                     feedbackDrill: "Arms UP! Not halfway — ALL THE WAY!",
                     severity: "warning", cooldownSeconds: 6),
            FormRule(id: "jj_legs", angleKey: "legSpreadAngle",
                     minAngle: 35, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Spread your feet wider — open up those legs!",
                     feedbackDrill: "Wider! Those legs should be JUMPING apart!",
                     severity: "info", cooldownSeconds: 8),
        ],
        targetMuscles: ["Full Body", "Shoulders", "Calves", "Core"]
    )

    // MARK: Knee Raises Bilateral

    static let kneeRaisesBilateral = ExerciseDefinition(
        id: "kneeRaise",
        displayName: "Knee Raises Bilateral",
        category: .fullBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera — alternate lifting each knee",
        requiredJoints: [.leftHip, .rightHip,
                         .leftKnee, .rightKnee,
                         .leftShoulder, .rightShoulder,
                         .leftAnkle, .rightAnkle],
        visibilityHint: "Full body — shoulders to ankles",
        angles: [
            AngleDefinition(key: "hipFlexionAngle", label: "Hip Flexion",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "knee",
                            side: .bestAvailable),
            AngleDefinition(key: "trunkAngle", label: "Trunk",
                            startJoint: "knee", midJoint: "hip", endJoint: "shoulder",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "hipFlexionAngle",
        downThreshold: PhaseThreshold(angleKey: "hipFlexionAngle", enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "hipFlexionAngle", enterBelow: nil, enterAbove: 150),
        qualityTarget: 80,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "kneer_height", angleKey: "hipFlexionAngle",
                     minAngle: nil, maxAngle: 80,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Drive that knee up to hip height!",
                     feedbackDrill: "HIGHER! Your knee should hit your chest!",
                     severity: "warning", cooldownSeconds: 6),
        ],
        targetMuscles: ["Hip Flexors", "Core", "Quads"]
    )

    // MARK: Sit Ups

    static let sitUps = ExerciseDefinition(
        id: "sitUp",
        displayName: "Sit Ups",
        category: .fullBody,
        movementType: .repetition,
        cameraPosition: .side,
        setupInstruction: "Lie on your back sideways to the camera, knees bent",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftHip, .rightHip,
                         .leftKnee, .rightKnee],
        visibilityHint: "Side view — shoulder, hip, and knee",
        angles: [
            AngleDefinition(key: "torsoAngle", label: "Torso",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "knee",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "torsoAngle",
        downThreshold: PhaseThreshold(angleKey: "torsoAngle", enterBelow: 90, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "torsoAngle", enterBelow: nil, enterAbove: 140),
        qualityTarget: 70,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "situp_full", angleKey: "torsoAngle",
                     minAngle: nil, maxAngle: 70,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Come all the way up — don't stop halfway!",
                     feedbackDrill: "ALL the way up! That was a crunch, not a sit-up!",
                     severity: "warning", cooldownSeconds: 8),
        ],
        targetMuscles: ["Abs", "Hip Flexors", "Core"]
    )

    // MARK: V-Ups

    static let vUps = ExerciseDefinition(
        id: "vUp",
        displayName: "V-Ups",
        category: .fullBody,
        movementType: .repetition,
        cameraPosition: .side,
        setupInstruction: "Lie flat on your back sideways to the camera",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftHip, .rightHip,
                         .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle,
                         .leftWrist, .rightWrist],
        visibilityHint: "Full body from the side",
        angles: [
            AngleDefinition(key: "torsoAngle", label: "Torso",
                            startJoint: "wrist", midJoint: "shoulder", endJoint: "hip",
                            side: .bestAvailable),
            AngleDefinition(key: "hipFlexionAngle", label: "Hip",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "ankle",
                            side: .bestAvailable),
            AngleDefinition(key: "kneeAngle", label: "Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "hipFlexionAngle",
        downThreshold: PhaseThreshold(angleKey: "hipFlexionAngle", enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "hipFlexionAngle", enterBelow: nil, enterAbove: 155),
        qualityTarget: 70,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "vup_touch", angleKey: "hipFlexionAngle",
                     minAngle: nil, maxAngle: 70,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Reach for your toes — hands and feet should meet!",
                     feedbackDrill: "Touch your toes! Not your knees — your TOES!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "vup_legs_straight", angleKey: "kneeAngle",
                     minAngle: 160, maxAngle: nil,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Keep those legs straight throughout the movement!",
                     feedbackDrill: "Straight legs! Don't cheat by bending your knees!",
                     severity: "warning", cooldownSeconds: 10),
        ],
        targetMuscles: ["Upper Abs", "Lower Abs", "Hip Flexors", "Core"]
    )

    // MARK: Plank

    static let plank = ExerciseDefinition(
        id: "plank",
        displayName: "Plank",
        category: .fullBody,
        movementType: .isometric,
        cameraPosition: .side,
        setupInstruction: "Get into plank position sideways to the camera",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftElbow, .rightElbow,
                         .leftHip, .rightHip,
                         .leftAnkle, .rightAnkle],
        visibilityHint: "Full body from the side — shoulder to ankle",
        angles: [
            AngleDefinition(key: "bodyLineAngle", label: "Body Line",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "ankle",
                            side: .bestAvailable),
            AngleDefinition(key: "elbowAngle", label: "Elbow",
                            startJoint: "shoulder", midJoint: "elbow", endJoint: "wrist",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "bodyLineAngle",
        downThreshold: PhaseThreshold(angleKey: "bodyLineAngle", enterBelow: nil, enterAbove: 160),
        upThreshold: PhaseThreshold(angleKey: "bodyLineAngle", enterBelow: 145, enterAbove: nil),
        qualityTarget: 175,
        qualityTargetIsMinimum: true,
        formRules: [
            FormRule(id: "plank_sag", angleKey: "bodyLineAngle",
                     minAngle: 165, maxAngle: nil,
                     activeDuringPhases: [],
                     feedbackGood: "Keep your hips up — straight line from head to heels!",
                     feedbackDrill: "Your hips are dropping! Tighten that core NOW!",
                     severity: "critical", cooldownSeconds: 8),
            FormRule(id: "plank_pike", angleKey: "bodyLineAngle",
                     minAngle: nil, maxAngle: 180,
                     activeDuringPhases: [],
                     feedbackGood: "Don't pike your hips — bring them down a touch!",
                     feedbackDrill: "You're not doing downward dog! Flatten out!",
                     severity: "warning", cooldownSeconds: 8),
        ],
        targetMuscles: ["Core", "Shoulders", "Glutes", "Back"]
    )

    // ────────────────────────────────────────────────────────────────
    // MARK: - YOGA
    // ────────────────────────────────────────────────────────────────

    // MARK: Downward Dog

    static let downwardDog = ExerciseDefinition(
        id: "downwardDog",
        displayName: "Downward Dog",
        category: .yoga,
        movementType: .isometric,
        cameraPosition: .side,
        setupInstruction: "Start on all fours sideways to the camera, then lift hips up",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftHip, .rightHip,
                         .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle,
                         .leftWrist, .rightWrist],
        visibilityHint: "Full body from the side — wrists to ankles",
        angles: [
            AngleDefinition(key: "hipAngle", label: "Hip",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "ankle",
                            side: .bestAvailable),
            AngleDefinition(key: "shoulderAngle", label: "Shoulder",
                            startJoint: "hip", midJoint: "shoulder", endJoint: "wrist",
                            side: .bestAvailable),
            AngleDefinition(key: "kneeAngle", label: "Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "hipAngle",
        downThreshold: PhaseThreshold(angleKey: "hipAngle", enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "hipAngle", enterBelow: nil, enterAbove: 140),
        qualityTarget: 70,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "dd_hips", angleKey: "hipAngle",
                     minAngle: nil, maxAngle: 90,
                     activeDuringPhases: [],
                     feedbackGood: "Push your hips higher — create that inverted V!",
                     feedbackDrill: "Hips UP! You look like a table, not a dog!",
                     severity: "warning", cooldownSeconds: 10),
            FormRule(id: "dd_legs", angleKey: "kneeAngle",
                     minAngle: 165, maxAngle: nil,
                     activeDuringPhases: [],
                     feedbackGood: "Try to straighten your legs — press heels down!",
                     feedbackDrill: "Straight legs! Bend those knees on your own time!",
                     severity: "info", cooldownSeconds: 12),
            FormRule(id: "dd_arms", angleKey: "shoulderAngle",
                     minAngle: 165, maxAngle: nil,
                     activeDuringPhases: [],
                     feedbackGood: "Extend your arms fully — push the floor away!",
                     feedbackDrill: "Lock those arms! Push the ground AWAY from you!",
                     severity: "info", cooldownSeconds: 12),
        ],
        targetMuscles: ["Hamstrings", "Calves", "Shoulders", "Back", "Core"]
    )

    // MARK: Warrior (Warrior II)

    static let warrior = ExerciseDefinition(
        id: "warrior",
        displayName: "Warrior II",
        category: .yoga,
        movementType: .isometric,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera, step wide and extend arms to the sides",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftElbow, .rightElbow,
                         .leftWrist, .rightWrist,
                         .leftHip, .rightHip,
                         .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle],
        visibilityHint: "Full body — head to ankles",
        angles: [
            AngleDefinition(key: "frontKneeAngle", label: "Front Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .bestAvailable),
            AngleDefinition(key: "armLineAngle", label: "Arm Line",
                            startJoint: "wrist_left", midJoint: "shoulder_center", endJoint: "wrist_right",
                            side: .both),
            AngleDefinition(key: "shoulderAbductionAngle", label: "Arms",
                            startJoint: "hip", midJoint: "shoulder", endJoint: "wrist",
                            side: .both),
        ],
        primaryAngleKey: "frontKneeAngle",
        downThreshold: PhaseThreshold(angleKey: "frontKneeAngle", enterBelow: 110, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "frontKneeAngle", enterBelow: nil, enterAbove: 150),
        qualityTarget: 95,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "warrior_knee", angleKey: "frontKneeAngle",
                     minAngle: nil, maxAngle: 95,
                     activeDuringPhases: [],
                     feedbackGood: "Bend your front knee deeper — aim for 90 degrees!",
                     feedbackDrill: "Deeper! A warrior doesn't stand straight!",
                     severity: "warning", cooldownSeconds: 10),
            FormRule(id: "warrior_arms", angleKey: "shoulderAbductionAngle",
                     minAngle: 80, maxAngle: nil,
                     activeDuringPhases: [],
                     feedbackGood: "Keep your arms parallel to the ground!",
                     feedbackDrill: "Arms UP and OUT! Like you're reaching for two walls!",
                     severity: "warning", cooldownSeconds: 10),
        ],
        positionalChecks: [
            PositionalCheck(id: "warrior_shoulders", checkType: .shoulderLevel,
                            threshold: 0.04, jointA: nil, jointB: nil,
                            activeDuringPhases: [],
                            feedbackGood: "Keep your shoulders level — don't tilt!",
                            feedbackDrill: "LEVEL shoulders! You're a warrior, not a seesaw!",
                            severity: "info", cooldownSeconds: 12),
        ],
        targetMuscles: ["Quads", "Glutes", "Shoulders", "Core", "Hip Flexors"]
    )
}
