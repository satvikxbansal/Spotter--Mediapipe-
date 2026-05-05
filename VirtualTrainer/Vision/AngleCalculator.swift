import Foundation
import simd

private extension AngleDefinition {
    nonisolated var supportsBilateralTelemetry: Bool {
        switch side {
        case .both, .bestAvailable, .moreFlexed, .lessFlexed:
            return true
        case .left, .right:
            return false
        }
    }
}

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
nonisolated enum AngleCalculator {

    // ────────────────────────────────────────────────────────────────
    // MARK: - Public API
    // ────────────────────────────────────────────────────────────────

    static func computeAngles(
        joints: [JointName: CGPoint],
        jointVisibility: [JointName: Float] = [:],
        for definition: ExerciseDefinition
    ) -> [String: Double] {
        var result: [String: Double] = [:]
        result.reserveCapacity(definition.angles.count)

        for angleDef in definition.angles {
            if let angle = computeSingleAngle(
                angleDef,
                joints: joints,
                jointVisibility: jointVisibility
            ) {
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
        joints: [JointName: CGPoint],
        jointVisibility: [JointName: Float] = [:]
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
            return pickBestAvailableValue(def, joints: joints, jointVisibility: jointVisibility)

        case .moreFlexed:
            return pickSideValue(def, joints: joints, preferSmaller: true)

        case .lessFlexed:
            return pickSideValue(def, joints: joints, preferSmaller: false)
        }
    }

    private static func pickBestAvailableValue(
        _ def: AngleDefinition,
        joints: [JointName: CGPoint],
        jointVisibility: [JointName: Float]
    ) -> Double? {
        let left = resolveAndMeasure(def, joints: joints, side: "left")
        let right = resolveAndMeasure(def, joints: joints, side: "right")
        switch (left, right) {
        case let (l?, r?):
            let leftScore = visibilityScore(for: def, side: "left", jointVisibility: jointVisibility)
            let rightScore = visibilityScore(for: def, side: "right", jointVisibility: jointVisibility)
            switch (leftScore, rightScore) {
            case let (ls?, rs?):
                return ls > rs ? l : r
            case (_?, nil):
                return l
            case (nil, _?):
                return r
            case (nil, nil):
                return r
            }
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        case (nil, nil):
            return nil
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

        if def.key == "bodyLineAngle" {
            return measureSignedBodyLine(joints: joints, start: startJoint, mid: midJoint, end: endJoint)
        }
        return measureAngle(joints: joints, start: startJoint, mid: midJoint, end: endJoint)
    }

    private static func pickSideValue(
        _ def: AngleDefinition,
        joints: [JointName: CGPoint],
        preferSmaller: Bool
    ) -> Double? {
        let left = resolveAndMeasure(def, joints: joints, side: "left")
        let right = resolveAndMeasure(def, joints: joints, side: "right")
        switch (left, right) {
        case let (l?, r?):
            return preferSmaller ? min(l, r) : max(l, r)
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        case (nil, nil):
            return nil
        }
    }

    /// Body-line angles need direction: a folded 0-180 angle cannot tell a
    /// push-up sag from a pike. Returns 180 for straight, below 180 for sag,
    /// and above 180 for pike in image coordinates.
    private static func measureSignedBodyLine(
        joints: [JointName: CGPoint],
        start: JointName,
        mid: JointName,
        end: JointName
    ) -> Double? {
        guard let shoulder = joints[start],
              let hip = joints[mid],
              let ankle = joints[end] else { return nil }

        let folded = angle(start: shoulder, mid: hip, end: ankle)
        let deviation = 180.0 - folded
        guard deviation > 0 else { return 180.0 }

        let lineY: CGFloat
        let dx = ankle.x - shoulder.x
        if abs(dx) > 0.0001 {
            let t = (hip.x - shoulder.x) / dx
            lineY = shoulder.y + t * (ankle.y - shoulder.y)
        } else {
            lineY = (shoulder.y + ankle.y) / 2
        }

        if hip.y < lineY {
            return 180.0 + deviation
        } else if hip.y > lineY {
            return 180.0 - deviation
        } else {
            return 180.0
        }
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
            return .root
        case "shoulder_center":
            return .neck
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

        func value(for side: String?) -> Double? {
            switch side {
            case "left": return left
            case "right": return right
            default: return nil
            }
        }

        func selectedSide(preferSmaller: Bool) -> String? {
            switch (left, right) {
            case let (l?, r?):
                return preferSmaller ? (l <= r ? "left" : "right") : (l >= r ? "left" : "right")
            case (_?, nil):
                return "left"
            case (nil, _?):
                return "right"
            case (nil, nil):
                return nil
            }
        }
    }

    /// For each multi-side angle definition, returns
    /// separate left/right measurements (instead of the averaged value).
    static func computeBilateralAngles(
        joints: [JointName: CGPoint],
        for definition: ExerciseDefinition
    ) -> [String: BilateralAngle] {
        var result: [String: BilateralAngle] = [:]
        for angleDef in definition.angles {
            guard angleDef.supportsBilateralTelemetry else { continue }
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
            guard angleDef.supportsBilateralTelemetry else { continue }
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
        jointVisibility: [JointName: Float] = [:],
        for definition: ExerciseDefinition
    ) -> [String: Double] {
        var result: [String: Double] = [:]
        result.reserveCapacity(definition.angles.count)

        for angleDef in definition.angles {
            if angleDef.key == "signedTrunkTwistAngle",
               let angle = signedTrunkTwistAngle(world: joints3D) {
                result[angleDef.key] = angle
            } else if angleDef.key == "trunkTwistMagnitude",
                      let angle = trunkTwistMagnitude(world: joints3D) {
                result[angleDef.key] = angle
            } else if angleDef.key == "bodyLineAngle",
               let angle = computeSingleAngle3D(
                angleDef,
                joints3D: joints3D,
                jointVisibility: jointVisibility
               ) {
                result[angleDef.key] = angle
            } else if let angle = computeSingleAngle3D(
                angleDef,
                joints3D: joints3D,
                jointVisibility: jointVisibility
            ) {
                result[angleDef.key] = angle
            } else if let angle = computeSingleAngle(
                angleDef,
                joints: joints2D,
                jointVisibility: jointVisibility
            ) {
                result[angleDef.key] = angle
            }
        }

        return result
    }

    static func signedTrunkTwistAngle(world joints: [JointName: SIMD3<Float>]) -> Double? {
        guard let leftShoulder = joints[.leftShoulder],
              let rightShoulder = joints[.rightShoulder],
              let leftHip = joints[.leftHip],
              let rightHip = joints[.rightHip]
        else { return nil }

        let shoulderVector = rightShoulder - leftShoulder
        let hipVector = rightHip - leftHip
        let shoulderXZ = SIMD3<Float>(shoulderVector.x, 0, shoulderVector.z)
        let hipXZ = SIMD3<Float>(hipVector.x, 0, hipVector.z)

        guard simd_length(shoulderXZ) > 1e-6,
              simd_length(hipXZ) > 1e-6 else { return nil }

        let shoulderNormal = simd_normalize(shoulderXZ)
        let hipNormal = simd_normalize(hipXZ)
        let dot = min(max(simd_dot(shoulderNormal, hipNormal), -1), 1)
        let unsigned = acos(dot)
        let cross = simd_cross(hipNormal, shoulderNormal)
        let signed = cross.y >= 0 ? unsigned : -unsigned

        return Double(signed) * 180.0 / .pi
    }

    static func trunkTwistMagnitude(world joints: [JointName: SIMD3<Float>]) -> Double? {
        signedTrunkTwistAngle(world: joints).map(abs)
    }

    static func leanBackAngle(
        joints2D: [JointName: CGPoint],
        world joints3D: [JointName: SIMD3<Float>]
    ) -> Double? {
        let angleDef = AngleDefinition(
            key: "leanBackAngle",
            label: "Lean Back",
            startJoint: "shoulder",
            midJoint: "hip",
            endJoint: "knee",
            side: .bestAvailable
        )
        return computeSingleAngle3D(angleDef, joints3D: joints3D)
            ?? computeSingleAngle(angleDef, joints: joints2D)
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
        joints3D: [JointName: SIMD3<Float>],
        jointVisibility: [JointName: Float] = [:]
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
            return pickBestAvailableValue3D(def, joints: joints3D, jointVisibility: jointVisibility)

        case .moreFlexed:
            return pickSideValue3D(def, joints: joints3D, preferSmaller: true)

        case .lessFlexed:
            return pickSideValue3D(def, joints: joints3D, preferSmaller: false)
        }
    }

    private static func pickBestAvailableValue3D(
        _ def: AngleDefinition,
        joints: [JointName: SIMD3<Float>],
        jointVisibility: [JointName: Float]
    ) -> Double? {
        let left = resolveAndMeasure3D(def, joints: joints, side: "left")
        let right = resolveAndMeasure3D(def, joints: joints, side: "right")
        switch (left, right) {
        case let (l?, r?):
            let leftScore = visibilityScore(for: def, side: "left", jointVisibility: jointVisibility)
            let rightScore = visibilityScore(for: def, side: "right", jointVisibility: jointVisibility)
            switch (leftScore, rightScore) {
            case let (ls?, rs?):
                return ls > rs ? l : r
            case (_?, nil):
                return l
            case (nil, _?):
                return r
            case (nil, nil):
                return r
            }
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        case (nil, nil):
            return nil
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

        if def.key == "bodyLineAngle" {
            return measureSignedBodyLine3D(joints: joints, start: startJoint, mid: midJoint, end: endJoint)
        }
        return measureAngle3D(joints: joints, start: startJoint, mid: midJoint, end: endJoint)
    }

    /// 3D signed body line using the vertical displacement of the hip from the
    /// shoulder-to-ankle line. MediaPipe world Y follows the image-space
    /// convention closely enough for this sign: higher hip = pike, lower hip = sag.
    private static func measureSignedBodyLine3D(
        joints: [JointName: SIMD3<Float>],
        start: JointName,
        mid: JointName,
        end: JointName
    ) -> Double? {
        guard let shoulder = joints[start],
              let hip = joints[mid],
              let ankle = joints[end] else { return nil }

        let folded = angle3D(start: shoulder, mid: hip, end: ankle)
        let deviation = 180.0 - folded
        guard deviation > 0 else { return 180.0 }

        let line = ankle - shoulder
        let lineLenSq = simd_dot(line, line)
        guard lineLenSq > 1e-8 else { return 180.0 }

        let t = min(max(simd_dot(hip - shoulder, line) / lineLenSq, 0), 1)
        let closestPoint = shoulder + t * line

        if hip.y < closestPoint.y {
            return 180.0 + deviation
        } else if hip.y > closestPoint.y {
            return 180.0 - deviation
        } else {
            return 180.0
        }
    }

    private static func pickSideValue3D(
        _ def: AngleDefinition,
        joints: [JointName: SIMD3<Float>],
        preferSmaller: Bool
    ) -> Double? {
        let left = resolveAndMeasure3D(def, joints: joints, side: "left")
        let right = resolveAndMeasure3D(def, joints: joints, side: "right")
        switch (left, right) {
        case let (l?, r?):
            return preferSmaller ? min(l, r) : max(l, r)
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        case (nil, nil):
            return nil
        }
    }

    /// Returns the side whose joint triple best represents the computed angle.
    /// This keeps angle overlays and violated-joint highlighting aligned with
    /// active-side rules instead of always drawing the right-side triple.
    static func preferredOverlaySide(
        for def: AngleDefinition,
        joints2D: [JointName: CGPoint],
        joints3D: [JointName: SIMD3<Float>] = [:],
        jointVisibility: [JointName: Float] = [:]
    ) -> String? {
        switch def.side {
        case .left:
            return resolveAndMeasure(def, joints: joints2D, side: "left") != nil ? "left" : nil
        case .right:
            return resolveAndMeasure(def, joints: joints2D, side: "right") != nil ? "right" : nil
        case .both, .bestAvailable:
            let left = resolveAndMeasure(def, joints: joints2D, side: "left")
            let right = resolveAndMeasure(def, joints: joints2D, side: "right")
            switch (left, right) {
            case (_?, _?):
                let leftScore = visibilityScore(for: def, side: "left", jointVisibility: jointVisibility)
                let rightScore = visibilityScore(for: def, side: "right", jointVisibility: jointVisibility)
                if let leftScore, let rightScore {
                    return leftScore > rightScore ? "left" : "right"
                }
                return "right"
            case (_?, nil):
                return "left"
            case (nil, _?):
                return "right"
            case (nil, nil):
                return nil
            }
        case .moreFlexed, .lessFlexed:
            let preferSmaller = def.side == .moreFlexed
            let left3D = resolveAndMeasure3D(def, joints: joints3D, side: "left")
            let right3D = resolveAndMeasure3D(def, joints: joints3D, side: "right")
            let left = left3D ?? resolveAndMeasure(def, joints: joints2D, side: "left")
            let right = right3D ?? resolveAndMeasure(def, joints: joints2D, side: "right")
            switch (left, right) {
            case let (l?, r?):
                return preferSmaller ? (l <= r ? "left" : "right") : (l >= r ? "left" : "right")
            case let (l?, nil):
                return l.isFinite ? "left" : nil
            case let (nil, r?):
                return r.isFinite ? "right" : nil
            case (nil, nil):
                return nil
            }
        }
    }

    private static func visibilityScore(
        for def: AngleDefinition,
        side: String,
        jointVisibility: [JointName: Float]
    ) -> Float? {
        guard
            let triple = resolveJointTriple(for: def, side: side),
            let start = jointVisibility[triple.start],
            let mid = jointVisibility[triple.mid],
            let end = jointVisibility[triple.end]
        else { return nil }

        return (start + mid + end) / 3.0
    }

    static func minimumVisibility(
        for def: AngleDefinition,
        side: String,
        jointVisibility: [JointName: Float]
    ) -> Float? {
        guard let triple = resolveJointTriple(for: def, side: side),
              let start = jointVisibility[triple.start],
              let mid = jointVisibility[triple.mid],
              let end = jointVisibility[triple.end]
        else { return nil }

        return min(start, mid, end)
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
            return evaluateKneeValgus(check, joints2D: joints2D, joints3D: joints3D)

        case .heelRise:
            return evaluateHeelRise(check, joints2D: joints2D)

        case .jointAboveJoint:
            return evaluateJointAboveJoint(check, joints2D: joints2D)

        case .jointAlignedX:
            return evaluateJointAlignedX(check, joints2D: joints2D)

        case .shoulderLevel:
            return evaluateShoulderLevel(check, joints2D: joints2D)

        case .hipRotationStability:
            return evaluateHipRotationStability(check, joints3D: joints3D)
        case .stanceWidth:
            return evaluateStanceWidth(check, joints2D: joints2D)
        case .kneeOverFootLine:
            return evaluateKneeOverFootLine(check, joints2D: joints2D)
        case .kneeOverAnkle:
            return evaluateKneeOverAnkle(check, joints2D: joints2D)
        case .hipBetweenKnees:
            return evaluateHipBetweenKnees(check, joints2D: joints2D)
        case .hipHeightRelativeToLine:
            return evaluateHipHeightRelativeToLine(check, joints2D: joints2D)
        case .pelvisLevel:
            return evaluatePelvisLevel(check, joints2D: joints2D)
        case .shoulderOverSupport:
            return evaluateShoulderOverSupport(check, joints2D: joints2D)
        case .footPlanted:
            return evaluateFootPlanted(check, joints2D: joints2D)
        case .trunkLean:
            return evaluateTrunkLean(check, joints2D: joints2D)
        case .wristOverElbow:
            return evaluateWristOverElbow(check, joints2D: joints2D)
        case .controlledLower, .pauseAtTop:
            // Temporal checks are sourced from rep telemetry rather than a
            // stateless landmark snapshot.
            return nil
        }
    }

    /// Knee valgus: detects if the knee collapses inward past the ankle
    /// in the frontal plane. Measures abs(knee.x - ankle.x) relative to
    /// abs(hip.x - ankle.x). A ratio above threshold means valgus.
    private static func evaluateKneeValgus(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint],
        joints3D: [JointName: SIMD3<Float>]
    ) -> PositionalCheckResult? {
        if let result = evaluateKneeValgus3D(check, joints3D: joints3D) {
            return result
        }

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

    /// 3D knee valgus approximation: project knee-vs-ankle displacement onto
    /// the user's hip-width lateral axis. This keeps the same normalized ratio
    /// semantics as the 2D FPPA-style check while being less sensitive to
    /// camera tilt or slight off-front positioning.
    private static func evaluateKneeValgus3D(
        _ check: PositionalCheck,
        joints3D: [JointName: SIMD3<Float>]
    ) -> PositionalCheckResult? {
        guard let lHip = joints3D[.leftHip], let rHip = joints3D[.rightHip],
              let lKnee = joints3D[.leftKnee], let rKnee = joints3D[.rightKnee],
              let lAnkle = joints3D[.leftAnkle], let rAnkle = joints3D[.rightAnkle]
        else { return nil }

        let hipVector = rHip - lHip
        let hipWidth = simd_length(hipVector)
        guard hipWidth > 1e-4 else { return nil }

        let lateralAxis = hipVector / hipWidth
        let leftInward = simd_dot(lKnee - lAnkle, lateralAxis) / hipWidth
        let rightInward = simd_dot(rAnkle - rKnee, lateralAxis) / hipWidth
        let maxInward = Double(max(leftInward, rightInward))
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

    private static func evaluateHipRotationStability(
        _ check: PositionalCheck,
        joints3D: [JointName: SIMD3<Float>]
    ) -> PositionalCheckResult? {
        guard let leftHip = joints3D[.leftHip],
              let rightHip = joints3D[.rightHip] else { return nil }

        let hipVector = rightHip - leftHip
        let projected = SIMD3<Float>(hipVector.x, 0, hipVector.z)
        guard simd_length(projected) > 1e-6 else { return nil }

        let normalized = simd_normalize(projected)
        let degrees = abs(Double(atan2(normalized.z, normalized.x)) * 180.0 / .pi)
        let acuteDegrees = min(degrees, 180.0 - degrees)
        let violated = acuteDegrees > (check.threshold ?? 15)

        return PositionalCheckResult(key: check.id, violated: violated, value: acuteDegrees)
    }

    private static func evaluateStanceWidth(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let lAnkle = joints2D[.leftAnkle], let rAnkle = joints2D[.rightAnkle],
              let lHip = joints2D[.leftHip], let rHip = joints2D[.rightHip] else { return nil }

        let hipWidth = abs(lHip.x - rHip.x)
        guard hipWidth > 0.01 else { return nil }
        let ratio = abs(lAnkle.x - rAnkle.x) / hipWidth
        let violated = ratio < (check.threshold ?? 1.4)
        return PositionalCheckResult(key: check.id, violated: violated, value: Double(ratio))
    }

    private static func evaluateKneeOverFootLine(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let lHip = joints2D[.leftHip], let rHip = joints2D[.rightHip],
              let lKnee = joints2D[.leftKnee], let rKnee = joints2D[.rightKnee],
              let lFoot = joints2D[.leftFootIndex] ?? joints2D[.leftAnkle],
              let rFoot = joints2D[.rightFootIndex] ?? joints2D[.rightAnkle] else { return nil }

        let hipWidth = abs(lHip.x - rHip.x)
        guard hipWidth > 0.01 else { return nil }
        let leftDrift = abs(lKnee.x - lFoot.x) / hipWidth
        let rightDrift = abs(rKnee.x - rFoot.x) / hipWidth
        let maxDrift = max(leftDrift, rightDrift)
        let violated = maxDrift > (check.threshold ?? 0.35)
        return PositionalCheckResult(key: check.id, violated: violated, value: Double(maxDrift))
    }

    private static func evaluateKneeOverAnkle(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let lKnee = joints2D[.leftKnee], let rKnee = joints2D[.rightKnee],
              let lAnkle = joints2D[.leftAnkle], let rAnkle = joints2D[.rightAnkle],
              let lHip = joints2D[.leftHip], let rHip = joints2D[.rightHip] else { return nil }

        let leftLeg = distance(lHip, lAnkle)
        let rightLeg = distance(rHip, rAnkle)
        let scale = max(max(leftLeg, rightLeg), 0.01)
        let leftDrift = abs(lKnee.x - lAnkle.x) / scale
        let rightDrift = abs(rKnee.x - rAnkle.x) / scale
        let leftKneeAngle = angle(start: lHip, mid: lKnee, end: lAnkle)
        let rightKneeAngle = angle(start: rHip, mid: rKnee, end: rAnkle)
        let drift: CGFloat
        if abs(leftKneeAngle - rightKneeAngle) < 8 {
            drift = max(leftDrift, rightDrift)
        } else {
            drift = leftKneeAngle < rightKneeAngle ? leftDrift : rightDrift
        }
        let violated = drift > (check.threshold ?? 0.18)
        return PositionalCheckResult(key: check.id, violated: violated, value: Double(drift))
    }

    private static func evaluateHipBetweenKnees(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let root = joints2D[.root],
              let lKnee = joints2D[.leftKnee], let rKnee = joints2D[.rightKnee] else { return nil }

        let minX = min(lKnee.x, rKnee.x)
        let maxX = max(lKnee.x, rKnee.x)
        let kneeWidth = max(maxX - minX, 0.01)
        let outside = max(minX - root.x, root.x - maxX, 0) / kneeWidth
        let violated = outside > (check.threshold ?? 0.08)
        return PositionalCheckResult(key: check.id, violated: violated, value: Double(outside))
    }

    private static func evaluateHipHeightRelativeToLine(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let hip = joints2D[.root],
              let shoulder = joints2D[.neck] ?? midpoint(joints2D[.leftShoulder], joints2D[.rightShoulder]),
              let knee = midpoint(joints2D[.leftKnee], joints2D[.rightKnee]) else { return nil }

        let lineLength = max(distance(shoulder, knee), 0.01)
        let normalizedDistance = perpendicularDistance(from: hip, toLineStart: shoulder, end: knee) / lineLength
        let violated = normalizedDistance > (check.threshold ?? 0.12)
        return PositionalCheckResult(key: check.id, violated: violated, value: Double(normalizedDistance))
    }

    private static func evaluatePelvisLevel(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let lHip = joints2D[.leftHip], let rHip = joints2D[.rightHip] else { return nil }

        let shoulderWidth: CGFloat
        if let lShoulder = joints2D[.leftShoulder], let rShoulder = joints2D[.rightShoulder] {
            shoulderWidth = abs(lShoulder.x - rShoulder.x)
        } else {
            shoulderWidth = 0
        }
        let shoulderCenterY = (joints2D[.neck] ?? midpoint(joints2D[.leftShoulder], joints2D[.rightShoulder]))?.y ?? lHip.y
        let hipCenterY = (joints2D[.root] ?? midpoint(lHip, rHip))?.y ?? rHip.y
        let torsoHeight = abs(shoulderCenterY - hipCenterY)
        let scale = max(max(abs(lHip.x - rHip.x), shoulderWidth), max(torsoHeight * 0.5, 0.12))
        let normalizedDrop = abs(lHip.y - rHip.y) / scale
        let violated = normalizedDrop > (check.threshold ?? 0.12)
        return PositionalCheckResult(key: check.id, violated: violated, value: Double(normalizedDrop))
    }

    private static func evaluateShoulderOverSupport(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let shoulder = joints2D[.neck] ?? midpoint(joints2D[.leftShoulder], joints2D[.rightShoulder]) else { return nil }
        let support = midpoint(joints2D[.leftWrist], joints2D[.rightWrist])
            ?? midpoint(joints2D[.leftElbow], joints2D[.rightElbow])
        guard let support else { return nil }

        let drift = abs(shoulder.x - support.x)
        let violated = drift > (check.threshold ?? 0.08)
        return PositionalCheckResult(key: check.id, violated: violated, value: Double(drift))
    }

    private static func evaluateFootPlanted(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        let leftSpan = footSpan(heel: joints2D[.leftHeel], toe: joints2D[.leftFootIndex])
        let rightSpan = footSpan(heel: joints2D[.rightHeel], toe: joints2D[.rightFootIndex])
        guard leftSpan > 0 || rightSpan > 0 else { return nil }

        let maxSpan = max(leftSpan, rightSpan)
        let violated = maxSpan < (check.threshold ?? 0.025)
        return PositionalCheckResult(key: check.id, violated: violated, value: Double(maxSpan))
    }

    private static func evaluateTrunkLean(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let shoulder = joints2D[.neck] ?? midpoint(joints2D[.leftShoulder], joints2D[.rightShoulder]),
              let hip = joints2D[.root] ?? midpoint(joints2D[.leftHip], joints2D[.rightHip]) else { return nil }

        let vertical = max(abs(shoulder.y - hip.y), 0.01)
        let leanRatio = abs(shoulder.x - hip.x) / vertical
        let violated = leanRatio > (check.threshold ?? 0.25)
        return PositionalCheckResult(key: check.id, violated: violated, value: Double(leanRatio))
    }

    private static func evaluateWristOverElbow(
        _ check: PositionalCheck,
        joints2D: [JointName: CGPoint]
    ) -> PositionalCheckResult? {
        guard let lWrist = joints2D[.leftWrist], let rWrist = joints2D[.rightWrist],
              let lElbow = joints2D[.leftElbow], let rElbow = joints2D[.rightElbow],
              let lShoulder = joints2D[.leftShoulder], let rShoulder = joints2D[.rightShoulder] else { return nil }

        let shoulderWidth = max(abs(lShoulder.x - rShoulder.x), 0.01)
        let leftDrift = abs(lWrist.x - lElbow.x) / shoulderWidth
        let rightDrift = abs(rWrist.x - rElbow.x) / shoulderWidth
        let maxDrift = max(leftDrift, rightDrift)
        let violated = maxDrift > (check.threshold ?? 0.35)
        return PositionalCheckResult(key: check.id, violated: violated, value: Double(maxDrift))
    }

    private static func midpoint(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
        guard let a, let b else { return nil }
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func perpendicularDistance(from point: CGPoint, toLineStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let denominator = max(hypot(dx, dy), 0.0001)
        return abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x) / denominator
    }

    private static func footSpan(heel: CGPoint?, toe: CGPoint?) -> CGFloat {
        guard let heel, let toe else { return 0 }
        return distance(heel, toe)
    }
}
