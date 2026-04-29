import Foundation
import simd

// ────────────────────────────────────────────────────────────────────
// MARK: - FormFeedbackEngine
// ────────────────────────────────────────────────────────────────────

/// Real-time biomechanical form analyzer that checks joint angles
/// against exercise-specific rules and generates coaching feedback
/// in the selected personality style.
final class FormFeedbackEngine {

    // MARK: - Configuration

    private let globalCooldown: TimeInterval = 3.0
    private let frameCooldown: TimeInterval = 5.0
    private let asymmetryThreshold: Double = 15.0
    private let asymmetryCooldown: TimeInterval = 8.0
    private var ruleCooldowns: [String: Date] = [:]
    private var lastFeedbackTime: Date?
    private var positionalViolationFrames: [String: Int] = [:]

    // MARK: - Feedback Types

    enum FeedbackType: Comparable {
        case bodyPosition
        case framePosition
        case jointVisibility
        case exerciseRule
    }

    struct Feedback: Identifiable {
        let id = UUID()
        let type: FeedbackType
        let message: String
        let severity: CoachCue.Severity
        let ruleId: String?

        var asCoachCue: CoachCue {
            CoachCue(
                message: message,
                severity: severity,
                cooldownSeconds: 5.0
            )
        }
    }

    // MARK: - Public API

    func evaluate(
        joints: [JointName: CGPoint],
        angles: [String: Double],
        phase: RepPhase,
        definition: ExerciseDefinition,
        personality: CoachPersonality,
        bilateralAngles: [String: AngleCalculator.BilateralAngle] = [:],
        worldJoints: [JointName: SIMD3<Float>] = [:],
        frameMask: SegmentationMaskData? = nil
    ) -> [Feedback] {
        var feedbacks: [Feedback] = []

        if let positionFeedback = checkBodyPosition(joints: joints, definition: definition) {
            feedbacks.append(positionFeedback)
            return feedbacks
        }

        if let frameFeedback = checkFramePosition(mask: frameMask, personality: personality) {
            feedbacks.append(frameFeedback)
            return feedbacks
        }

        let visibilityFeedbacks = checkJointVisibility(joints: joints, definition: definition)
        if !visibilityFeedbacks.isEmpty {
            feedbacks.append(contentsOf: visibilityFeedbacks)
            return feedbacks
        }

        if let lastGlobal = lastFeedbackTime {
            guard Date().timeIntervalSince(lastGlobal) > globalCooldown else { return [] }
        }

        let formFeedbacks = checkFormRules(
            angles: angles,
            phase: phase,
            definition: definition,
            personality: personality
        )
        feedbacks.append(contentsOf: formFeedbacks)

        if !definition.positionalChecks.isEmpty {
            let positionalFeedbacks = checkPositionalRules(
                joints2D: joints,
                joints3D: worldJoints,
                phase: phase,
                definition: definition,
                personality: personality
            )
            feedbacks.append(contentsOf: positionalFeedbacks)
        }

        if !bilateralAngles.isEmpty {
            let asymmetryFeedbacks = checkBilateralAsymmetry(
                bilateralAngles: bilateralAngles,
                phase: phase,
                definition: definition,
                personality: personality
            )
            feedbacks.append(contentsOf: asymmetryFeedbacks)
        }

        guard let best = feedbacks.max(by: { $0.severity < $1.severity }) else {
            return []
        }
        if let ruleId = best.ruleId {
            ruleCooldowns[ruleId] = Date()
        }
        lastFeedbackTime = Date()
        return [best]
    }

    func reset() {
        ruleCooldowns.removeAll()
        positionalViolationFrames.removeAll()
        lastFeedbackTime = nil
    }

    // MARK: - Body Position Check

    private func checkBodyPosition(
        joints: [JointName: CGPoint],
        definition: ExerciseDefinition
    ) -> Feedback? {
        if joints.isEmpty {
            return Feedback(
                type: .bodyPosition,
                message: "Step into the frame so the camera can see you",
                severity: .critical,
                ruleId: "body_missing"
            )
        }

        let missingRequired = definition.requiredJoints.filter { joints[$0] == nil }
        if !definition.requiredJoints.isEmpty,
           Double(missingRequired.count) / Double(definition.requiredJoints.count) > 0.5 {
            return Feedback(
                type: .bodyPosition,
                message: "Move further from the camera — show more of your body",
                severity: .warning,
                ruleId: "body_partial"
            )
        }

        return nil
    }

    // MARK: - Frame Position Check

    private func checkFramePosition(
        mask: SegmentationMaskData?,
        personality: CoachPersonality
    ) -> Feedback? {
        guard let mask else { return nil }

        let ruleId = "frame_position"
        let now = Date()

        if let lastFired = ruleCooldowns[ruleId] {
            guard now.timeIntervalSince(lastFired) > frameCooldown else { return nil }
        }
        if let lastGlobal = lastFeedbackTime {
            guard now.timeIntervalSince(lastGlobal) > globalCooldown else { return nil }
        }

        guard let result = FramePositionAnalyzer.analyze(mask),
              result.guidance != .wellPositioned,
              result.guidance != .noBodyDetected,
              let message = FramePositionResult.message(for: result.guidance, personality: personality)
        else { return nil }

        ruleCooldowns[ruleId] = now
        lastFeedbackTime = now

        return Feedback(
            type: .framePosition,
            message: message,
            severity: .warning,
            ruleId: ruleId
        )
    }

    // MARK: - Joint Visibility Check

