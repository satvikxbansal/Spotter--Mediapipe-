import Foundation

nonisolated enum CueCluster: String, CaseIterable {
    case kneeTracking = "knee-tracking"
    case hipHinge = "hip-hinge"
    case trunkBrace = "trunk-brace"
    case shoulderStack = "shoulder-stack"
    case elbowAlign = "elbow-align"
    case wristNeutral = "wrist-neutral"
    case depthRange = "depth-range"
    case tempoControl = "tempo-control"
    case balanceStability = "balance-stability"
    case headNeck = "head-neck"
    case footPlacement = "foot-placement"
    case breathing
    case other

    var label: String {
        switch self {
        case .kneeTracking:
            return "Knee tracking"
        case .hipHinge:
            return "Hip hinge"
        case .trunkBrace:
            return "Trunk bracing"
        case .shoulderStack:
            return "Shoulder stacking"
        case .elbowAlign:
            return "Elbow alignment"
        case .wristNeutral:
            return "Wrist position"
        case .depthRange:
            return "Depth and range"
        case .tempoControl:
            return "Tempo control"
        case .balanceStability:
            return "Balance and stability"
        case .headNeck:
            return "Head and neck"
        case .footPlacement:
            return "Foot placement"
        case .breathing:
            return "Breathing"
        case .other:
            return "Other cues"
        }
    }
}

nonisolated enum CueClusterTaxonomy {
    static func cluster(for normalized: String) -> CueCluster {
        let cue = CueNormalizer.normalize(normalized)
        guard !cue.isEmpty else { return .other }

        if containsAny(cue, ["breath", "breathe", "inhale", "exhale"]) {
            return .breathing
        }
        if containsAny(cue, ["head to heel", "head to heels"]) {
            return .trunkBrace
        }
        if containsAny(cue, ["head", "neck", "chin", "gaze", "eyes forward", "look forward"]) {
            return .headNeck
        }
        if containsAny(cue, ["wrist", "wrists"]) {
            return .wristNeutral
        }
        if containsAny(cue, ["elbow", "elbows"]) {
            return .elbowAlign
        }
        if cue == "it out" ||
            containsAny(cue, ["shoulder height", "parallel to the floor", "full extension", "fully extend", "extend fully", "all the way", "lockout"]) {
            return .depthRange
        }
        if containsAny(cue, ["shoulder", "shoulders", "trap", "traps", "scapula", "shoulder blade", "shoulder blades"]) {
            return .shoulderStack
        }
        if containsAny(cue, ["depth", "deeper", "parallel", "range", "range of motion", "half rep", "partial", "90 degrees", "right angle", "sink", "get down"]) {
            return .depthRange
        }
        if containsAny(cue, ["knee", "knees", "valgus", "cave", "caving"]) {
            return .kneeTracking
        }
        if containsAny(cue, ["foot", "feet", "heel", "heels", "toe", "toes", "stance", "base", "ankle", "ankles"]) {
            return .footPlacement
        }
        if containsAny(cue, ["balance", "steady", "stable", "stability", "wobble", "wobbling", "centered", "level", "square"]) {
            return .balanceStability
        }
        if containsAny(cue, ["hinge", "hips back", "hip extension", "hips through", "glute", "glutes", "pelvis"]) ||
            cue.contains("hip") && containsAny(cue, ["higher", "thrust", "extension", "line"]) {
            return .hipHinge
        }
        if containsAny(cue, ["brace", "core", "trunk", "torso", "rib", "ribs", "sag", "sagging", "pike", "piking", "back straight", "back flat", "chest up", "chest lifted", "upright", "body line", "straight line", "neutral spine"]) {
            return .trunkBrace
        }
        if containsAny(cue, ["tempo", "rush", "rushing", "slow", "slower", "controlled", "control", "pause", "momentum", "swing", "swinging"]) {
            return .tempoControl
        }

        return .other
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
