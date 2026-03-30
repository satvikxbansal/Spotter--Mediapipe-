import Foundation
import simd

// ────────────────────────────────────────────────────────────────────
// MARK: - SquatRepCounter
// ────────────────────────────────────────────────────────────────────

/// State-machine rep counter for barbell / bodyweight squats.
///
/// ## Movement Model
///
/// A squat is a single-axis movement driven by the knee angle:
///
/// ```
///  Standing (idle)          Bottom (down)           Standing (up → idle)
///       │                      │                         │
///   knee ≈ 170°           knee ≈ 90°                knee ≈ 170°
///       │                      │                         │
///       └──── eccentric ───────┘──── concentric ─────────┘
///                                                     ↑ rep counted
/// ```
///
/// ## Joint-Angle Math
///
/// Prefers 3D world landmarks (camera-independent, measured in meters)
/// when available. Falls back to 2D normalised coordinates when the
/// world landmark triple is incomplete.
final class SquatRepCounter: RepCounter {

    let exerciseType: ExerciseType = .squat

    // MARK: - Angle Thresholds (degrees)

    private let upThreshold: Double = 150.0
    private let downThreshold: Double = 120.0
    private let depthTarget: Double = 110.0

    // MARK: - State

    private(set) var repCount: Int = 0
    private(set) var currentPhase: RepPhase = .idle
    private(set) var lastKneeAngle: Double?

    private var deepestAngleInDown: Double = .greatestFiniteMagnitude
    private var lastDepthCueTime: Date?
    private let depthCueCooldown: TimeInterval = 8.0

    // MARK: - Angle Calculation (2D fallback)

    func calculateAngle(
        firstPoint: CGPoint,
        midPoint: CGPoint,
        lastPoint: CGPoint
    ) -> Double {
        let v1 = CGVector(dx: firstPoint.x - midPoint.x,
                          dy: firstPoint.y - midPoint.y)
        let v2 = CGVector(dx: lastPoint.x - midPoint.x,
                          dy: lastPoint.y - midPoint.y)

        let angle1 = atan2(v1.dy, v1.dx)
        let angle2 = atan2(v2.dy, v2.dx)

        var degrees = abs(angle1 - angle2) * (180.0 / .pi)
        if degrees > 180 { degrees = 360 - degrees }

        return degrees
    }

    // MARK: - Joint Entry Point

    /// Accepts the raw joint dictionaries from `PoseEstimator` and
    /// drives the state machine. Prefers 3D world landmarks for
    /// camera-independent accuracy.
    func processReps(
        joints: [JointName: CGPoint],
        worldJoints: [JointName: SIMD3<Float>] = [:]
    ) -> RepCounterOutput {

        // Prefer 3D world landmarks when all three joints are available
        if let angle = resolve3DKneeAngle(worldJoints) {
            lastKneeAngle = angle
            return process(angles: ["kneeAngle": angle])
        }

        if let angle = resolve3DHipAngle(worldJoints) {
            lastKneeAngle = angle
            return process(angles: ["kneeAngle": angle])
        }

        // 2D fallback: knee angle (hip -> knee -> ankle)
        if let (h, k, a) = resolveKneeTriple(joints) {
            let kneeAngle = calculateAngle(firstPoint: h, midPoint: k, lastPoint: a)
            lastKneeAngle = kneeAngle
            return process(angles: ["kneeAngle": kneeAngle])
        }

        // 2D fallback: hip angle (shoulder -> hip -> knee)
        if let (s, h, k) = resolveHipTriple(joints) {
            let hipAngle = calculateAngle(firstPoint: s, midPoint: h, lastPoint: k)
            lastKneeAngle = hipAngle
            return process(angles: ["kneeAngle": hipAngle])
        }

        lastKneeAngle = nil
        return RepCounterOutput(
            repCount: repCount,
            phase: currentPhase,
            cues: []
        )
    }

    // MARK: - 3D Joint Resolution

    private func resolve3DKneeAngle(_ joints: [JointName: SIMD3<Float>]) -> Double? {
        if let h = joints[.rightHip], let k = joints[.rightKnee], let a = joints[.rightAnkle] {
            return AngleCalculator.angle3D(start: h, mid: k, end: a)
        }
        if let h = joints[.leftHip], let k = joints[.leftKnee], let a = joints[.leftAnkle] {
            return AngleCalculator.angle3D(start: h, mid: k, end: a)
        }
        return nil
    }

    private func resolve3DHipAngle(_ joints: [JointName: SIMD3<Float>]) -> Double? {
        if let s = joints[.rightShoulder], let h = joints[.rightHip], let k = joints[.rightKnee] {
            return AngleCalculator.angle3D(start: s, mid: h, end: k)
        }
        if let s = joints[.leftShoulder], let h = joints[.leftHip], let k = joints[.leftKnee] {
            return AngleCalculator.angle3D(start: s, mid: h, end: k)
        }
        return nil
    }

    // MARK: - 2D Joint Resolution

    private func resolveKneeTriple(
        _ joints: [JointName: CGPoint]
    ) -> (hip: CGPoint, knee: CGPoint, ankle: CGPoint)? {
        if let h = joints[.rightHip], let k = joints[.rightKnee], let a = joints[.rightAnkle] {
            return (h, k, a)
        }
        if let h = joints[.leftHip], let k = joints[.leftKnee], let a = joints[.leftAnkle] {
            return (h, k, a)
        }
        return nil
    }

    private func resolveHipTriple(
        _ joints: [JointName: CGPoint]
    ) -> (shoulder: CGPoint, hip: CGPoint, knee: CGPoint)? {
        if let s = joints[.rightShoulder], let h = joints[.rightHip], let k = joints[.rightKnee] {
            return (s, h, k)
        }
        if let s = joints[.leftShoulder], let h = joints[.leftHip], let k = joints[.leftKnee] {
            return (s, h, k)
        }
        return nil
    }

    // MARK: - Generic Angle-Dictionary Entry Point

    func process(angles: [String: Double]) -> RepCounterOutput {
        guard let kneeAngle = angles["kneeAngle"] else {
            return RepCounterOutput(
                repCount: repCount,
                phase: currentPhase,
                cues: []
            )
        }

        var cues: [CoachCue] = []
        let previousRepCount = repCount

        switch currentPhase {

        case .idle:
            if kneeAngle < downThreshold {
                currentPhase = .down
                deepestAngleInDown = kneeAngle
            }

        case .down:
            deepestAngleInDown = min(deepestAngleInDown, kneeAngle)

            if kneeAngle > upThreshold {
                currentPhase = .up
                repCount += 1

                if deepestAngleInDown > depthTarget {
                    let shouldCue = lastDepthCueTime.map { date in
                        Date().timeIntervalSince(date) > depthCueCooldown
                    } ?? true

                    if shouldCue {
                        cues.append(CoachCue(
                            message: "Go a bit deeper",
                            severity: .warning,
                            cooldownSeconds: depthCueCooldown
                        ))
                        lastDepthCueTime = Date()
                    }
                }

                deepestAngleInDown = .greatestFiniteMagnitude
                currentPhase = .idle
            }

        case .up:
            if kneeAngle > upThreshold {
                currentPhase = .idle
            }
        }

        if repCount > previousRepCount {
            HapticsEngine.shared.repTick()
        }

        return RepCounterOutput(
            repCount: repCount,
            phase: currentPhase,
            cues: cues
        )
    }

    // MARK: - Reset

    func reset() {
        repCount = 0
        currentPhase = .idle
        deepestAngleInDown = .greatestFiniteMagnitude
        lastDepthCueTime = nil
        lastKneeAngle = nil
    }
}
