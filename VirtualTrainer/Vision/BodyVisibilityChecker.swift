import Foundation

// ────────────────────────────────────────────────────────────────────
// MARK: - BodyVisibilityChecker
// ────────────────────────────────────────────────────────────────────

/// Evaluates whether the camera can see enough of the user's body
/// to track a given exercise.
///
/// The checker is exercise-agnostic — it pulls `requiredJoints` from
/// `ExerciseType`, so adding a new movement only requires updating
/// that enum.
enum BodyVisibilityChecker {

    // MARK: - Result

    struct Result: Equatable {
        let isReady: Bool
        let visibility: Double
        let message: String?
        let missingJoints: [JointName]
    }

    // MARK: - Evaluate

    static func evaluate(
        joints: [JointName: CGPoint],
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

    // MARK: - Frame-Aware Evaluate

    /// Enhanced evaluation that combines landmark visibility with
    /// segmentation-mask spatial analysis. When the mask is available,
    /// this catches framing problems (too close, clipped edges,
    /// off-center) that landmark visibility alone cannot detect.
    ///
    /// Falls back to landmark-only evaluation when `mask` is nil.
    static func evaluateFrame(
        mask: SegmentationMaskData?,
        joints: [JointName: CGPoint],
        for exerciseType: ExerciseType,
        personality: CoachPersonality = .good
    ) -> Result {
        let landmarkResult = evaluate(joints: joints, for: exerciseType)

        guard landmarkResult.isReady else {
            return landmarkResult
        }

        guard let mask,
              let frameResult = FramePositionAnalyzer.analyze(mask),
              frameResult.guidance != .wellPositioned,
              frameResult.guidance != .noBodyDetected
        else {
            return landmarkResult
        }

        guard let message = FramePositionResult.message(
            for: frameResult.guidance,
            personality: personality
        ) else {
            return landmarkResult
        }

        return Result(
            isReady: false,
            visibility: landmarkResult.visibility,
            message: message,
            missingJoints: []
        )
    }
}
