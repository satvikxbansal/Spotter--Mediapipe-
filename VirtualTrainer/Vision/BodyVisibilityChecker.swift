import Vision

// ────────────────────────────────────────────────────────────────────
// MARK: - BodyVisibilityChecker
// ────────────────────────────────────────────────────────────────────

/// Evaluates whether the camera can see enough of the user's body
/// to track a given exercise.
///
/// The checker is exercise-agnostic — it pulls `requiredJoints` from
/// `ExerciseType`, so adding a new movement only requires updating
/// that enum. No changes needed here.
///
/// ## Usage
///
/// ```swift
/// let result = BodyVisibilityChecker.evaluate(
///     joints: poseEstimator.bodyJoints,
///     for: .squat
/// )
///
/// if !result.isReady {
///     // show banner with result.message
/// }
/// ```
enum BodyVisibilityChecker {

    // MARK: - Result

    struct Result: Equatable {
        /// `true` when every required joint is detected.
        let isReady: Bool

        /// 0…1 ratio of visible required joints. Drives progress
        /// indicators or partial-visibility states.
        let visibility: Double

        /// User-facing instruction when `isReady == false`.
        /// `nil` when all joints are visible.
        let message: String?

        /// The specific joint names that are still missing.
        let missingJoints: [VNHumanBodyPoseObservation.JointName]
    }

    // MARK: - Evaluate

    /// Check the detected joints against the requirements for
    /// `exerciseType` and return a visibility report.
    static func evaluate(
        joints: [VNHumanBodyPoseObservation.JointName: CGPoint],
        for exerciseType: ExerciseType
    ) -> Result {
        let required = exerciseType.requiredJoints

        guard !required.isEmpty else {
            return Result(isReady: true, visibility: 1, message: nil, missingJoints: [])
        }

        let missing = required.filter { joints[$0] == nil }
        let visibleCount = required.count - missing.count
        let visibility = Double(visibleCount) / Double(required.count)

        if missing.isEmpty {
            return Result(isReady: true, visibility: 1, message: nil, missingJoints: [])
        }

        let message: String
        if joints.isEmpty {
            message = "Step into the frame so the camera can see you"
        } else {
            message = "Move back so your \(exerciseType.visibilityHint.lowercased()) are visible"
        }

        return Result(
            isReady: false,
            visibility: visibility,
            message: message,
            missingJoints: missing
        )
    }
}
