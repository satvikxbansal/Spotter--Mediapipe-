import Foundation
import simd

// ────────────────────────────────────────────────────────────────────
// MARK: - AngleCalculator
// ────────────────────────────────────────────────────────────────────

/// Computes all joint angles defined by an `ExerciseDefinition` from
/// raw body-pose landmarks.
///
/// ## Design
///
/// The calculator is stateless — it takes a joint dictionary and an
/// exercise definition, and returns a dictionary of named angles.
///
/// ## Coordinate Space
///
/// Supports both 2D (normalised top-left, 0…1) and 3D (world
/// coordinates in meters with hip-center origin). The 3D path uses
/// SIMD vectors for accurate camera-independent angles.
///
/// The preferred call path is `computeAngles3D` when world landmarks
/// are available, falling back to the 2D variant when they aren't.
enum AngleCalculator {

    // ────────────────────────────────────────────────────────────────
    // MARK: - Public API
    // ────────────────────────────────────────────────────────────────

    static func computeAngles(
        joints: [JointName: CGPoint],
        for definition: ExerciseDefinition
    ) -> [String: Double] {
        var result: [String: Double] = [:]
        result.reserveCapacity(definition.angles.count)

        for angleDef in definition.angles {
            if let angle = computeSingleAngle(angleDef, joints: joints) {
                result[angleDef.key] = angle
            }
        }

        return result
    }

