import Foundation
import simd

// ────────────────────────────────────────────────────────────────────
// MARK: - UniversalRepCounter
// ────────────────────────────────────────────────────────────────────

/// A data-driven rep counter that works with **any** `ExerciseDefinition`.
///
/// Instead of writing a custom state machine per exercise, this counter reads
/// thresholds and form rules from the definition and applies them generically.
///
/// Prefers 3D world landmarks for angle calculations when available.
nonisolated final class UniversalRepCounter: RepCounter {

    // MARK: - Properties

    let exerciseType: ExerciseType
    let definition: ExerciseDefinition

    private(set) var repCount: Int = 0
    private(set) var currentPhase: RepPhase = .idle
    private(set) var holdDuration: TimeInterval = 0

    private var extremeAngleDuringDown: Double?
    private var extremeAnglesDuringDown: [String: Double] = [:]
    private let downIsDecreasing: Bool

    private var lastQualityCueTime: Date?
    private let qualityCueCooldown: TimeInterval = 8.0

    private var holdStartTime: Date?
    private var pendingActiveSide: String?
    private var lockedActiveSide: String?

    private(set) var lastPrimaryAngle: Double?
    private(set) var lastAngles: [String: Double] = [:]
    private(set) var lastBilateralAngles: [String: AngleCalculator.BilateralAngle] = [:]
    private(set) var lastActiveSide: String?
    private(set) var lastPeakAngularVelocity: Double = 0

    /// Most recent per-rep form score. Published for the UI.
    private(set) var lastFormScore: FormScore?

    /// Running average of all rep form scores in the current set.
    private(set) var averageFormScore: Double = 0
    private var formScoreAccumulator: Double = 0
    private(set) var repRecords: [RepRecord] = []

    // EMA smoothing for angle stability (reduces jitter from 3D world landmarks)
    private var emaAngles: [String: Double] = [:]
    private let emaAlpha: Double = 0.4

    // Hysteresis: require consecutive frames in new phase before transitioning
    private var consecutiveDownFrames: Int = 0
    private var consecutiveUpFrames: Int = 0
    private let hysteresisFrameCount: Int = 2
    private var upPhaseFramesRemaining: Int = 0

    // Min rep duration: prevents false positives from jitter / bouncing
    private var lastRepTime: Date?
    private var minRepDuration: TimeInterval { definition.minRepDuration ?? 0.5 }

    // Tempo tracking for form score
    private var repStartTime: Date?
    private var lastAngleSample: (angle: Double, timestamp: Date)?
    private var peakAngularVelocityDuringRep: Double = 0
    private var repDurations: [TimeInterval] = []

    // Feedback accumulator for current rep
    private(set) var currentRepFeedbackCount: Int = 0

    struct RepRecord {
        let index: Int
        let completedAt: Date
        let duration: TimeInterval
        let peakAngles: [String: Double]
        let formScore: FormScore
        let feedbackCount: Int
        let activeSide: String?
        let peakAngularVelocity: Double
    }

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
        jointVisibility: [JointName: Float] = [:],
        personality: CoachPersonality = .good,
        formEngine: FormFeedbackEngine? = nil
    ) -> RepCounterOutput {
        var angles: [String: Double]
        if worldJoints.isEmpty {
            angles = AngleCalculator.computeAngles(
                joints: joints,
                jointVisibility: jointVisibility,
                for: definition
            )
            lastBilateralAngles = AngleCalculator.computeBilateralAngles(
                joints: joints, for: definition
            )
        } else {
            angles = AngleCalculator.computeAngles3D(
                joints2D: joints,
                joints3D: worldJoints,
                jointVisibility: jointVisibility,
                for: definition
            )
            lastBilateralAngles = AngleCalculator.computeBilateralAngles3D(
                joints2D: joints,
                joints3D: worldJoints,
                for: definition
            )
        }
        updateActiveSideCandidateAndAngles(&angles)
        let output = process(angles: angles)

        return output
    }

    private func updateActiveSideCandidateAndAngles(_ angles: inout [String: Double]) {
        guard let primaryDef = definition.angles.first(where: { $0.key == definition.primaryAngleKey }),
              primaryDef.side == .moreFlexed || primaryDef.side == .lessFlexed,
              let bilateral = lastBilateralAngles[primaryDef.key]
        else {
            pendingActiveSide = nil
            return
        }

        let preferSmaller = primaryDef.side == .moreFlexed
        let selectedSide = lockedActiveSide ?? bilateral.selectedSide(preferSmaller: preferSmaller)
        pendingActiveSide = selectedSide
        lastActiveSide = selectedSide

        if let selectedValue = bilateral.value(for: selectedSide) {
            angles[primaryDef.key] = selectedValue
        }
    }

    // MARK: - Process (Angle Dictionary)

    func process(angles: [String: Double]) -> RepCounterOutput {
        let smoothed = applyEMA(angles)
        lastAngles = smoothed

        guard let primaryAngle = smoothed[definition.primaryAngleKey] else {
            if definition.movementType == .isometric {
                pauseIsometricHoldIfNeeded()
            }

            return RepCounterOutput(
                repCount: repCount,
                phase: currentPhase,
                cues: [],
                holdDuration: definition.movementType == .isometric ? liveHoldDuration : 0,
                isHolding: false
            )
        }

        lastPrimaryAngle = primaryAngle
        updateVelocityTelemetry(primaryAngle)

        if definition.movementType == .isometric {
            return processIsometric(primaryAngle: primaryAngle, angles: smoothed)
        } else {
            return processRepetition(primaryAngle: primaryAngle, angles: smoothed)
        }
    }

    private func applyEMA(_ angles: [String: Double]) -> [String: Double] {
        var smoothed: [String: Double] = [:]
        for (key, raw) in angles {
            if let prev = emaAngles[key] {
                let filtered = emaAlpha * raw + (1.0 - emaAlpha) * prev
                emaAngles[key] = filtered
                smoothed[key] = filtered
            } else {
                emaAngles[key] = raw
                smoothed[key] = raw
            }
        }
        return smoothed
    }

    // MARK: - Repetition State Machine

    private func processRepetition(primaryAngle: Double, angles: [String: Double]) -> RepCounterOutput {
        var cues: [CoachCue] = []
        var completedFormScore: FormScore?

        switch currentPhase {

        case .idle:
            if shouldEnterDown(primaryAngle) {
                consecutiveDownFrames += 1
                if consecutiveDownFrames >= hysteresisFrameCount {
                    currentPhase = .down
                    extremeAngleDuringDown = primaryAngle
                    extremeAnglesDuringDown = angles
                    repStartTime = Date()
                    lockedActiveSide = pendingActiveSide
                    lastActiveSide = lockedActiveSide
                    peakAngularVelocityDuringRep = 0
                    lastPeakAngularVelocity = 0
                    currentRepFeedbackCount = 0
                    consecutiveDownFrames = 0
                }
            } else {
                consecutiveDownFrames = 0
            }

        case .down:
            updateExtremeAngle(primaryAngle)
            updateExtremeAngles(angles)

            if shouldEnterUp(primaryAngle) {
                consecutiveUpFrames += 1
                if consecutiveUpFrames >= hysteresisFrameCount {
                    let now = Date()
                    let timeSinceLastRep = lastRepTime.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
                    guard timeSinceLastRep >= minRepDuration else {
                        consecutiveUpFrames = 0
                        break
                    }

                    currentPhase = .up
                    repCount += 1
                    lastRepTime = now

                    let duration = repStartTime.map { now.timeIntervalSince($0) } ?? 0
                    if duration > 0 {
                        repDurations.append(duration)
                    }

                    completedFormScore = calculateFormScore(feedbackCount: currentRepFeedbackCount)
                    lastFormScore = completedFormScore

                    if repCount > 0 {
                        formScoreAccumulator += Double(completedFormScore?.score ?? 100)
                        averageFormScore = formScoreAccumulator / Double(repCount)
                    }

                    if let qualityCue = checkQuality() {
                        cues.append(qualityCue)
                    }

                    if let completedFormScore {
                        repRecords.append(RepRecord(
                            index: repCount,
                            completedAt: now,
                            duration: duration,
                            peakAngles: extremeAnglesDuringDown,
                            formScore: completedFormScore,
                            feedbackCount: currentRepFeedbackCount,
                            activeSide: lockedActiveSide,
                            peakAngularVelocity: peakAngularVelocityDuringRep
                        ))
                    }

                    extremeAngleDuringDown = nil
                    extremeAnglesDuringDown = [:]
                    consecutiveUpFrames = 0
                    upPhaseFramesRemaining = hysteresisFrameCount
                }
            } else {
                consecutiveUpFrames = 0
            }

        case .up:
            if upPhaseFramesRemaining > 0 {
                upPhaseFramesRemaining -= 1
            } else {
                currentPhase = .idle
                lockedActiveSide = nil
                lastActiveSide = nil
            }
        }

        return RepCounterOutput(
            repCount: repCount,
            phase: currentPhase,
            cues: cues,
            formScore: completedFormScore
        )
    }

    /// Called by FormFeedbackEngine when a cue fires during the current rep.
    func recordFeedbackDuringRep() {
        if currentPhase == .down {
            currentRepFeedbackCount += 1
        }
    }

    // MARK: - Isometric State Machine

    private func processIsometric(primaryAngle: Double, angles: [String: Double]) -> RepCounterOutput {
        let inPosition = isWithinHoldPosition(primaryAngle)

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
            repCount: repCount,
            phase: currentPhase,
            cues: [],
            holdDuration: liveHoldDuration,
            isHolding: currentPhase == .down
        )
    }

    private var liveHoldDuration: TimeInterval {
        if let start = holdStartTime {
            return holdDuration + Date().timeIntervalSince(start)
        }
        return holdDuration
    }

    private func pauseIsometricHoldIfNeeded() {
        guard currentPhase == .down else { return }
        if let start = holdStartTime {
            holdDuration += Date().timeIntervalSince(start)
        }
        holdStartTime = nil
        currentPhase = .idle
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

    private func isWithinHoldPosition(_ angle: Double) -> Bool {
        if let range = definition.holdAngleRange {
            return range.contains(angle)
        }
        return shouldEnterDown(angle)
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

    private func updateExtremeAngles(_ angles: [String: Double]) {
        for (key, value) in angles {
            if let current = extremeAnglesDuringDown[key] {
                if downIsDecreasing {
                    extremeAnglesDuringDown[key] = min(current, value)
                } else {
                    extremeAnglesDuringDown[key] = max(current, value)
                }
            } else {
                extremeAnglesDuringDown[key] = value
            }
        }
    }

    private func updateVelocityTelemetry(_ primaryAngle: Double) {
        let now = Date()
        defer { lastAngleSample = (primaryAngle, now) }

        guard let previous = lastAngleSample else { return }
        let dt = now.timeIntervalSince(previous.timestamp)
        guard dt > 0.001 else { return }

        let velocity = abs(primaryAngle - previous.angle) / dt
        if currentPhase == .down {
            peakAngularVelocityDuringRep = max(peakAngularVelocityDuringRep, velocity)
            lastPeakAngularVelocity = peakAngularVelocityDuringRep
        }
    }

    private func checkQuality() -> CoachCue? {
        if let lastCue = lastQualityCueTime {
            guard Date().timeIntervalSince(lastCue) > qualityCueCooldown else { return nil }
        }

        if !definition.idealAngles.isEmpty {
            let missedIdeal = definition.idealAngles.contains { key, ideal in
                guard let extreme = extremeAnglesDuringDown[key] else { return false }
                return abs(extreme - ideal) > 12
            }
            guard missedIdeal else { return nil }
        } else {
            guard let target = definition.qualityTarget,
                  let extreme = extremeAngleDuringDown else { return nil }
            let missed: Bool
            if definition.qualityTargetIsMinimum {
                missed = extreme < target
            } else {
                missed = extreme > target
            }
            guard missed else { return nil }
        }

        lastQualityCueTime = Date()
        return CoachCue(
            message: "Try for a fuller range of motion",
            severity: .warning,
            cooldownSeconds: qualityCueCooldown
        )
    }

    // MARK: - Form Score Calculation

    private func calculateFormScore(feedbackCount: Int) -> FormScore {
        var score = 100

        let romPenalty = calculateROMPenalty()
        score -= min(romPenalty, 40)

        let tempoPenalty = calculateTempoPenalty()
        score -= min(tempoPenalty, 30)

        let fbPenalty = min(feedbackCount * 10, 30)
        score -= fbPenalty

        score = max(score, 0)

        return FormScore(
            score: score,
            grade: .from(score: score),
            romPenalty: min(romPenalty, 40),
            tempoPenalty: min(tempoPenalty, 30),
            feedbackPenalty: fbPenalty
        )
    }

    /// Angle deviation penalty: how far each tracked angle was from its ideal.
    private func calculateROMPenalty() -> Int {
        let ideals = definition.idealAngles
        guard !ideals.isEmpty else { return 0 }

        var totalDeviation: Double = 0
        var count = 0

        for (key, idealValue) in ideals {
            guard let extremeValue = extremeAnglesDuringDown[key] else { continue }
            let deviation = abs(extremeValue - idealValue)
            totalDeviation += (deviation / 10.0) * 5.0
            count += 1
        }

        guard count > 0 else { return 0 }
        return Int(totalDeviation / Double(count))
    }

    /// Tempo penalty: too fast or too slow relative to the exercise's ideal range.
    private func calculateTempoPenalty() -> Int {
        guard let lastDuration = repDurations.last else { return 0 }

        let range = definition.tempoRange
        if lastDuration < range.lowerBound {
            let deficit = range.lowerBound - lastDuration
            return min(Int((deficit / 0.5) * 15.0), 30)
        } else if lastDuration > range.upperBound {
            let excess = lastDuration - range.upperBound
            return min(Int(excess * 10.0), 30)
        }
        return 0
    }

    // MARK: - Reset

    func reset() {
        repCount = 0
        currentPhase = .idle
        holdDuration = 0
        extremeAngleDuringDown = nil
        extremeAnglesDuringDown = [:]
        holdStartTime = nil
        lastQualityCueTime = nil
        lastPrimaryAngle = nil
        lastAngles = [:]
        lastBilateralAngles = [:]
        lastActiveSide = nil
        pendingActiveSide = nil
        lockedActiveSide = nil
        emaAngles = [:]
        consecutiveDownFrames = 0
        consecutiveUpFrames = 0
        upPhaseFramesRemaining = 0
        lastRepTime = nil
        repStartTime = nil
        lastAngleSample = nil
        peakAngularVelocityDuringRep = 0
        lastPeakAngularVelocity = 0
        repDurations = []
        currentRepFeedbackCount = 0
        lastFormScore = nil
        averageFormScore = 0
        formScoreAccumulator = 0
        repRecords = []
    }
}
