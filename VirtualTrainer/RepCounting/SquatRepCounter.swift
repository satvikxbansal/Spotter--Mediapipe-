import Foundation
import Vision

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
/// ## State Transitions
///
/// ```
///  ┌─────────┐  knee < downThreshold   ┌──────┐  knee > upThreshold   ┌──────┐
///  │  IDLE   │ ──────────────────────▶ │ DOWN │ ─────────────────────▶│  UP  │
///  └─────────┘                         └──────┘                       └──────┘
///       ▲                                                                │
///       │                    rep counted + form check                    │
///       └────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Joint-Angle Math
///
/// The knee angle is the interior angle at the knee formed by the
/// vectors hip→knee and ankle→knee.  Calculated via `atan2` so it
/// maps cleanly to 0°–180° without quadrant ambiguity.
final class SquatRepCounter: RepCounter {

    let exerciseType: ExerciseType = .squat

    // MARK: - Angle Thresholds (degrees)

    /// Knee angle above which the user is considered "standing."
    /// Full leg extension is ~175°; 160° gives margin for soft lockout.
    private let upThreshold: Double = 160.0

    /// Knee angle below which the user is considered "in the hole."
    /// 110° catches most people before true parallel, giving the
    /// state machine time to latch `down` before the turnaround.
    private let downThreshold: Double = 110.0

    /// The depth we actually want the user to hit for a quality rep.
    /// If the deepest angle during the `down` phase never drops below
    /// this, we fire a "go deeper" cue.
    private let depthTarget: Double = 100.0

    // MARK: - State

    private(set) var repCount: Int = 0
    private(set) var currentPhase: RepPhase = .idle

    /// Tracks the lowest (deepest) knee angle seen during the current
    /// `down` phase. Reset when the phase transitions out of `down`.
    private var deepestAngleInDown: Double = .greatestFiniteMagnitude

    /// Timestamp of the last "go deeper" cue, used to enforce the
    /// cooldown so we don't nag every frame.
    private var lastDepthCueTime: Date?
    private let depthCueCooldown: TimeInterval = 8.0

    // MARK: - Angle Calculation

    /// Interior angle at `midPoint` formed by the vectors
    /// `firstPoint→midPoint` and `lastPoint→midPoint`.
    ///
    /// Uses `atan2` for quadrant-safe results, then converts to
    /// degrees clamped to 0°–180°.
    ///
    /// ```
    ///  firstPoint (hip)
    ///       \
    ///        \ θ ← this angle
    ///         \
    ///    midPoint (knee)
    ///         /
    ///        /
    ///       /
    ///  lastPoint (ankle)
    /// ```
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

        // Normalise into 0…180 — the interior angle can't exceed 180.
        if degrees > 180 { degrees = 360 - degrees }

        return degrees
    }

    // MARK: - Vision Joint Entry Point

    /// Accepts the raw joint dictionary from `PoseEstimator` and
    /// drives the state machine.
    ///
    /// Prefers the right leg (hip-knee-ankle) but falls back to
    /// the left if any right-side joint is missing.
    func processReps(
        joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    ) -> RepCounterOutput {

        // Try right leg first, fall back to left.
        let hip:   CGPoint?
        let knee:  CGPoint?
        let ankle: CGPoint?

        if let rh = joints[.rightHip],
           let rk = joints[.rightKnee],
           let ra = joints[.rightAnkle] {
            hip   = rh
            knee  = rk
            ankle = ra
        } else if let lh = joints[.leftHip],
                  let lk = joints[.leftKnee],
                  let la = joints[.leftAnkle] {
            hip   = lh
            knee  = lk
            ankle = la
        } else {
            return RepCounterOutput(
                repCount: repCount,
                phase: currentPhase,
                cues: []
            )
        }

        let kneeAngle = calculateAngle(
            firstPoint: hip!,
            midPoint: knee!,
            lastPoint: ankle!
        )

        return process(angles: ["kneeAngle": kneeAngle])
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

        // ── IDLE ────────────────────────────────────────────────
        case .idle:
            if kneeAngle < downThreshold {
                currentPhase = .down
                deepestAngleInDown = kneeAngle
            }

        // ── DOWN ────────────────────────────────────────────────
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

        // ── UP ──────────────────────────────────────────────────
        case .up:
            if kneeAngle > upThreshold {
                currentPhase = .idle
            }
        }

        // Fire haptic on the exact frame the rep is counted.
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
    }
}