    private func checkJointVisibility(
        joints: [JointName: CGPoint],
        definition: ExerciseDefinition
    ) -> [Feedback] {
        let missing = definition.requiredJoints.filter { joints[$0] == nil }

        guard !missing.isEmpty else { return [] }

        var messages: [Feedback] = []

        let missingNames = missing.map { $0.displayName }

        let jointList: String
        if missingNames.count <= 2 {
            jointList = missingNames.joined(separator: " and ")
        } else {
            let allButLast = missingNames.dropLast().joined(separator: ", ")
            jointList = "\(allButLast), and \(missingNames.last!)"
        }

        messages.append(Feedback(
            type: .jointVisibility,
            message: "Move your \(jointList) into view",
            severity: .warning,
            ruleId: "joint_visibility"
        ))

        return messages
    }

    // MARK: - Form Rules Check

    private func checkFormRules(
        angles: [String: Double],
        phase: RepPhase,
        definition: ExerciseDefinition,
        personality: CoachPersonality
    ) -> [Feedback] {
        let now = Date()
        var feedbacks: [Feedback] = []

        for rule in definition.formRules {
            if !rule.activeDuringPhases.isEmpty {
                let phaseStr = phase.rawValue
                guard rule.activeDuringPhases.contains(phaseStr) else { continue }
            }

            if let lastFired = ruleCooldowns[rule.id] {
                guard now.timeIntervalSince(lastFired) > rule.cooldownSeconds else { continue }
            }

            guard let angleValue = angles[rule.angleKey] else { continue }

            var violated = false

            if let min = rule.minAngle, angleValue < min {
                violated = true
            }
            if let max = rule.maxAngle, angleValue > max {
                violated = true
            }

            guard violated else { continue }

            let message: String
            switch personality {
            case .good:  message = rule.feedbackGood
            case .drill: message = rule.feedbackDrill
            }

            let severity: CoachCue.Severity
            switch rule.severity {
            case "critical": severity = .critical
            case "warning":  severity = .warning
            default:         severity = .info
            }

            feedbacks.append(Feedback(
                type: .exerciseRule,
                message: message,
                severity: severity,
                ruleId: rule.id
            ))

            break
        }

        return feedbacks
    }

    // MARK: - Positional Rules Check

    private func checkPositionalRules(
        joints2D: [JointName: CGPoint],
        joints3D: [JointName: SIMD3<Float>],
        phase: RepPhase,
        definition: ExerciseDefinition,
        personality: CoachPersonality
    ) -> [Feedback] {
        let now = Date()
        var feedbacks: [Feedback] = []

        let results = AngleCalculator.evaluatePositionalChecks(
            definition.positionalChecks,
            joints2D: joints2D,
            joints3D: joints3D
        )

        for check in definition.positionalChecks {
            if !check.activeDuringPhases.isEmpty {
                let phaseStr = phase.rawValue
                guard check.activeDuringPhases.contains(phaseStr) else { continue }
            }

            if let lastFired = ruleCooldowns[check.id] {
                guard now.timeIntervalSince(lastFired) > check.cooldownSeconds else { continue }
            }
            guard let result = results[check.id], result.violated else { continue }
            positionalViolationFrames[check.id, default: 0] += 1
            guard positionalViolationFrames[check.id, default: 0] >= requiredPersistenceFrames(for: check) else {
                continue
            }

            let message: String
            switch personality {
            case .good:  message = check.feedbackGood
            case .drill: message = check.feedbackDrill
            }

            let severity: CoachCue.Severity
            switch check.severity {
            case "critical": severity = .critical
            case "warning":  severity = .warning
            default:         severity = .info
            }

            feedbacks.append(Feedback(
                type: .exerciseRule,
                message: message,
                severity: severity,
                ruleId: check.id
            ))

            break
        }

        for check in definition.positionalChecks where results[check.id]?.violated != true {
            positionalViolationFrames[check.id] = 0
        }

        return feedbacks
    }

    private func requiredPersistenceFrames(for check: PositionalCheck) -> Int {
        switch check.checkType {
        case .kneeValgus, .heelRise:
            return 3
        default:
            return 1
        }
    }

    // MARK: - Bilateral Asymmetry Check

    private func checkBilateralAsymmetry(
        bilateralAngles: [String: AngleCalculator.BilateralAngle],
        phase: RepPhase,
        definition: ExerciseDefinition,
        personality: CoachPersonality
    ) -> [Feedback] {
        let now = Date()
        var feedbacks: [Feedback] = []

        for angleDef in definition.angles {
            guard angleDef.side == .both || angleDef.side == .bestAvailable else { continue }

            guard let bilateral = bilateralAngles[angleDef.key],
                  let delta = bilateral.delta,
                  delta > asymmetryThreshold else { continue }

            let ruleId = "asymmetry_\(angleDef.key)"

            if let lastFired = ruleCooldowns[ruleId] {
                guard now.timeIntervalSince(lastFired) > asymmetryCooldown else { continue }
            }
            let side: String
            if let l = bilateral.left, let r = bilateral.right {
                side = l < r ? "left" : "right"
            } else {
                side = "one"
            }

            let message: String
            switch personality {
            case .good:
                message = "Your \(side) \(angleDef.label.lowercased()) is off by \(Int(delta))° — try to keep both sides even!"
            case .drill:
                message = "\(Int(delta))° imbalance on your \(side) \(angleDef.label.lowercased())! Even it out NOW!"
            }

            feedbacks.append(Feedback(
                type: .exerciseRule,
                message: message,
                severity: .warning,
                ruleId: ruleId
            ))

            break
        }

        return feedbacks
    }
}
