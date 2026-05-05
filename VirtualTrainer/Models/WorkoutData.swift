import Foundation
import SwiftUI

// ────────────────────────────────────────────────────────────────────
// MARK: - Body Category
// ────────────────────────────────────────────────────────────────────

nonisolated enum BodyCategory: String, CaseIterable, Identifiable {
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

    var exercises: [ExerciseOption] {
        switch self {
        case .upperBody:
            [
                ExerciseOption(type: .bicepCurl, available: true),
                ExerciseOption(type: .pushup, available: true),
                ExerciseOption(type: .lateralRaise, available: true),
                ExerciseOption(type: .frontRaise, available: true),
                ExerciseOption(type: .overheadPress, available: true),
                ExerciseOption(type: .cobraWings, available: true),
                ExerciseOption(type: .overarmReach, available: true),
                ExerciseOption(type: .hammerCurl, available: true),
                ExerciseOption(type: .shoulderPress, available: true),
                ExerciseOption(type: .tricepDip, available: true),
                ExerciseOption(type: .inclinePushup, available: true),
            ]
        case .lowerBody:
            [
                ExerciseOption(type: .squat, available: true),
                ExerciseOption(type: .sumoSquat, available: true),
                ExerciseOption(type: .lunge, available: true),
                ExerciseOption(type: .sideLunge, available: true),
                ExerciseOption(type: .gluteBridge, available: true),
                ExerciseOption(type: .hipAbduction, available: true),
                ExerciseOption(type: .legRaise, available: true),
                ExerciseOption(type: .wallSit, available: true),
                ExerciseOption(type: .deadlift, available: true),
                ExerciseOption(type: .calfRaise, available: true),
                ExerciseOption(type: .romanianDeadlift, available: true),
                ExerciseOption(type: .chairSitToStand, available: true),
                ExerciseOption(type: .hipThrust, available: true),
                ExerciseOption(type: .reverseLunge, available: true),
                ExerciseOption(type: .stepUp, available: true),
                ExerciseOption(type: .donkeyKick, available: true),
            ]
        case .fullBody:
            [
                ExerciseOption(type: .jumpingJack, available: true),
                ExerciseOption(type: .kneeRaise, available: true),
                ExerciseOption(type: .sitUp, available: true),
                ExerciseOption(type: .vUp, available: true),
                ExerciseOption(type: .plank, available: true),
                ExerciseOption(type: .highKnees, available: true),
                ExerciseOption(type: .mountainClimber, available: true),
                ExerciseOption(type: .reverseCrunch, available: true),
                ExerciseOption(type: .russianTwist, available: true),
                ExerciseOption(type: .birdDog, available: true),
                ExerciseOption(type: .sidePlank, available: true),
            ]
        case .yoga:
            [
                ExerciseOption(type: .downwardDog, available: true),
                ExerciseOption(type: .warrior, available: true),
                ExerciseOption(type: .chairPose, available: true),
                ExerciseOption(type: .treePose, available: true),
                ExerciseOption(type: .trianglePose, available: true),
                ExerciseOption(type: .warriorOne, available: true),
                ExerciseOption(type: .warriorThree, available: true),
                ExerciseOption(type: .cobraPose, available: true),
                ExerciseOption(type: .mountainPose, available: true),
            ]
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Exercise Option (for bottom-sheet selection)
// ────────────────────────────────────────────────────────────────────

nonisolated struct ExerciseOption: Identifiable {
    let id: String
    let name: String
    let type: ExerciseType?
    let available: Bool

    init(type: ExerciseType, available: Bool) {
        self.id = type.rawValue
        self.name = type.displayName
        self.type = type
        self.available = available
    }

    init(name: String, available: Bool) {
        self.id = name.lowercased().replacingOccurrences(of: " ", with: "_")
        self.name = name
        self.type = nil
        self.available = available
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Exercise Type
// ────────────────────────────────────────────────────────────────────

/// Every exercise the app can track with the pose estimation pipeline.
/// Adding a new movement means adding a case here and a matching
/// `RepCounter` implementation.
nonisolated enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    // Lower Body
    case squat
    case sumoSquat
    case lunge
    case sideLunge
    case gluteBridge
    case hipAbduction
    case legRaise
    case wallSit
    case deadlift
    case calfRaise
    case romanianDeadlift
    case chairSitToStand
    case hipThrust
    case reverseLunge
    case stepUp
    case donkeyKick

    // Upper Body
    case bicepCurl
    case pushup
    case lateralRaise
    case frontRaise
    case overheadPress
    case cobraWings
    case overarmReach
    case hammerCurl
    case shoulderPress
    case tricepDip
    case inclinePushup

    // Full Body
    case jumpingJack
    case kneeRaise
    case sitUp
    case vUp
    case plank
    case highKnees
    case mountainClimber
    case reverseCrunch
    case russianTwist
    case birdDog
    case sidePlank

    // Yoga
    case downwardDog
    case warrior
    case chairPose
    case treePose
    case trianglePose
    case warriorOne
    case warriorThree
    case cobraPose
    case mountainPose

    var id: String { rawValue }

    /// Looks up the full definition from the ExerciseLibrary.
    var definition: ExerciseDefinition? {
        ExerciseLibrary.definition(for: rawValue)
    }

    var displayName: String {
        definition?.displayName ?? rawValue.capitalized
    }

    /// The primary joint angle key that the rep counter cares about.
    var primaryAngleKey: String {
        definition?.primaryAngleKey ?? "kneeAngle"
    }

    /// Body joints the camera **must** see for this exercise to be
    /// tracked reliably.
    var requiredJoints: [JointName] {
        definition?.requiredJoints ?? [.leftShoulder, .rightShoulder,
                                        .leftHip, .rightHip]
    }

    /// Human-readable summary of what the camera needs to see.
    var visibilityHint: String {
        definition?.visibilityHint ?? "Full body visible"
    }

    /// Whether this is an isometric hold (plank, yoga) vs rep-based.
    var isIsometric: Bool {
        definition?.movementType == .isometric
    }

    /// Camera orientation for this exercise.
    var cameraPosition: CameraPosition {
        definition?.cameraPosition ?? .front
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Workout Set
// ────────────────────────────────────────────────────────────────────

/// A single set within a workout (e.g., "12 squats").
nonisolated struct WorkoutSet: Identifiable, Codable {
    let id: UUID
    let exerciseType: ExerciseType
    let targetReps: Int
    var completedReps: Int

    /// `true` once the user has hit or exceeded the target.
    var isComplete: Bool { completedReps >= targetReps }

    /// 0.0 → 1.0 progress for UI rings / bars.
    var progress: Double {
        guard targetReps > 0 else { return 0 }
        return min(Double(completedReps) / Double(targetReps), 1.0)
    }

    init(
        id: UUID = UUID(),
        exerciseType: ExerciseType,
        targetReps: Int,
        completedReps: Int = 0
    ) {
        self.id = id
        self.exerciseType = exerciseType
        self.targetReps = targetReps
        self.completedReps = completedReps
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Workout Plan
// ────────────────────────────────────────────────────────────────────

/// A complete workout the user picks from the home screen.
nonisolated struct WorkoutPlan: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let exercises: [WorkoutSet]
    let estimatedMinutes: Int

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        exercises: [WorkoutSet],
        estimatedMinutes: Int
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.exercises = exercises
        self.estimatedMinutes = estimatedMinutes
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Workout Plan V2
// ────────────────────────────────────────────────────────────────────

/// Target styles supported by the next workout planner.
nonisolated enum WorkoutTarget: Codable, Equatable, Hashable {
    case reps(Int)
    case hold(seconds: Int)
    case timed(seconds: Int)
    case amrap(seconds: Int?)
    case open

    var formattedText: String {
        switch self {
        case .reps(let count):
            return "\(count) \(count == 1 ? "rep" : "reps")"
        case .hold(let seconds):
            return "\(Self.formatDuration(seconds)) hold"
        case .timed(let seconds):
            return "\(Self.formatDuration(seconds)) work"
        case .amrap(let seconds):
            guard let seconds else { return "AMRAP" }
            return "AMRAP \(Self.formatDuration(seconds))"
        case .open:
            return "Open"
        }
    }

    static func formatTargetText(_ target: WorkoutTarget) -> String {
        target.formattedText
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        guard safeSeconds >= 60 else { return "\(safeSeconds) sec" }

        let minutes = safeSeconds / 60
        let remainingSeconds = safeSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

/// Where a workout plan came from.
nonisolated enum PlanSource: String, Codable, CaseIterable, Equatable, Hashable {
    case generatedLocal
    case template
    case remote
    case aiAssisted
}

/// Role of a workout block inside a plan.
nonisolated enum WorkoutBlockType: String, Codable, CaseIterable, Equatable, Hashable {
    case warmup
    case main
    case circuit
    case finisher
    case cooldown
}

/// High-level section of a generated workout.
nonisolated struct WorkoutBlock: Codable, Equatable {
    let title: String
    let type: WorkoutBlockType
    let exercises: [PlannedExercise]

    init(
        title: String,
        type: WorkoutBlockType,
        exercises: [PlannedExercise]
    ) {
        self.title = title
        self.type = type
        self.exercises = exercises
    }
}

/// One exercise prescription inside a workout block.
nonisolated struct PlannedExercise: Codable, Equatable {
    let exerciseType: ExerciseType
    let sets: [PlannedSet]
    let restSeconds: Int
    let coachingFocus: String
    let cameraPosition: CameraPosition
    let allowSwap: Bool

    init(
        exerciseType: ExerciseType,
        sets: [PlannedSet],
        restSeconds: Int,
        coachingFocus: String,
        cameraPosition: CameraPosition,
        allowSwap: Bool
    ) {
        self.exerciseType = exerciseType
        self.sets = sets
        self.restSeconds = restSeconds
        self.coachingFocus = coachingFocus
        self.cameraPosition = cameraPosition
        self.allowSwap = allowSwap
    }
}

/// One prescribed set. `setIndex` is one-based within its exercise.
nonisolated struct PlannedSet: Codable, Equatable {
    let setIndex: Int
    let target: WorkoutTarget

    init(setIndex: Int, target: WorkoutTarget) {
        self.setIndex = setIndex
        self.target = target
    }
}

/// Structured workout plan for generated, remote, template, and AI-assisted flows.
nonisolated struct WorkoutPlanV2: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let goal: String
    let estimatedMinutes: Int
    let difficulty: ExerciseDifficulty
    let coach: CoachPersonality
    let blocks: [WorkoutBlock]
    let generatedAt: Date
    let planReason: String
    let source: PlanSource

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        goal: String,
        estimatedMinutes: Int,
        difficulty: ExerciseDifficulty,
        coach: CoachPersonality,
        blocks: [WorkoutBlock],
        generatedAt: Date = Date(),
        planReason: String,
        source: PlanSource
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.goal = goal
        self.estimatedMinutes = estimatedMinutes
        self.difficulty = difficulty
        self.coach = coach
        self.blocks = blocks
        self.generatedAt = generatedAt
        self.planReason = planReason
        self.source = source
    }

    init(
        legacy workout: WorkoutPlan,
        goal: String? = nil,
        difficulty: ExerciseDifficulty? = nil,
        coach: CoachPersonality = .good,
        generatedAt: Date = Date(),
        planReason: String = "Converted from the legacy workout plan format.",
        source: PlanSource = .template
    ) {
        self.init(
            id: workout.id,
            title: workout.title,
            subtitle: workout.subtitle,
            goal: goal ?? workout.subtitle,
            estimatedMinutes: workout.estimatedMinutes,
            difficulty: difficulty ?? Self.inferredDifficulty(for: workout.exercises),
            coach: coach,
            blocks: [
                WorkoutBlock(
                    title: "Main Work",
                    type: .main,
                    exercises: Self.convertLegacySets(workout.exercises)
                )
            ],
            generatedAt: generatedAt,
            planReason: planReason,
            source: source
        )
    }

    private static func convertLegacySets(_ sets: [WorkoutSet]) -> [PlannedExercise] {
        var plannedExercises: [PlannedExercise] = []
        var currentExerciseType: ExerciseType?
        var currentSets: [PlannedSet] = []

        func appendCurrentExercise() {
            guard let exerciseType = currentExerciseType else { return }
            plannedExercises.append(
                PlannedExercise(
                    exerciseType: exerciseType,
                    sets: currentSets,
                    restSeconds: ExerciseMetadataCatalog.metadata(for: exerciseType)?.defaultRestSeconds ?? 60,
                    coachingFocus: exerciseType.visibilityHint,
                    cameraPosition: exerciseType.cameraPosition,
                    allowSwap: true
                )
            )
        }

        for legacySet in sets {
            if currentExerciseType != legacySet.exerciseType {
                appendCurrentExercise()
                currentExerciseType = legacySet.exerciseType
                currentSets = []
            }

            let nextIndex = currentSets.count + 1
            currentSets.append(
                PlannedSet(
                    setIndex: nextIndex,
                    target: legacySet.exerciseType.isIsometric
                        ? .hold(seconds: legacySet.targetReps)
                        : .reps(legacySet.targetReps)
                )
            )
        }

        appendCurrentExercise()
        return plannedExercises
    }

    private static func inferredDifficulty(for sets: [WorkoutSet]) -> ExerciseDifficulty {
        let difficulties = sets.compactMap {
            ExerciseMetadataCatalog.metadata(for: $0.exerciseType)?.difficulty
        }

        if difficulties.contains(.advanced) {
            return .advanced
        }
        if difficulties.contains(.intermediate) {
            return .intermediate
        }
        return .beginner
    }
}

extension WorkoutPlan {
    func convertedToV2(
        goal: String? = nil,
        difficulty: ExerciseDifficulty? = nil,
        coach: CoachPersonality = .good,
        generatedAt: Date = Date(),
        planReason: String = "Converted from the legacy workout plan format.",
        source: PlanSource = .template
    ) -> WorkoutPlanV2 {
        WorkoutPlanV2(
            legacy: self,
            goal: goal,
            difficulty: difficulty,
            coach: coach,
            generatedAt: generatedAt,
            planReason: planReason,
            source: source
        )
    }
}

extension WorkoutPlan {

    /// Ready-made plans for previews and first-launch content.
    struct MockData {
        static let all: [WorkoutPlan] = [legDay, upperBody, fullBody]

        static let legDay = WorkoutPlan(
            title: "Leg Day Essentials",
            subtitle: "Quads, glutes, and grit",
            exercises: [
                WorkoutSet(exerciseType: .squat, targetReps: 12),
                WorkoutSet(exerciseType: .squat, targetReps: 12),
                WorkoutSet(exerciseType: .squat, targetReps: 10),
            ],
            estimatedMinutes: 15
        )

        static let upperBody = WorkoutPlan(
            title: "Upper Body Pump",
            subtitle: "Arms and chest, no excuses",
            exercises: [
                WorkoutSet(exerciseType: .bicepCurl, targetReps: 12),
                WorkoutSet(exerciseType: .pushup, targetReps: 15),
                WorkoutSet(exerciseType: .bicepCurl, targetReps: 10),
                WorkoutSet(exerciseType: .pushup, targetReps: 12),
            ],
            estimatedMinutes: 20
        )

        static let fullBody = WorkoutPlan(
            title: "Full Body Quickie",
            subtitle: "Hit everything in under 20 min",
            exercises: [
                WorkoutSet(exerciseType: .squat, targetReps: 10),
                WorkoutSet(exerciseType: .bicepCurl, targetReps: 10),
                WorkoutSet(exerciseType: .pushup, targetReps: 12),
                WorkoutSet(exerciseType: .squat, targetReps: 10),
                WorkoutSet(exerciseType: .bicepCurl, targetReps: 10),
                WorkoutSet(exerciseType: .pushup, targetReps: 10),
            ],
            estimatedMinutes: 18
        )
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Coach Personality
// ────────────────────────────────────────────────────────────────────

/// Two flavours of motivational coaching.
/// Persisted via `@AppStorage` using the raw string value.
nonisolated enum CoachPersonality: String, Codable, CaseIterable, Identifiable {
    case good
    case drill

    var id: String { rawValue }

    var coachName: String {
        switch self {
        case .good:  "Coach Bennett"
        case .drill: "Coach Fletcher"
        }
    }

    var displayName: String {
        switch self {
        case .good:  "The Good Coach"
        case .drill: "The Drill Sergeant"
        }
    }

    var tagline: String {
        switch self {
        case .good:  "Believes in you more than you believe in yourself"
        case .drill: "Not quite my tempo. Were you rushing or dragging?"
        }
    }

    var imageName: String {
        switch self {
        case .good:  "CoachBennet"
        case .drill: "CoachFletcher"
        }
    }

    @MainActor var accentColor: SwiftUI.Color {
        switch self {
        case .good:  Theme.Colors.positive
        case .drill: Theme.Colors.danger
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Coach Cue
// ────────────────────────────────────────────────────────────────────

/// A real-time coaching message generated by the rep counter's
/// form-check logic. These feed into the voice engine and on-screen
/// overlay simultaneously.
nonisolated struct CoachCue: Identifiable, Codable, Equatable {
    let id: UUID
    let message: String
    let severity: Severity
    let cooldownSeconds: TimeInterval

    init(
        id: UUID = UUID(),
        message: String,
        severity: Severity,
        cooldownSeconds: TimeInterval = 5.0
    ) {
        self.id = id
        self.message = message
        self.severity = severity
        self.cooldownSeconds = cooldownSeconds
    }

    /// How urgent the cue is — drives haptic intensity, voice tone,
    /// and overlay color.
    nonisolated enum Severity: String, Codable, Comparable {
        case info
        case warning
        case critical

        private var rank: Int {
            switch self {
            case .info:     0
            case .warning:  1
            case .critical: 2
            }
        }

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rank < rhs.rank
        }
    }
}
