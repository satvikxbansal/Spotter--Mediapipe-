import Foundation
import simd

// ────────────────────────────────────────────────────────────────────
// MARK: - FormFeedbackEngine
// ────────────────────────────────────────────────────────────────────

/// Real-time biomechanical form analyzer that checks joint angles
/// against exercise-specific rules and generates coaching feedback
/// in the selected personality style.
nonisolated final class FormFeedbackEngine {

    // MARK: - Configuration

    private let globalCooldown: TimeInterval = 3.0
    private let frameCooldown: TimeInterval = 5.0
    private let asymmetryThreshold: Double = 15.0
    private let asymmetryCooldown: TimeInterval = 8.0
    private var ruleCooldowns: [String: Date] = [:]
    private var lastFeedbackTime: Date?
    private var positionalViolationFrames: [String: Int] = [:]
    private var russianTwistMaxLeft: Double = 0
    private var russianTwistMaxRight: Double = 0

    // MARK: - Feedback Types

    nonisolated enum FeedbackType: Comparable {
        case bodyPosition
        case framePosition
        case jointVisibility
        case exerciseRule
    }

    nonisolated struct Feedback: Identifiable {
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
        jointVisibility: [JointName: Float] = [:],
        activeSide: String? = nil,
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
            personality: personality,
            jointVisibility: jointVisibility,
            activeSide: activeSide
        )
        feedbacks.append(contentsOf: formFeedbacks)

        if !definition.positionalChecks.isEmpty {
            let positionalFeedbacks = checkPositionalRules(
                joints2D: joints,
                joints3D: worldJoints,
                phase: phase,
                definition: definition,
                personality: personality,
                jointVisibility: jointVisibility
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

        if let twistFeedback = checkRussianTwistAsymmetry(
            angles: angles,
            definition: definition,
            personality: personality
        ) {
            feedbacks.append(twistFeedback)
        }

        guard let best = highestSeverityFeedback(feedbacks) else {
            return []
        }
        if let ruleId = best.ruleId {
            ruleCooldowns[ruleId] = Date()
        }
        lastFeedbackTime = Date()
        return [best]
    }

    private func highestSeverityFeedback(_ feedbacks: [Feedback]) -> Feedback? {
        var best: Feedback?
        for feedback in feedbacks {
            if let currentBest = best {
                if currentBest.severity < feedback.severity {
                    best = feedback
                }
            } else {
                best = feedback
            }
        }
        return best
    }

    func reset() {
        ruleCooldowns.removeAll()
        positionalViolationFrames.removeAll()
        lastFeedbackTime = nil
        russianTwistMaxLeft = 0
        russianTwistMaxRight = 0
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
        personality: CoachPersonality,
        jointVisibility: [JointName: Float],
        activeSide: String?
    ) -> [Feedback] {
        let now = Date()
        var bestFeedback: Feedback?

        for rule in definition.formRules {
            if !rule.activeDuringPhases.isEmpty {
                let phaseStr = phase.rawValue
                guard rule.activeDuringPhases.contains(phaseStr) else { continue }
            }

            if let lastFired = ruleCooldowns[rule.id] {
                guard now.timeIntervalSince(lastFired) > rule.cooldownSeconds else { continue }
            }

            guard let angleValue = angles[rule.angleKey] else { continue }
            guard hasSufficientConfidence(
                for: rule,
                definition: definition,
                jointVisibility: jointVisibility,
                activeSide: activeSide
            ) else { continue }

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
            severity = coachCueSeverity(from: rule.severity)

            let feedback = Feedback(
                type: .exerciseRule,
                message: message,
                severity: severity,
                ruleId: rule.id
            )

            if let currentBest = bestFeedback {
                if currentBest.severity < feedback.severity {
                    bestFeedback = feedback
                }
            } else {
                bestFeedback = feedback
            }
        }

        return bestFeedback.map { [$0] } ?? []
    }

    // MARK: - Positional Rules Check

    private func checkPositionalRules(
        joints2D: [JointName: CGPoint],
        joints3D: [JointName: SIMD3<Float>],
        phase: RepPhase,
        definition: ExerciseDefinition,
        personality: CoachPersonality,
        jointVisibility: [JointName: Float]
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
            guard hasSufficientConfidence(for: check, jointVisibility: jointVisibility) else { continue }
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
            severity = coachCueSeverity(from: check.severity)

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

    private func coachCueSeverity(from rawSeverity: String) -> CoachCue.Severity {
        switch rawSeverity {
        case "critical": .critical
        case "warning": .warning
        default: .info
        }
    }

    private func requiredPersistenceFrames(for check: PositionalCheck) -> Int {
        switch check.checkType {
        case .kneeValgus, .heelRise, .kneeOverFootLine, .footPlanted, .pelvisLevel:
            return 3
        case .hipRotationStability, .hipHeightRelativeToLine:
            return 5
        default:
            return 1
        }
    }

    private func hasSufficientConfidence(
        for rule: FormRule,
        definition: ExerciseDefinition,
        jointVisibility: [JointName: Float],
        activeSide: String?
    ) -> Bool {
        guard !jointVisibility.isEmpty,
              let angleDef = definition.angles.first(where: { $0.key == rule.angleKey })
        else { return true }

        let threshold = confidenceThreshold(for: angleDef)
        switch angleDef.side {
        case .left:
            return sideHasConfidence("left", for: angleDef, threshold: threshold, jointVisibility: jointVisibility)
        case .right:
            return sideHasConfidence("right", for: angleDef, threshold: threshold, jointVisibility: jointVisibility)
        case .both:
            return ["left", "right"].allSatisfy {
                sideHasConfidence($0, for: angleDef, threshold: threshold, jointVisibility: jointVisibility)
            }
        case .bestAvailable:
            return ["left", "right"].contains {
                sideHasConfidence($0, for: angleDef, threshold: threshold, jointVisibility: jointVisibility)
            }
        case .moreFlexed, .lessFlexed:
            if let activeSide {
                return sideHasConfidence(activeSide, for: angleDef, threshold: threshold, jointVisibility: jointVisibility)
            }
            return ["left", "right"].contains {
                sideHasConfidence($0, for: angleDef, threshold: threshold, jointVisibility: jointVisibility)
            }
        }
    }

    private func sideHasConfidence(
        _ side: String,
        for angleDef: AngleDefinition,
        threshold: Float,
        jointVisibility: [JointName: Float]
    ) -> Bool {
        guard let confidence = AngleCalculator.minimumVisibility(
            for: angleDef,
            side: side,
            jointVisibility: jointVisibility
        ) else { return false }
        return confidence >= threshold
    }

    private func allJointsVisible(_ joints: [JointName], threshold: Float, jointVisibility: [JointName: Float]) -> Bool {
        joints.allSatisfy { (jointVisibility[$0] ?? 0) >= threshold }
    }

    private func anyJointGroupVisible(_ groups: [[JointName]], threshold: Float, jointVisibility: [JointName: Float]) -> Bool {
        groups.contains { allJointsVisible($0, threshold: threshold, jointVisibility: jointVisibility) }
    }

    private func positionalConfidenceGroups(for check: PositionalCheck) -> [[JointName]] {
        switch check.checkType {
        case .heelRise, .footPlanted:
            return [
                [.leftHeel, .leftFootIndex],
                [.rightHeel, .rightFootIndex],
            ]
        case .kneeValgus, .kneeOverFootLine:
            return [[.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]]
        case .kneeOverAnkle:
            return [
                [.leftHip, .leftKnee, .leftAnkle],
                [.rightHip, .rightKnee, .rightAnkle],
            ]
        case .wristOverElbow:
            return [[.leftWrist, .rightWrist, .leftElbow, .rightElbow, .leftShoulder, .rightShoulder]]
        case .stanceWidth:
            return [[.leftAnkle, .rightAnkle, .leftHip, .rightHip]]
        case .hipBetweenKnees, .pelvisLevel:
            return [[.leftHip, .rightHip]]
        case .hipHeightRelativeToLine:
            return [[.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee]]
        case .shoulderOverSupport:
            return [
                [.leftShoulder, .rightShoulder, .leftWrist, .rightWrist],
                [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow],
            ]
        case .trunkLean:
            return [[.leftShoulder, .rightShoulder, .leftHip, .rightHip]]
        case .shoulderLevel:
            return [[.leftShoulder, .rightShoulder]]
        case .hipRotationStability:
            return [[.leftHip, .rightHip]]
        case .jointAboveJoint, .jointAlignedX:
            guard let jointA = check.jointA, let jointB = check.jointB else { return [] }
            return [[jointA, jointB]]
        case .controlledLower, .pauseAtTop:
            return []
        }
    }

    private func hasSufficientConfidence(
        for check: PositionalCheck,
        jointVisibility: [JointName: Float]
    ) -> Bool {
        guard !jointVisibility.isEmpty else { return true }

        let threshold: Float = switch check.checkType {
        case .heelRise, .footPlanted:
            0.65
        case .kneeOverFootLine, .kneeOverAnkle, .kneeValgus, .wristOverElbow:
            0.60
        default:
            0.50
        }

        let groups = positionalConfidenceGroups(for: check)
        guard !groups.isEmpty else { return true }
        return anyJointGroupVisible(groups, threshold: threshold, jointVisibility: jointVisibility)
    }

    private func confidenceThreshold(for angleDef: AngleDefinition) -> Float {
        let joints = ["wrist", "ankle", "heel", "footIndex"]
        let key = "\(angleDef.startJoint) \(angleDef.midJoint) \(angleDef.endJoint)"
        return joints.contains { key.contains($0) } ? 0.60 : 0.50
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

    private func checkRussianTwistAsymmetry(
        angles: [String: Double],
        definition: ExerciseDefinition,
        personality: CoachPersonality
    ) -> Feedback? {
        guard definition.id == "russianTwist",
              let signedTwist = angles["signedTrunkTwistAngle"] else { return nil }

        if signedTwist > 0 {
            russianTwistMaxLeft = max(russianTwistMaxLeft, abs(signedTwist))
        } else if signedTwist < 0 {
            russianTwistMaxRight = max(russianTwistMaxRight, abs(signedTwist))
        }

        guard russianTwistMaxLeft > 0, russianTwistMaxRight > 0 else { return nil }
        let delta = abs(russianTwistMaxLeft - russianTwistMaxRight)
        guard delta > 12 else { return nil }

        let ruleId = "russiantwist_asymmetry"
        let now = Date()
        if let lastFired = ruleCooldowns[ruleId] {
            guard now.timeIntervalSince(lastFired) > 10 else { return nil }
        }

        let message: String
        switch personality {
        case .good:
            message = "You're rotating further to one side — try to match both"
        case .drill:
            message = "EVEN it out! You're favoring one side!"
        }

        return Feedback(
            type: .exerciseRule,
            message: message,
            severity: .warning,
            ruleId: ruleId
        )
    }
}
