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

    /// Accumulated seconds the user has held the isometric pose.
    /// Always 0 for repetition-based exercises.
    let holdDuration: TimeInterval

    /// Whether the user is currently in the held position.
    let isHolding: Bool

    /// Per-rep form quality score (0–100). `nil` if no rep was just completed.
    let formScore: FormScore?

    init(
        repCount: Int,
        phase: RepPhase,
        cues: [CoachCue],
        holdDuration: TimeInterval = 0,
        isHolding: Bool = false,
        formScore: FormScore? = nil
    ) {
        self.repCount = repCount
        self.phase = phase
        self.cues = cues
        self.holdDuration = holdDuration
        self.isHolding = isHolding
        self.formScore = formScore
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Form Score
// ────────────────────────────────────────────────────────────────────

/// Per-rep form quality assessment combining ROM, tempo, and
/// real-time feedback violations.
struct FormScore {
    /// 0 → 100 composite quality score.
    let score: Int

    /// Letter grade derived from score.
    let grade: Grade

    /// Individual component breakdowns (for UI detail).
    let romPenalty: Int
    let tempoPenalty: Int
    let feedbackPenalty: Int

    enum Grade: String, Comparable {
        case A, B, C, D, F

        private var rank: Int {
            switch self {
            case .A: 4
            case .B: 3
            case .C: 2
            case .D: 1
            case .F: 0
            }
        }

        static func < (lhs: Grade, rhs: Grade) -> Bool {
            lhs.rank < rhs.rank
        }

        static func from(score: Int) -> Grade {
            switch score {
            case 90...100: .A
            case 80..<90:  .B
            case 70..<80:  .C
            case 60..<70:  .D
            default:       .F
            }
        }

        var color: String {
            switch self {
            case .A: "positive"
            case .B: "accent"
            case .C: "accent"
            case .D: "warning"
            case .F: "danger"
            }
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - RepCounter Protocol
// ────────────────────────────────────────────────────────────────────

/// Contract for any exercise-specific rep counting engine.
///
/// Each implementation owns its own state machine, threshold
/// constants, and form-check rules. The pose pipeline feeds it
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
