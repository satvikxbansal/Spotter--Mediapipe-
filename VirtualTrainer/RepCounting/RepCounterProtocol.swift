import Foundation

// ────────────────────────────────────────────────────────────────────
// MARK: - Rep Phase
// ────────────────────────────────────────────────────────────────────

/// Where the user is within a single repetition cycle.
///
/// The state machine for every exercise follows the same abstract
/// loop:  `idle → down → up → idle`  (with "up" being the moment
/// the rep is counted).
enum RepPhase: String, Codable {
    /// Standing / resting — waiting for movement to begin.
    case idle
    /// Eccentric portion — the user is lowering into the rep.
    case down
    /// Concentric portion — the user is driving back up.
    /// The rep is counted at the transition from `up` → `idle`.
    case up
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Rep Counter Output
// ────────────────────────────────────────────────────────────────────

/// The packet returned by every `RepCounter.process(angles:)` call.
///
/// The workout ViewModel consumes this each frame to update the UI,
/// fire haptics, and queue voice cues — without knowing which
/// exercise produced it.
struct RepCounterOutput {
    /// Total reps completed so far in this set.
    let repCount: Int

    /// Current phase of the movement cycle.
    let phase: RepPhase

    /// Form-check warnings generated during this frame.
    /// Empty array = form is clean.
    let cues: [CoachCue]
}

// ────────────────────────────────────────────────────────────────────
// MARK: - RepCounter Protocol
// ────────────────────────────────────────────────────────────────────

/// Contract for any exercise-specific rep counting engine.
///
/// Each implementation owns its own state machine, threshold
/// constants, and form-check rules. The Vision pipeline feeds it
/// a dictionary of named joint angles every frame; the
/// implementation returns a `RepCounterOutput`.
///
/// ```
/// let counter: RepCounter = SquatRepCounter()
/// let output = counter.process(angles: ["kneeAngle": 97.3, ...])
/// ```
protocol RepCounter: AnyObject {

    /// The exercise this counter is built for.
    var exerciseType: ExerciseType { get }

    /// Current accumulated rep count.
    var repCount: Int { get }

    /// Current movement phase.
    var currentPhase: RepPhase { get }

    /// Ingests a frame's worth of joint angles and returns the
    /// updated rep state + any coaching cues.
    ///
    /// - Parameter angles: Keys are human-readable joint names
    ///   (e.g. `"kneeAngle"`, `"elbowAngle"`, `"hipAngle"`).
    ///   Values are degrees (0–180).
    func process(angles: [String: Double]) -> RepCounterOutput

    /// Resets internal state for a new set.
    func reset()
}
