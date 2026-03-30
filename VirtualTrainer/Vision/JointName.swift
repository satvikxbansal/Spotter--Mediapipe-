import Foundation

// ────────────────────────────────────────────────────────────────────
// MARK: - JointName
// ────────────────────────────────────────────────────────────────────

/// Framework-agnostic body landmark identifiers.
///
/// Maps 1:1 with MediaPipe Pose Landmarker's 33 output indices,
/// plus two synthetic joints (`neck`, `root`) computed as midpoints
/// for compatibility with exercise definitions that reference them.
///
/// Downstream code (angle calculators, rep counters, form engines,
/// overlay views) should use this enum exclusively — never import
/// Vision or MediaPipe directly.
enum JointName: Int, CaseIterable, Hashable, Codable {

    // MediaPipe indices 0–32
    case nose                = 0
    case leftEyeInner        = 1
    case leftEye             = 2
    case leftEyeOuter        = 3
    case rightEyeInner       = 4
    case rightEye            = 5
    case rightEyeOuter       = 6
    case leftEar             = 7
    case rightEar            = 8
    case mouthLeft           = 9
    case mouthRight          = 10
    case leftShoulder        = 11
    case rightShoulder       = 12
    case leftElbow           = 13
    case rightElbow          = 14
    case leftWrist           = 15
    case rightWrist          = 16
    case leftPinky           = 17
    case rightPinky          = 18
    case leftIndex           = 19
    case rightIndex          = 20
    case leftThumb           = 21
    case rightThumb          = 22
    case leftHip             = 23
    case rightHip            = 24
    case leftKnee            = 25
    case rightKnee           = 26
    case leftAnkle           = 27
    case rightAnkle          = 28
    case leftHeel            = 29
    case rightHeel           = 30
    case leftFootIndex       = 31
    case rightFootIndex      = 32

    // Synthetic joints (computed as midpoints)
    case neck                = 100
    case root                = 101

    // MARK: - Display Name

    var displayName: String {
        switch self {
        case .nose:             return "head"
        case .leftEyeInner:     return "left eye"
        case .leftEye:          return "left eye"
        case .leftEyeOuter:     return "left eye"
        case .rightEyeInner:    return "right eye"
        case .rightEye:         return "right eye"
        case .rightEyeOuter:    return "right eye"
        case .leftEar:          return "left ear"
        case .rightEar:         return "right ear"
        case .mouthLeft:        return "mouth"
        case .mouthRight:       return "mouth"
        case .leftShoulder:     return "left shoulder"
        case .rightShoulder:    return "right shoulder"
        case .leftElbow:        return "left elbow"
        case .rightElbow:       return "right elbow"
        case .leftWrist:        return "left wrist"
        case .rightWrist:       return "right wrist"
        case .leftPinky:        return "left pinky"
        case .rightPinky:       return "right pinky"
        case .leftIndex:        return "left index"
        case .rightIndex:       return "right index"
        case .leftThumb:        return "left thumb"
        case .rightThumb:       return "right thumb"
        case .leftHip:          return "left hip"
        case .rightHip:         return "right hip"
        case .leftKnee:         return "left knee"
        case .rightKnee:        return "right knee"
        case .leftAnkle:        return "left ankle"
        case .rightAnkle:       return "right ankle"
        case .leftHeel:         return "left heel"
        case .rightHeel:        return "right heel"
        case .leftFootIndex:    return "left foot"
        case .rightFootIndex:   return "right foot"
        case .neck:             return "neck"
        case .root:             return "torso"
        }
    }

    // MARK: - Skeleton Bone Pairs

    /// Pairs of joints that should be connected with a line for
    /// skeleton overlay rendering. Ordered head → extremities.
    static let bonePairs: [(JointName, JointName)] = [
        // Torso
        (.leftShoulder,  .rightShoulder),
        (.leftShoulder,  .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip,       .rightHip),

        // Left arm
        (.leftShoulder,  .leftElbow),
        (.leftElbow,     .leftWrist),

        // Right arm
        (.rightShoulder, .rightElbow),
        (.rightElbow,    .rightWrist),

        // Left leg
        (.leftHip,       .leftKnee),
        (.leftKnee,      .leftAnkle),
        (.leftAnkle,     .leftHeel),
        (.leftAnkle,     .leftFootIndex),

        // Right leg
        (.rightHip,      .rightKnee),
        (.rightKnee,     .rightAnkle),
        (.rightAnkle,    .rightHeel),
        (.rightAnkle,    .rightFootIndex),

        // Neck / head
        (.neck,          .leftShoulder),
        (.neck,          .rightShoulder),
        (.neck,          .nose),
    ]
}
