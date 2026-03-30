import Foundation
import simd

// ────────────────────────────────────────────────────────────────────
// MARK: - UniversalRepCounter
// ────────────────────────────────────────────────────────────────────

/// A data-driven rep counter that works with **any** `ExerciseDefinition`.
///
/// Instead of writing a custom state machine per exercise (like
/// `SquatRepCounter`), this counter reads thresholds and form rules
/// from the definition and applies them generically.
///
/// Prefers 3D world landmarks for angle calculations when available.
final class UniversalRepCounter: RepCounter {

    // MARK: - Properties

    let exerciseType: ExerciseType
    let definition: ExerciseDefinition

    private(set) var repCount: Int = 0
    private(set) var currentPhase: RepPhase = .idle
    private(set) var holdDuration: TimeInterval = 0

    private var extremeAngleDuringDown: Double?
    private let downIsDecreasing: Bool

    private var lastQualityCueTime: Date?
    private let qualityCueCooldown: TimeInterval = 8.0

    private var holdStartTime: Date?

    private(set) var lastPrimaryAngle: Double?
    private(set) var lastAngles: [String: Double] = [:]

    // MARK: - Init

    init(exerciseType: ExerciseType) {
        self.exerciseType = exerciseType

        self.definition = ExerciseLibrary.definition(for: exerciseType.rawValue)
            ?? ExerciseLibrary.squats

        self.downIsDecreasing = (definition.downThreshold.enterBelow != nil)
    }

    init(definition: ExerciseDefinition) {
        self.definition = definition
        self.exerciseType = ExerciseType(rawValue: definition.id) ?? .squat
        self.downIsDecreasing = (definition.downThreshold.enterBelow != nil)
    }

    // MARK: - Process (Joint Dictionary)

    /// Preferred entry point — uses 3D world landmarks when available,
    /// falling back to 2D for any joint triple that lacks 3D data.
    func processJoints(
        _ joints: [JointName: CGPoint],
        worldJoints: [JointName: SIMD3<Float>] = [:],
        personality: CoachPersonality = .good,
        formEngine: FormFeedbackEngine? = nil
    ) -> RepCounterOutput {
        let angles: [String: Double]
        if worldJoints.isEmpty {
            angles = AngleCalculator.computeAngles(joints: joints, for: definition)
        } else {
            angles = AngleCalculator.computeAngles3D(
                joints2D: joints,
                joints3D: worldJoints,
                for: definition
            )
        }
        lastAngles = angles

        let output = process(angles: angles)

        return output
    }

    // MARK: - Process (Angle Dictionary)

    func process(angles: [String: Double]) -> RepCounterOutput {
        guard let primaryAngle = angles[definition.primaryAngleKey] else {
            return RepCounterOutput(
                repCount: repCount,
                phase: currentPhase,
                cues: []
            )
        }

        lastPrimaryAngle = primaryAngle

        if definition.movementType == .isometric {
            return processIsometric(primaryAngle: primaryAngle, angles: angles)
        } else {
            return processRepetition(primaryAngle: primaryAngle, angles: angles)
        }
    }

    // MARK: - Repetition State Machine

    private func processRepetition(primaryAngle: Double, angles: [String: Double]) -> RepCounterOutput {
        var cues: [CoachCue] = []
        let previousRepCount = repCount

        switch currentPhase {

        case .idle:
            if shouldEnterDown(primaryAngle) {
                currentPhase = .down
                extremeAngleDuringDown = primaryAngle
            }

        case .down:
            updateExtremeAngle(primaryAngle)

            if shouldEnterUp(primaryAngle) {
                currentPhase = .up
                repCount += 1

                if let qualityCue = checkQuality() {
                    cues.append(qualityCue)
                }

                extremeAngleDuringDown = nil
                currentPhase = .idle
            }

        case .up:
            currentPhase = .idle
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

    // MARK: - Isometric State Machine

    private func processIsometric(primaryAngle: Double, angles: [String: Double]) -> RepCounterOutput {
        let inPosition = shouldEnterDown(primaryAngle)

        switch currentPhase {
        case .idle:
            if inPosition {
                currentPhase = .down
                holdStartTime = Date()
            }

        case .down:
            if !inPosition {
                if let start = holdStartTime {
                    holdDuration += Date().timeIntervalSince(start)
                }
                holdStartTime = nil
                currentPhase = .idle
            }

        case .up:
            currentPhase = .idle
        }

        return RepCounterOutput(
            repCount: Int(holdDuration),
            phase: currentPhase,
            cues: []
        )
    }

    // MARK: - Threshold Checks

    private func shouldEnterDown(_ angle: Double) -> Bool {
        if let threshold = definition.downThreshold.enterBelow {
            return angle < threshold
        }
        if let threshold = definition.downThreshold.enterAbove {
            return angle > threshold
        }
        return false
    }

    private func shouldEnterUp(_ angle: Double) -> Bool {
        if let threshold = definition.upThreshold.enterAbove {
            return angle > threshold
        }
        if let threshold = definition.upThreshold.enterBelow {
            return angle < threshold
        }
        return false
    }

    // MARK: - Quality Check

    private func updateExtremeAngle(_ angle: Double) {
        guard let current = extremeAngleDuringDown else {
            extremeAngleDuringDown = angle
            return
        }
        if downIsDecreasing {
            extremeAngleDuringDown = min(current, angle)
        } else {
            extremeAngleDuringDown = max(current, angle)
        }
    }

    private func checkQuality() -> CoachCue? {
        guard let target = definition.qualityTarget,
              let extreme = extremeAngleDuringDown else { return nil }

        if let lastCue = lastQualityCueTime {
            guard Date().timeIntervalSince(lastCue) > qualityCueCooldown else { return nil }
        }

        let missed: Bool
        if definition.qualityTargetIsMinimum {
            missed = extreme < target
        } else {
            missed = extreme > target
        }

        guard missed else { return nil }

        lastQualityCueTime = Date()
        return CoachCue(
            message: "Try for a fuller range of motion",
            severity: .warning,
            cooldownSeconds: qualityCueCooldown
        )
    }

    // MARK: - Reset

    func reset() {
        repCount = 0
        currentPhase = .idle
        holdDuration = 0
        extremeAngleDuringDown = nil
        holdStartTime = nil
        lastQualityCueTime = nil
        lastPrimaryAngle = nil
        lastAngles = [:]
    }
}
