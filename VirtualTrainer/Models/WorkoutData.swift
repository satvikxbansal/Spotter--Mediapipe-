import Foundation
import Vision

// ────────────────────────────────────────────────────────────────────
// MARK: - Exercise Type
// ────────────────────────────────────────────────────────────────────

/// Every exercise the app can track with the Vision body-pose pipeline.
/// Adding a new movement means adding a case here and a matching
/// `RepCounter` implementation.
enum ExerciseType: String, Codable, CaseIterable, Identifiable {
    case squat
    case pushup
    case bicepCurl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .squat:     "Squats"
        case .pushup:    "Push-Ups"
        case .bicepCurl: "Bicep Curls"
        }
    }

    /// The primary joint angle key that the rep counter cares about.
    /// Maps to keys in the `[String: Double]` angles dictionary
    /// that the Vision pipeline produces each frame.
    var primaryAngleKey: String {
        switch self {
        case .squat:     "kneeAngle"
        case .pushup:    "elbowAngle"
        case .bicepCurl: "elbowAngle"
        }
    }

    /// Body joints the camera **must** see for this exercise to be
    /// tracked reliably. The visibility checker uses this to decide
    /// whether to show the "step back" banner.
    ///
    /// Add new exercises here — the rest of the pipeline picks it up
    /// automatically.
    var requiredJoints: [VNHumanBodyPoseObservation.JointName] {
        switch self {
        case .squat:
            [.leftHip, .rightHip,
             .leftKnee, .rightKnee,
             .leftAnkle, .rightAnkle,
             .leftShoulder, .rightShoulder]

        case .pushup:
            [.leftShoulder, .rightShoulder,
             .leftElbow, .rightElbow,
             .leftWrist, .rightWrist,
             .leftHip, .rightHip]

        case .bicepCurl:
            [.leftShoulder, .rightShoulder,
             .leftElbow, .rightElbow,
             .leftWrist, .rightWrist]
        }
    }

    /// Human-readable summary of what the camera needs to see.
    /// Shown inside the visibility banner.
    var visibilityHint: String {
        switch self {
        case .squat:     "Full body — hips, knees, and ankles"
        case .pushup:    "Upper body — shoulders, elbows, and wrists"
        case .bicepCurl: "Arms — shoulders, elbows, and wrists"
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Workout Set
// ────────────────────────────────────────────────────────────────────

/// A single set within a workout (e.g., "12 squats").
struct WorkoutSet: Identifiable, Codable {
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
struct WorkoutPlan: Identifiable {
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
// MARK: - Coach Cue
// ────────────────────────────────────────────────────────────────────

/// A real-time coaching message generated by the rep counter's
/// form-check logic. These feed into the voice engine and on-screen
/// overlay simultaneously.
struct CoachCue: Identifiable, Codable, Equatable {
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
    enum Severity: String, Codable, Comparable {
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
