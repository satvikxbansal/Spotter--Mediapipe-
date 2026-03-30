import Foundation

// ────────────────────────────────────────────────────────────────────
// MARK: - FormFeedbackEngine
// ────────────────────────────────────────────────────────────────────

/// Real-time biomechanical form analyzer that checks joint angles
/// against exercise-specific rules and generates coaching feedback
/// in the selected personality style.
final class FormFeedbackEngine {

    // MARK: - Configuration

    private let globalCooldown: TimeInterval = 3.0
    private var ruleCooldowns: [String: Date] = [:]
    private var lastFeedbackTime: Date?

    // MARK: - Feedback Types

    enum FeedbackType: Comparable {
        case bodyPosition
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
        personality: CoachPersonality
    ) -> [Feedback] {
        var feedbacks: [Feedback] = []

        if let positionFeedback = checkBodyPosition(joints: joints, definition: definition) {
            feedbacks.append(positionFeedback)
            return feedbacks
        }

        let visibilityFeedbacks = checkJointVisibility(joints: joints, definition: definition)
        if !visibilityFeedbacks.isEmpty {
            feedbacks.append(contentsOf: visibilityFeedbacks)
            return feedbacks
        }

        let formFeedbacks = checkFormRules(
            angles: angles,
            phase: phase,
            definition: definition,
            personality: personality
        )
        feedbacks.append(contentsOf: formFeedbacks)

        return feedbacks
    }

    func reset() {
        ruleCooldowns.removeAll()
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

        if joints.count < 4 {
            return Feedback(
                type: .bodyPosition,
                message: "Move further from the camera — show more of your body",
                severity: .warning,
                ruleId: "body_partial"
            )
        }

        return nil
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

            if let lastGlobal = lastFeedbackTime {
                guard now.timeIntervalSince(lastGlobal) > globalCooldown else { continue }
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

            ruleCooldowns[rule.id] = now
            lastFeedbackTime = now

            break
        }

        return feedbacks
    }
}
