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

    /// Minimum seconds between rep counts to filter noise (e.g. bouncing
    /// at the bottom of a squat). `nil` uses the counter's default.
    let minRepDuration: TimeInterval?

    /// Ideal angle values used for form score calculation.
    /// Keys match `AngleDefinition.key`; values are the target degrees
    /// at the deepest point of the rep.
    let idealAngles: [String: Double]

    /// Acceptable rep tempo range in seconds. Reps outside this
    /// range incur a tempo penalty in the form score.
    let tempoRange: ClosedRange<Double>

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
        targetMuscles: [String],
        minRepDuration: TimeInterval? = nil,
        idealAngles: [String: Double] = [:],
        tempoRange: ClosedRange<Double> = 1.0...4.0
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
        self.minRepDuration = minRepDuration
        self.idealAngles = idealAngles
        self.tempoRange = tempoRange
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
        hipAbductionStanding, legRaises, wallSit, deadlift, calfRaises,
        // Upper Body
        bicepCurls, pushUps, lateralRaises, frontRaises,
        overheadDumbbellPress, cobraWings, overarmReachBilateral,
        hammerCurl, shoulderPress, tricepDip,
        // Full Body
        jumpingJacks, kneeRaisesBilateral, sitUps, vUps, plank,
        highKnees, mountainClimber,
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
        targetMuscles: ["Quadriceps", "Glutes", "Hamstrings", "Core"],
        minRepDuration: 0.8,
        idealAngles: ["kneeAngle": 90, "hipAngle": 80],
        tempoRange: 1.5...4.0
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
        targetMuscles: ["Inner Thighs", "Glutes", "Quadriceps", "Core"],
        minRepDuration: 0.8,
        idealAngles: ["kneeAngle": 85, "hipAngle": 75],
        tempoRange: 1.5...4.0
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
        targetMuscles: ["Quadriceps", "Glutes", "Hamstrings", "Calves"],
        minRepDuration: 1.0,
        idealAngles: ["frontKneeAngle": 90, "hipAngle": 85],
        tempoRange: 1.5...4.0
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
            FormRule(id: "sidelunge_trailing", angleKey: "trailingKneeAngle",
                     minAngle: 160, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Keep your trailing leg straight — don't bend it!",
                     feedbackDrill: "Straight leg on the other side! Only ONE knee bends!",
                     severity: "info", cooldownSeconds: 10),
        ],
        positionalChecks: [
            PositionalCheck(id: "sidelunge_shoulders", checkType: .shoulderLevel,
                            threshold: 0.04, jointA: nil, jointB: nil,
                            activeDuringPhases: ["down"],
                            feedbackGood: "Keep your shoulders level — don't lean to one side!",
                            feedbackDrill: "You're tilting! Keep those shoulders LEVEL!",
                            severity: "info", cooldownSeconds: 10),
        ],
        targetMuscles: ["Inner Thighs", "Quadriceps", "Glutes", "Hip Flexors"],
        minRepDuration: 1.0,
        idealAngles: ["kneeAngle": 90],
        tempoRange: 1.5...4.0
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
        targetMuscles: ["Glutes", "Hamstrings", "Core", "Lower Back"],
        minRepDuration: 0.8,
        idealAngles: ["hipAngle": 170, "kneeAngle": 90],
        tempoRange: 1.0...3.0
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
        targetMuscles: ["Hip Abductors", "Glutes", "Outer Thighs"],
        minRepDuration: 0.6,
        idealAngles: ["legAbductionAngle": 40],
        tempoRange: 1.0...3.0
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
            FormRule(id: "legr_momentum", angleKey: "hipFlexionAngle",
                     minAngle: 80, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Control the movement — don't use momentum to swing!",
                     feedbackDrill: "Stop SWINGING! Slow and controlled — feel every inch!",
                     severity: "info", cooldownSeconds: 10),
        ],
        targetMuscles: ["Lower Abs", "Hip Flexors", "Core"],
        minRepDuration: 1.0,
        idealAngles: ["hipFlexionAngle": 90, "kneeAngle": 170],
        tempoRange: 1.5...4.0
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
        targetMuscles: ["Biceps", "Forearms"],
        minRepDuration: 0.8,
        idealAngles: ["elbowAngle": 35],
        tempoRange: 1.0...3.0
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
            FormRule(id: "pushup_hips_sag", angleKey: "bodyLineAngle",
                     minAngle: 155, maxAngle: nil,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Your hips are sagging — squeeze your glutes and tighten your core!",
                     feedbackDrill: "Hips are DROPPING! Tighten everything — you're a PLANK, not a hammock!",
                     severity: "critical", cooldownSeconds: 10),
            FormRule(id: "pushup_hips_pike", angleKey: "bodyLineAngle",
                     minAngle: nil, maxAngle: 185,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Your hips are too high — flatten your body line!",
                     feedbackDrill: "Stop piking! This is push-ups, not downward dog!",
                     severity: "warning", cooldownSeconds: 10),
        ],
        targetMuscles: ["Chest", "Triceps", "Shoulders", "Core"],
        minRepDuration: 1.0,
        idealAngles: ["elbowAngle": 80, "bodyLineAngle": 170],
        tempoRange: 1.5...4.0
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
            FormRule(id: "latrise_toohigh", angleKey: "shoulderAbductionAngle",
                     minAngle: nil, maxAngle: 100,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Don't raise past shoulder height — control at the top!",
                     feedbackDrill: "TOO HIGH! Shoulder height is the ceiling — stop overshooting!",
                     severity: "info", cooldownSeconds: 10),
        ],
        positionalChecks: [
            PositionalCheck(id: "latrise_shrug", checkType: .shoulderLevel,
                            threshold: 0.05, jointA: nil, jointB: nil,
                            activeDuringPhases: ["down"],
                            feedbackGood: "Relax your traps — don't shrug your shoulders up!",
                            feedbackDrill: "Drop those shoulders! You're not earring shopping!",
                            severity: "info", cooldownSeconds: 12),
        ],
        targetMuscles: ["Lateral Deltoids", "Traps"],
        minRepDuration: 0.6,
        idealAngles: ["shoulderAbductionAngle": 90],
        tempoRange: 1.0...3.0
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
        targetMuscles: ["Anterior Deltoids", "Upper Chest"],
        minRepDuration: 0.6,
        idealAngles: ["shoulderFlexionAngle": 90],
        tempoRange: 1.0...3.0
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
        targetMuscles: ["Shoulders", "Triceps", "Upper Chest", "Traps"],
        minRepDuration: 0.8,
        idealAngles: ["elbowAngle": 175],
        tempoRange: 1.0...3.0
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
        targetMuscles: ["Rear Deltoids", "Rhomboids", "Traps", "Rotator Cuff"],
        minRepDuration: 0.6,
        idealAngles: ["shoulderAngle": 95, "elbowAngle": 90],
        tempoRange: 1.0...3.0
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
        targetMuscles: ["Shoulders", "Lats", "Core", "Upper Back"],
        minRepDuration: 0.6,
        idealAngles: ["shoulderFlexionAngle": 170, "elbowAngle": 170],
        tempoRange: 1.0...3.5
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
        targetMuscles: ["Full Body", "Shoulders", "Calves", "Core"],
        minRepDuration: 0.3,
        idealAngles: ["armRaiseAngle": 165],
        tempoRange: 0.5...2.0
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
        targetMuscles: ["Hip Flexors", "Core", "Quads"],
        minRepDuration: 0.4,
        idealAngles: ["hipFlexionAngle": 75],
        tempoRange: 0.5...2.0
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
        targetMuscles: ["Abs", "Hip Flexors", "Core"],
        minRepDuration: 0.8,
        idealAngles: ["torsoAngle": 65],
        tempoRange: 1.0...3.0
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
        targetMuscles: ["Upper Abs", "Lower Abs", "Hip Flexors", "Core"],
        minRepDuration: 1.0,
        idealAngles: ["hipFlexionAngle": 60, "kneeAngle": 170],
        tempoRange: 1.5...4.0
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

    // ────────────────────────────────────────────────────────────────
    // MARK: - ADDITIONAL LOWER BODY
    // ────────────────────────────────────────────────────────────────

    // MARK: Wall Sit

    static let wallSit = ExerciseDefinition(
        id: "wallSit",
        displayName: "Wall Sit",
        category: .lowerBody,
        movementType: .isometric,
        cameraPosition: .side,
        setupInstruction: "Stand sideways to the camera and slide down the wall until thighs are parallel",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftHip, .rightHip,
                         .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle],
        visibilityHint: "Full body from the side — shoulder to ankle",
        angles: [
            AngleDefinition(key: "kneeAngle", label: "Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .bestAvailable),
            AngleDefinition(key: "hipAngle", label: "Hip",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "knee",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "kneeAngle",
        downThreshold: PhaseThreshold(angleKey: "kneeAngle", enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "kneeAngle", enterBelow: nil, enterAbove: 150),
        qualityTarget: 90,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "wallsit_depth", angleKey: "kneeAngle",
                     minAngle: nil, maxAngle: 90,
                     activeDuringPhases: [],
                     feedbackGood: "Lower down a bit more — aim for 90 degrees at the knee!",
                     feedbackDrill: "That's not sitting, that's leaning! Get DOWN to 90!",
                     severity: "warning", cooldownSeconds: 10),
            FormRule(id: "wallsit_back", angleKey: "hipAngle",
                     minAngle: 80, maxAngle: nil,
                     activeDuringPhases: [],
                     feedbackGood: "Keep your back flat against the wall — stay upright!",
                     feedbackDrill: "Back FLAT against the wall! You're slouching!",
                     severity: "warning", cooldownSeconds: 10),
        ],
        targetMuscles: ["Quadriceps", "Glutes", "Calves", "Core"],
        idealAngles: ["kneeAngle": 90, "hipAngle": 90]
    )

    // MARK: Deadlift

    static let deadlift = ExerciseDefinition(
        id: "deadlift",
        displayName: "Deadlift",
        category: .lowerBody,
        movementType: .repetition,
        cameraPosition: .side,
        setupInstruction: "Stand sideways to the camera, feet hip-width apart",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftHip, .rightHip,
                         .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle],
        visibilityHint: "Full body from the side — shoulder to ankle",
        angles: [
            AngleDefinition(key: "hipAngle", label: "Hip Hinge",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "knee",
                            side: .bestAvailable),
            AngleDefinition(key: "kneeAngle", label: "Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "hipAngle",
        downThreshold: PhaseThreshold(angleKey: "hipAngle", enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "hipAngle", enterBelow: nil, enterAbove: 165),
        qualityTarget: 90,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "deadlift_back", angleKey: "hipAngle",
                     minAngle: 70, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Keep your back flat — don't let it round over!",
                     feedbackDrill: "Your back is rounding like a scared cat! FLAT back!",
                     severity: "critical", cooldownSeconds: 8),
            FormRule(id: "deadlift_lockout", angleKey: "hipAngle",
                     minAngle: 170, maxAngle: nil,
                     activeDuringPhases: ["up"],
                     feedbackGood: "Stand all the way up — squeeze your glutes at the top!",
                     feedbackDrill: "Lock it OUT! Stand up straight and squeeze!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "deadlift_knees", angleKey: "kneeAngle",
                     minAngle: 140, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Keep your knees soft but fairly straight — this isn't a squat!",
                     feedbackDrill: "Straighten those knees! You're squatting, not hinging!",
                     severity: "info", cooldownSeconds: 10),
        ],
        targetMuscles: ["Hamstrings", "Glutes", "Lower Back", "Traps", "Core"],
        minRepDuration: 1.0,
        idealAngles: ["hipAngle": 90],
        tempoRange: 2.0...5.0
    )

    // MARK: Calf Raises

    static let calfRaises = ExerciseDefinition(
        id: "calfRaise",
        displayName: "Calf Raises",
        category: .lowerBody,
        movementType: .repetition,
        cameraPosition: .side,
        setupInstruction: "Stand sideways to the camera, feet hip-width apart",
        requiredJoints: [.leftHip, .rightHip,
                         .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle],
        visibilityHint: "Lower body from the side — hip to ankle",
        angles: [
            AngleDefinition(key: "kneeAngle", label: "Knee",
                            startJoint: "hip", midJoint: "knee", endJoint: "ankle",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "kneeAngle",
        downThreshold: PhaseThreshold(angleKey: "kneeAngle", enterBelow: 165, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "kneeAngle", enterBelow: nil, enterAbove: 170),
        qualityTarget: 155,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "calfraise_straight", angleKey: "kneeAngle",
                     minAngle: 160, maxAngle: nil,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Keep your legs straight — don't bend the knees!",
                     feedbackDrill: "Straight legs! This is calves, not squats!",
                     severity: "warning", cooldownSeconds: 8),
        ],
        positionalChecks: [
            PositionalCheck(id: "calfraise_balance", checkType: .shoulderLevel,
                            threshold: 0.04, jointA: nil, jointB: nil,
                            activeDuringPhases: [],
                            feedbackGood: "Stay balanced — keep your weight centered!",
                            feedbackDrill: "Stop wobbling! Center your weight!",
                            severity: "info", cooldownSeconds: 10),
        ],
        targetMuscles: ["Calves", "Soleus"],
        minRepDuration: 0.5,
        idealAngles: ["kneeAngle": 170],
        tempoRange: 0.8...2.5
    )

    // ────────────────────────────────────────────────────────────────
    // MARK: - ADDITIONAL UPPER BODY
    // ────────────────────────────────────────────────────────────────

    // MARK: Hammer Curl

    static let hammerCurl = ExerciseDefinition(
        id: "hammerCurl",
        displayName: "Hammer Curls",
        category: .upperBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera, arms at your sides with palms facing in",
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
        downThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: 50, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: nil, enterAbove: 155),
        qualityTarget: 40,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "hammer_squeeze", angleKey: "elbowAngle",
                     minAngle: nil, maxAngle: 40,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Great squeeze! Hold briefly at the top for max contraction!",
                     feedbackDrill: "Squeeze HARDER at the top! Don't just swing through!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "hammer_fullextend", angleKey: "elbowAngle",
                     minAngle: 155, maxAngle: nil,
                     activeDuringPhases: ["up"],
                     feedbackGood: "Extend fully between reps — full range of motion!",
                     feedbackDrill: "ALL the way down! Partial reps are worthless!",
                     severity: "info", cooldownSeconds: 10),
            FormRule(id: "hammer_swing", angleKey: "shoulderAngle",
                     minAngle: nil, maxAngle: 30,
                     activeDuringPhases: ["down", "up"],
                     feedbackGood: "Keep your elbows pinned — don't let the shoulders drift!",
                     feedbackDrill: "Elbows LOCKED to your sides! Stop using momentum!",
                     severity: "warning", cooldownSeconds: 10),
        ],
        targetMuscles: ["Biceps", "Brachialis", "Brachioradialis", "Forearms"],
        minRepDuration: 0.8,
        idealAngles: ["elbowAngle": 35],
        tempoRange: 1.0...3.0
    )

    // MARK: Shoulder Press

    static let shoulderPress = ExerciseDefinition(
        id: "shoulderPress",
        displayName: "Shoulder Press",
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
            AngleDefinition(key: "shoulderAngle", label: "Shoulder",
                            startJoint: "hip", midJoint: "shoulder", endJoint: "elbow",
                            side: .both),
            AngleDefinition(key: "elbowAngle", label: "Elbow",
                            startJoint: "shoulder", midJoint: "elbow", endJoint: "wrist",
                            side: .both),
        ],
        primaryAngleKey: "shoulderAngle",
        downThreshold: PhaseThreshold(angleKey: "shoulderAngle", enterBelow: nil, enterAbove: 160),
        upThreshold: PhaseThreshold(angleKey: "shoulderAngle", enterBelow: 90, enterAbove: nil),
        qualityTarget: 170,
        qualityTargetIsMinimum: true,
        formRules: [
            FormRule(id: "shoulderpress_lockout", angleKey: "shoulderAngle",
                     minAngle: 170, maxAngle: nil,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Press all the way up — lock those arms out!",
                     feedbackDrill: "LOCK IT OUT! Halfway reps don't build shoulders!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "shoulderpress_depth", angleKey: "shoulderAngle",
                     minAngle: nil, maxAngle: 85,
                     activeDuringPhases: ["up"],
                     feedbackGood: "Bring the weights all the way down to shoulder height!",
                     feedbackDrill: "Lower! All the way to your shoulders — full range!",
                     severity: "info", cooldownSeconds: 10),
        ],
        positionalChecks: [
            PositionalCheck(id: "shoulderpress_uneven", checkType: .shoulderLevel,
                            threshold: 0.05, jointA: nil, jointB: nil,
                            activeDuringPhases: ["down"],
                            feedbackGood: "Press both arms evenly — don't favor one side!",
                            feedbackDrill: "Even it out! One arm is leading — press TOGETHER!",
                            severity: "warning", cooldownSeconds: 10),
        ],
        targetMuscles: ["Shoulders", "Triceps", "Upper Chest", "Traps"],
        minRepDuration: 0.8,
        idealAngles: ["shoulderAngle": 175],
        tempoRange: 1.0...3.0
    )

    // MARK: Tricep Dip

    static let tricepDip = ExerciseDefinition(
        id: "tricepDip",
        displayName: "Tricep Dips",
        category: .upperBody,
        movementType: .repetition,
        cameraPosition: .side,
        setupInstruction: "Position sideways to the camera, hands on a bench behind you",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftElbow, .rightElbow,
                         .leftWrist, .rightWrist],
        visibilityHint: "Upper body from the side — shoulder, elbow, and wrist",
        angles: [
            AngleDefinition(key: "elbowAngle", label: "Elbow",
                            startJoint: "shoulder", midJoint: "elbow", endJoint: "wrist",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "elbowAngle",
        downThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: 90, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: nil, enterAbove: 160),
        qualityTarget: 85,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "tricdip_depth", angleKey: "elbowAngle",
                     minAngle: nil, maxAngle: 90,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Go deeper — aim for a 90-degree bend at the elbow!",
                     feedbackDrill: "That's not a dip, that's a nod! Get to 90 degrees!",
                     severity: "warning", cooldownSeconds: 8),
            FormRule(id: "tricdip_lockout", angleKey: "elbowAngle",
                     minAngle: 160, maxAngle: nil,
                     activeDuringPhases: ["up"],
                     feedbackGood: "Extend fully at the top — lock those triceps!",
                     feedbackDrill: "All the way UP! Lock out those arms!",
                     severity: "info", cooldownSeconds: 10),
        ],
        targetMuscles: ["Triceps", "Chest", "Anterior Deltoids"],
        minRepDuration: 0.8,
        idealAngles: ["elbowAngle": 85],
        tempoRange: 1.0...3.0
    )

    // ────────────────────────────────────────────────────────────────
    // MARK: - ADDITIONAL FULL BODY
    // ────────────────────────────────────────────────────────────────

    // MARK: High Knees

    static let highKnees = ExerciseDefinition(
        id: "highKnees",
        displayName: "High Knees",
        category: .fullBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Stand facing the camera — drive each knee up as high as you can",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftHip, .rightHip,
                         .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle],
        visibilityHint: "Full body — shoulders to ankles",
        angles: [
            AngleDefinition(key: "hipFlexionAngle", label: "Hip Flexion",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "knee",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "hipFlexionAngle",
        downThreshold: PhaseThreshold(angleKey: "hipFlexionAngle", enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "hipFlexionAngle", enterBelow: nil, enterAbove: 150),
        qualityTarget: 90,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "highknee_height", angleKey: "hipFlexionAngle",
                     minAngle: nil, maxAngle: 100,
                     activeDuringPhases: ["down"],
                     feedbackGood: "Drive that knee higher — aim for hip level!",
                     feedbackDrill: "HIGHER! Your knee should be at hip height minimum!",
                     severity: "warning", cooldownSeconds: 5),
        ],
        positionalChecks: [
            PositionalCheck(id: "highknee_posture", checkType: .shoulderLevel,
                            threshold: 0.05, jointA: nil, jointB: nil,
                            activeDuringPhases: [],
                            feedbackGood: "Stay upright — don't lean to one side!",
                            feedbackDrill: "Stand STRAIGHT! You're wobbling all over!",
                            severity: "info", cooldownSeconds: 8),
        ],
        targetMuscles: ["Hip Flexors", "Core", "Quads", "Calves"],
        minRepDuration: 0.2,
        idealAngles: ["hipFlexionAngle": 80],
        tempoRange: 0.3...1.5
    )

    // MARK: Mountain Climber

    static let mountainClimber = ExerciseDefinition(
        id: "mountainClimber",
        displayName: "Mountain Climbers",
        category: .fullBody,
        movementType: .repetition,
        cameraPosition: .side,
        setupInstruction: "Get into plank position sideways to the camera",
        requiredJoints: [.leftShoulder, .rightShoulder,
                         .leftHip, .rightHip,
                         .leftKnee, .rightKnee,
                         .leftAnkle, .rightAnkle],
        visibilityHint: "Full body from the side — shoulder to ankle",
        angles: [
            AngleDefinition(key: "hipFlexionAngle", label: "Hip Flexion",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "knee",
                            side: .bestAvailable),
            AngleDefinition(key: "bodyLineAngle", label: "Body Line",
                            startJoint: "shoulder", midJoint: "hip", endJoint: "ankle",
                            side: .bestAvailable),
        ],
        primaryAngleKey: "hipFlexionAngle",
        downThreshold: PhaseThreshold(angleKey: "hipFlexionAngle", enterBelow: 90, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "hipFlexionAngle", enterBelow: nil, enterAbove: 160),
        qualityTarget: 80,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(id: "mtnclimb_hips", angleKey: "bodyLineAngle",
                     minAngle: 155, maxAngle: nil,
                     activeDuringPhases: [],
                     feedbackGood: "Keep your hips level — don't let them pike up!",
                     feedbackDrill: "Hips DOWN! You're not doing downward dog!",
                     severity: "warning", cooldownSeconds: 8),
        ],
        targetMuscles: ["Core", "Hip Flexors", "Shoulders", "Quads", "Chest"],
        minRepDuration: 0.2,
        idealAngles: ["hipFlexionAngle": 80],
        tempoRange: 0.3...1.5
    )
}