    /// Computes all possible body angles from the current joints,
    /// independent of any exercise. Useful for ROM display.
    static func computeAllAngles(
        joints: [JointName: CGPoint]
    ) -> [String: Double] {
        var result: [String: Double] = [:]

        // Elbows
        if let angle = measureAngle(joints: joints, start: .rightShoulder, mid: .rightElbow, end: .rightWrist) {
            result["rightElbowAngle"] = angle
        }
        if let angle = measureAngle(joints: joints, start: .leftShoulder, mid: .leftElbow, end: .leftWrist) {
            result["leftElbowAngle"] = angle
        }

        // Shoulders (arm raise relative to torso)
        if let angle = measureAngle(joints: joints, start: .rightHip, mid: .rightShoulder, end: .rightElbow) {
            result["rightShoulderAngle"] = angle
        }
        if let angle = measureAngle(joints: joints, start: .leftHip, mid: .leftShoulder, end: .leftElbow) {
            result["leftShoulderAngle"] = angle
        }

        // Shoulder abduction (hip→shoulder→wrist)
        if let angle = measureAngle(joints: joints, start: .rightHip, mid: .rightShoulder, end: .rightWrist) {
            result["rightShoulderAbductionAngle"] = angle
        }
        if let angle = measureAngle(joints: joints, start: .leftHip, mid: .leftShoulder, end: .leftWrist) {
            result["leftShoulderAbductionAngle"] = angle
        }

        // Knees
        if let angle = measureAngle(joints: joints, start: .rightHip, mid: .rightKnee, end: .rightAnkle) {
            result["rightKneeAngle"] = angle
        }
        if let angle = measureAngle(joints: joints, start: .leftHip, mid: .leftKnee, end: .leftAnkle) {
            result["leftKneeAngle"] = angle
        }

        // Hips (shoulder→hip→knee)
        if let angle = measureAngle(joints: joints, start: .rightShoulder, mid: .rightHip, end: .rightKnee) {
            result["rightHipAngle"] = angle
        }
        if let angle = measureAngle(joints: joints, start: .leftShoulder, mid: .leftHip, end: .leftKnee) {
            result["leftHipAngle"] = angle
        }

        // Hip flexion (shoulder→hip→ankle)
        if let angle = measureAngle(joints: joints, start: .rightShoulder, mid: .rightHip, end: .rightAnkle) {
            result["rightHipFlexionAngle"] = angle
        }
        if let angle = measureAngle(joints: joints, start: .leftShoulder, mid: .leftHip, end: .leftAnkle) {
            result["leftHipFlexionAngle"] = angle
        }

        // Body line (shoulder→hip→ankle)
        if let angle = measureAngle(joints: joints, start: .rightShoulder, mid: .rightHip, end: .rightAnkle) {
            result["rightBodyLineAngle"] = angle
        }
        if let angle = measureAngle(joints: joints, start: .leftShoulder, mid: .leftHip, end: .leftAnkle) {
            result["leftBodyLineAngle"] = angle
        }

        return result
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Core Angle Math
    // ────────────────────────────────────────────────────────────────

    /// Interior angle at `midPoint` formed by vectors
    /// `startPoint→midPoint` and `endPoint→midPoint`.
    /// Returns degrees 0°–180°.
    static func angle(
        start: CGPoint,
        mid: CGPoint,
        end: CGPoint
    ) -> Double {
        let v1 = CGVector(dx: start.x - mid.x, dy: start.y - mid.y)
        let v2 = CGVector(dx: end.x - mid.x, dy: end.y - mid.y)

        let angle1 = atan2(v1.dy, v1.dx)
        let angle2 = atan2(v2.dy, v2.dx)

        var degrees = abs(angle1 - angle2) * (180.0 / .pi)
        if degrees > 180 { degrees = 360 - degrees }

        return degrees
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Private Helpers
    // ────────────────────────────────────────────────────────────────

    private static func measureAngle(
        joints: [JointName: CGPoint],
        start: JointName,
        mid: JointName,
        end: JointName
    ) -> Double? {
        guard let s = joints[start], let m = joints[mid], let e = joints[end] else {
            return nil
        }
        return angle(start: s, mid: m, end: e)
    }

    private static func computeSingleAngle(
        _ def: AngleDefinition,
        joints: [JointName: CGPoint]
    ) -> Double? {
        switch def.side {
        case .left:
            return resolveAndMeasure(def, joints: joints, side: "left")

        case .right:
            return resolveAndMeasure(def, joints: joints, side: "right")

        case .both:
            let left = resolveAndMeasure(def, joints: joints, side: "left")
            let right = resolveAndMeasure(def, joints: joints, side: "right")
            switch (left, right) {
            case let (l?, r?): return (l + r) / 2.0
            case let (l?, nil): return l
            case let (nil, r?): return r
            case (nil, nil): return nil
            }

        case .bestAvailable:
            if let right = resolveAndMeasure(def, joints: joints, side: "right") {
                return right
            }
            return resolveAndMeasure(def, joints: joints, side: "left")
        }
    }

    private static func resolveAndMeasure(
        _ def: AngleDefinition,
        joints: [JointName: CGPoint],
        side: String
    ) -> Double? {
        guard
            let startJoint = resolveJointName(def.startJoint, side: side),
            let midJoint = resolveJointName(def.midJoint, side: side),
            let endJoint = resolveJointName(def.endJoint, side: side)
        else { return nil }

        return measureAngle(joints: joints, start: startJoint, mid: midJoint, end: endJoint)
    }

    /// Resolves the three `JointName`s (start, mid, end) for an
    /// `AngleDefinition` given a side preference. Returns `nil` if
    /// any joint cannot be resolved.
    static func resolveJointTriple(
        for def: AngleDefinition,
        side: String = "right"
    ) -> (start: JointName, mid: JointName, end: JointName)? {
        guard
            let s = resolveJointName(def.startJoint, side: side),
            let m = resolveJointName(def.midJoint, side: side),
            let e = resolveJointName(def.endJoint, side: side)
        else { return nil }
        return (s, m, e)
    }

    /// Maps abstract joint names used in `AngleDefinition` to
    /// `JointName` values. Supports both sided (e.g. "shoulder" →
    /// `.leftShoulder`) and center joints (e.g. "nose" → `.nose`).
    static func resolveJointName(
        _ name: String,
        side: String
    ) -> JointName? {
        switch name {
        case "hip_center":
            return side == "left" ? .leftHip : .rightHip
        case "shoulder_center":
            return side == "left" ? .leftShoulder : .rightShoulder
        case "knee_left":
            return .leftKnee
        case "knee_right":
            return .rightKnee
        case "ankle_left":
            return .leftAnkle
        case "ankle_right":
            return .rightAnkle
        case "wrist_left":
            return .leftWrist
        case "wrist_right":
            return .rightWrist
        default:
            break
        }

        switch name {
        case "shoulder": return side == "left" ? .leftShoulder : .rightShoulder
        case "elbow":    return side == "left" ? .leftElbow : .rightElbow
        case "wrist":    return side == "left" ? .leftWrist : .rightWrist
        case "hip":      return side == "left" ? .leftHip : .rightHip
        case "knee":     return side == "left" ? .leftKnee : .rightKnee
        case "ankle":    return side == "left" ? .leftAnkle : .rightAnkle
        case "heel":     return side == "left" ? .leftHeel : .rightHeel
        case "footIndex": return side == "left" ? .leftFootIndex : .rightFootIndex

        case "heel_left":      return .leftHeel
        case "heel_right":     return .rightHeel
        case "footIndex_left": return .leftFootIndex
        case "footIndex_right": return .rightFootIndex

        case "nose":     return .nose
        case "neck":     return .neck
        case "root":     return .root

        default:
            return nil
        }
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Bilateral Angle Pairs
    // ────────────────────────────────────────────────────────────────

    struct BilateralAngle {
        let left: Double?
        let right: Double?

        var delta: Double? {
            guard let l = left, let r = right else { return nil }
            return abs(l - r)
        }
    }

    /// For each `.both` or `.bestAvailable` angle definition, returns
    /// separate left/right measurements (instead of the averaged value).
    static func computeBilateralAngles(
        joints: [JointName: CGPoint],
        for definition: ExerciseDefinition
    ) -> [String: BilateralAngle] {
        var result: [String: BilateralAngle] = [:]
        for angleDef in definition.angles {
            guard angleDef.side == .both || angleDef.side == .bestAvailable else { continue }
            let left = resolveAndMeasure(angleDef, joints: joints, side: "left")
            let right = resolveAndMeasure(angleDef, joints: joints, side: "right")
            result[angleDef.key] = BilateralAngle(left: left, right: right)
        }
        return result
    }

    /// 3D variant that prefers world landmarks, falling back to 2D.
    static func computeBilateralAngles3D(
        joints2D: [JointName: CGPoint],
        joints3D: [JointName: SIMD3<Float>],
        for definition: ExerciseDefinition
    ) -> [String: BilateralAngle] {
        var result: [String: BilateralAngle] = [:]
        for angleDef in definition.angles {
            guard angleDef.side == .both || angleDef.side == .bestAvailable else { continue }
            let left3D = resolveAndMeasure3D(angleDef, joints: joints3D, side: "left")
            let right3D = resolveAndMeasure3D(angleDef, joints: joints3D, side: "right")
            let left = left3D ?? resolveAndMeasure(angleDef, joints: joints2D, side: "left")
            let right = right3D ?? resolveAndMeasure(angleDef, joints: joints2D, side: "right")
            result[angleDef.key] = BilateralAngle(left: left, right: right)
        }
        return result
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - 3D World Landmark Angles
    // ────────────────────────────────────────────────────────────────

    /// Preferred path — uses 3D world coordinates for camera-independent
    /// angle accuracy. Falls back to 2D if world landmarks are unavailable
    /// for a given joint triple.
    static func computeAngles3D(
        joints2D: [JointName: CGPoint],
        joints3D: [JointName: SIMD3<Float>],
        for definition: ExerciseDefinition
    ) -> [String: Double] {
        var result: [String: Double] = [:]
        result.reserveCapacity(definition.angles.count)

        for angleDef in definition.angles {
            if let angle = computeSingleAngle3D(angleDef, joints3D: joints3D) {
                result[angleDef.key] = angle
            } else if let angle = computeSingleAngle(angleDef, joints: joints2D) {
                result[angleDef.key] = angle
            }
        }

        return result
    }

    /// Interior angle at `mid` formed by vectors `start→mid` and
    /// `end→mid` using 3D world coordinates. Returns degrees 0-180.
    static func angle3D(
        start: SIMD3<Float>,
        mid: SIMD3<Float>,
        end: SIMD3<Float>
    ) -> Double {
        let v1 = start - mid
        let v2 = end - mid

        let len1 = simd_length(v1)
        let len2 = simd_length(v2)
        guard len1 > 1e-6 && len2 > 1e-6 else { return 0 }

        let cosAngle = simd_dot(v1, v2) / (len1 * len2)
        let clamped = min(max(cosAngle, -1.0), 1.0)
        return Double(acos(clamped)) * (180.0 / .pi)
    }

    private static func measureAngle3D(
        joints: [JointName: SIMD3<Float>],
        start: JointName,
        mid: JointName,
        end: JointName
    ) -> Double? {
        guard let s = joints[start], let m = joints[mid], let e = joints[end] else {
            return nil
        }
        return angle3D(start: s, mid: m, end: e)
    }

    private static func computeSingleAngle3D(
        _ def: AngleDefinition,
        joints3D: [JointName: SIMD3<Float>]
    ) -> Double? {
        switch def.side {
        case .left:
            return resolveAndMeasure3D(def, joints: joints3D, side: "left")

        case .right:
            return resolveAndMeasure3D(def, joints: joints3D, side: "right")

        case .both:
            let left = resolveAndMeasure3D(def, joints: joints3D, side: "left")
            let right = resolveAndMeasure3D(def, joints: joints3D, side: "right")
            switch (left, right) {
            case let (l?, r?): return (l + r) / 2.0
            case let (l?, nil): return l
            case let (nil, r?): return r
            case (nil, nil): return nil
            }

        case .bestAvailable:
            if let right = resolveAndMeasure3D(def, joints: joints3D, side: "right") {
                return right
            }
            return resolveAndMeasure3D(def, joints: joints3D, side: "left")
        }
    }

    private static func resolveAndMeasure3D(
        _ def: AngleDefinition,
        joints: [JointName: SIMD3<Float>],
        side: String
    ) -> Double? {
        guard
            let startJoint = resolveJointName(def.startJoint, side: side),
            let midJoint = resolveJointName(def.midJoint, side: side),
            let endJoint = resolveJointName(def.endJoint, side: side)
        else { return nil }

        return measureAngle3D(joints: joints, start: startJoint, mid: midJoint, end: endJoint)
    }

    // ────────────────────────────────────────────────────────────────
    // MARK: - Positional Checks
    // ────────────────────────────────────────────────────────────────

    /// Result of a positional / spatial check on body landmarks.
    struct PositionalCheckResult {
        let key: String
        let violated: Bool
        let value: Double
    }

    /// Runs all positional checks defined for an exercise.
    /// Returns keyed results that the `FormFeedbackEngine` can consume.
    static func evaluatePositionalChecks(
        _ checks: [PositionalCheck],
        joints2D: [JointName: CGPoint],
        joints3D: [JointName: SIMD3<Float>]
    ) -> [String: PositionalCheckResult] {
        var results: [String: PositionalCheckResult] = [:]
        for check in checks {
            if let result = evaluateSingleCheck(check, joints2D: joints2D, joints3D: joints3D) {
                results[check.id] = result
            }
        }
        return results
    }

    private static func evaluateSingleCheck(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint],
        joints3D: [JointName: SIMD3<Float>]
    ) -> PositionalCheckResult? {
        switch check.checkType {
        case .kneeValgus:
            return evaluateKneeValgus(check, joints2D: joints2D)

        case .heelRise:
            return evaluateHeelRise(check, joints2D: joints2D)

        case .jointAboveJoint:
            return evaluateJointAboveJoint(check, joints2D: joints2D)

        case .jointAlignedX:
            return evaluateJointAlignedX(check, joints2D: joints2D)

        case .shoulderLevel:
            return evaluateShoulderLevel(check, joints2D: joints2D)
        }
    }

    /// Knee valgus: detects if the knee collapses inward past the ankle
    /// in the frontal plane. Measures abs(knee.x - ankle.x) relative to
    /// abs(hip.x - ankle.x). A ratio above threshold means valgus.
    private static func evaluateKneeValgus(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let lHip = joints2D[.leftHip], let rHip = joints2D[.rightHip],
              let lKnee = joints2D[.leftKnee], let rKnee = joints2D[.rightKnee],
              let lAnkle = joints2D[.leftAnkle], let rAnkle = joints2D[.rightAnkle]
        else { return nil }

        let hipWidth = abs(lHip.x - rHip.x)
        guard hipWidth > 0.01 else { return nil }

        let leftInward = (lKnee.x - lAnkle.x) / hipWidth
        let rightInward = (rAnkle.x - rKnee.x) / hipWidth

        let maxInward = max(leftInward, rightInward)
        let violated = maxInward > (check.threshold ?? 0.15)

        return PositionalCheckResult(key: check.id, violated: violated, value: maxInward)
    }

    /// Heel rise: detects if the heel landmark rises above the
    /// foot-index landmark, indicating the user has come up on their toes.
    private static func evaluateHeelRise(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        let leftRise: CGFloat
        let rightRise: CGFloat

        if let heel = joints2D[.leftHeel], let toe = joints2D[.leftFootIndex] {
            leftRise = toe.y - heel.y
        } else { leftRise = 0 }

        if let heel = joints2D[.rightHeel], let toe = joints2D[.rightFootIndex] {
            rightRise = toe.y - heel.y
        } else { rightRise = 0 }

        let maxRise = max(leftRise, rightRise)
        let violated = maxRise > (check.threshold ?? 0.02)

        return PositionalCheckResult(key: check.id, violated: violated, value: Double(maxRise))
    }

    /// Checks whether one joint's Y coordinate is above another's.
    /// Uses `jointA` and `jointB` from the check; violated when
    /// jointA.y < jointB.y (higher on screen) by more than threshold.
    private static func evaluateJointAboveJoint(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let jointA = check.jointA, let jointB = check.jointB,
              let ptA = joints2D[jointA], let ptB = joints2D[jointB]
        else { return nil }

        let diff = ptB.y - ptA.y
        let violated = diff > (check.threshold ?? 0.02)

        return PositionalCheckResult(key: check.id, violated: violated, value: Double(diff))
    }

    /// Checks whether two joints are roughly aligned on the X axis.
    /// Violated when abs(jointA.x - jointB.x) exceeds threshold
    /// (normalized to frame width 0-1).
    private static func evaluateJointAlignedX(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let jointA = check.jointA, let jointB = check.jointB,
              let ptA = joints2D[jointA], let ptB = joints2D[jointB]
        else { return nil }

        let diff = abs(ptA.x - ptB.x)
        let violated = diff > (check.threshold ?? 0.05)

        return PositionalCheckResult(key: check.id, violated: violated, value: Double(diff))
    }

    /// Checks whether the left and right shoulders are at roughly the
    /// same Y level. Violated when abs(delta Y) exceeds threshold.
    private static func evaluateShoulderLevel(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let lShoulder = joints2D[.leftShoulder],
              let rShoulder = joints2D[.rightShoulder]
        else { return nil }

        let diff = abs(lShoulder.y - rShoulder.y)
        let violated = diff > (check.threshold ?? 0.03)

        return PositionalCheckResult(key: check.id, violated: violated, value: Double(diff))
    }
}
