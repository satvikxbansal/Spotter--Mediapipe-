import Foundation
import CoreGraphics

// ────────────────────────────────────────────────────────────────────
// MARK: - FramePositionAnalyzer
// ────────────────────────────────────────────────────────────────────

/// Analyzes the segmentation mask produced by `PoseEstimator` to
/// determine how well the user is positioned within the camera frame.
///
/// Unlike landmark-based visibility (which answers "are the joints
/// detected?"), mask analysis answers spatial questions:
///   - Is the body centered?
///   - Is the body clipped by frame edges?
///   - Is the user too close or too far?
///
/// The analyzer is stateless — it takes a `SegmentationMaskData`
/// snapshot and returns a `FramePositionResult` with guidance.
enum FramePositionAnalyzer {

    // MARK: - Thresholds

    /// Minimum per-pixel confidence to count as "body."
    private static let pixelThreshold: Float = 0.5

    /// Fraction of frame edge to consider the "margin zone."
    /// Body probability in this zone indicates edge clipping.
    private static let edgeMarginFraction: Double = 0.03

    /// Body coverage below this means the user is too far away.
    private static let minCoverage: Double = 0.05

    /// Body coverage above this means the user is too close.
    private static let maxCoverage: Double = 0.55

    /// Centroid offset from 0.5 beyond which the body is "off-center."
    private static let centerToleranceX: Double = 0.15
    private static let centerToleranceY: Double = 0.15

    /// Fraction of edge-margin pixels that must be "body" to flag
    /// truncation on that edge.
    private static let edgeTruncationThreshold: Double = 0.05

    // MARK: - Public API

    /// Analyze a segmentation mask and produce positioning guidance.
    /// Returns `nil` when the mask is empty or zero-sized.
    static func analyze(_ mask: SegmentationMaskData) -> FramePositionResult? {
        let w = mask.width
        let h = mask.height
        guard w > 0, h > 0 else { return nil }

        let totalPixels = w * h
        let data = mask.data

        var bodyCount = 0
        var sumX: Double = 0
        var sumY: Double = 0

        var minX = w, maxX = 0
        var minY = h, maxY = 0

        for y in 0..<h {
            let rowOffset = y * w
            for x in 0..<w {
                let val = data[rowOffset + x]
                guard val > pixelThreshold else { continue }
                bodyCount += 1
                let dval = Double(val)
                sumX += Double(x) * dval
                sumY += Double(y) * dval
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }

        guard bodyCount > 0 else {
            return FramePositionResult(
                coverage: 0,
                centroid: CGPoint(x: 0.5, y: 0.5),
                boundingBox: .zero,
                edgeTruncation: [],
                guidance: .noBodyDetected
            )
        }

        let coverage = Double(bodyCount) / Double(totalPixels)

        let totalWeight = data.reduce(0.0) { acc, v in
            v > pixelThreshold ? acc + Double(v) : acc
        }
        let centroidX = totalWeight > 0 ? sumX / totalWeight / Double(w - 1) : 0.5
        let centroidY = totalWeight > 0 ? sumY / totalWeight / Double(h - 1) : 0.5

        let bbox = CGRect(
            x: Double(minX) / Double(w),
            y: Double(minY) / Double(h),
            width: Double(maxX - minX) / Double(w),
            height: Double(maxY - minY) / Double(h)
        )

        let truncatedEdges = detectEdgeTruncation(data: data, width: w, height: h)

        let guidance = determineGuidance(
            coverage: coverage,
            centroidX: centroidX,
            centroidY: centroidY,
            truncatedEdges: truncatedEdges
        )

        return FramePositionResult(
            coverage: coverage,
            centroid: CGPoint(x: centroidX, y: centroidY),
            boundingBox: bbox,
            edgeTruncation: truncatedEdges,
            guidance: guidance
        )
    }

    // MARK: - Edge Truncation Detection

    /// Checks each frame edge for significant body probability in the
    /// outermost margin zone. Returns the set of edges where the body
    /// silhouette is being clipped.
    private static func detectEdgeTruncation(
        data: [Float],
        width w: Int,
        height h: Int
    ) -> Set<FrameEdge> {
        var truncated = Set<FrameEdge>()

        let marginX = max(Int(Double(w) * edgeMarginFraction), 1)
        let marginY = max(Int(Double(h) * edgeMarginFraction), 1)

        // Top edge: rows 0..<marginY
        var topBody = 0, topTotal = 0
        for y in 0..<marginY {
            let rowOffset = y * w
            for x in 0..<w {
                topTotal += 1
                if data[rowOffset + x] > pixelThreshold { topBody += 1 }
            }
        }
        if topTotal > 0 && Double(topBody) / Double(topTotal) > edgeTruncationThreshold {
            truncated.insert(.top)
        }

        // Bottom edge: rows (h - marginY)..<h
        var bottomBody = 0, bottomTotal = 0
        for y in (h - marginY)..<h {
            let rowOffset = y * w
            for x in 0..<w {
                bottomTotal += 1
                if data[rowOffset + x] > pixelThreshold { bottomBody += 1 }
            }
        }
        if bottomTotal > 0 && Double(bottomBody) / Double(bottomTotal) > edgeTruncationThreshold {
            truncated.insert(.bottom)
        }

        // Left edge: columns 0..<marginX
        var leftBody = 0, leftTotal = 0
        for y in 0..<h {
            let rowOffset = y * w
            for x in 0..<marginX {
                leftTotal += 1
                if data[rowOffset + x] > pixelThreshold { leftBody += 1 }
            }
        }
        if leftTotal > 0 && Double(leftBody) / Double(leftTotal) > edgeTruncationThreshold {
            truncated.insert(.left)
        }

        // Right edge: columns (w - marginX)..<w
        var rightBody = 0, rightTotal = 0
        for y in 0..<h {
            let rowOffset = y * w
            for x in (w - marginX)..<w {
                rightTotal += 1
                if data[rowOffset + x] > pixelThreshold { rightBody += 1 }
            }
        }
        if rightTotal > 0 && Double(rightBody) / Double(rightTotal) > edgeTruncationThreshold {
            truncated.insert(.right)
        }

        return truncated
    }

    // MARK: - Guidance Logic

    /// Prioritized guidance based on mask metrics. Edge clipping is
    /// highest priority, then distance (coverage), then centering.
    private static func determineGuidance(
        coverage: Double,
        centroidX: Double,
        centroidY: Double,
        truncatedEdges: Set<FrameEdge>
    ) -> FrameGuidance {
        if !truncatedEdges.isEmpty {
            return .bodyClipped(edges: truncatedEdges)
        }

        if coverage > maxCoverage {
            return .tooClose
        }

        if coverage < minCoverage {
            return .tooFar
        }

        let offsetX = centroidX - 0.5
        let offsetY = centroidY - 0.5

        if abs(offsetX) > centerToleranceX {
            let direction: FrameGuidance.Direction = offsetX > 0 ? .right : .left
            return .offCenter(direction: direction)
        }

        if abs(offsetY) > centerToleranceY {
            let direction: FrameGuidance.Direction = offsetY > 0 ? .down : .up
            return .offCenter(direction: direction)
        }

        return .wellPositioned
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - FrameEdge
// ────────────────────────────────────────────────────────────────────

/// An edge of the camera frame where body clipping can occur.
enum FrameEdge: String, Hashable {
    case top, bottom, left, right
}

// ────────────────────────────────────────────────────────────────────
// MARK: - FrameGuidance
// ────────────────────────────────────────────────────────────────────

/// The type of positioning correction the user needs.
enum FrameGuidance: Equatable {
    case wellPositioned
    case tooClose
    case tooFar
    case offCenter(direction: Direction)
    case bodyClipped(edges: Set<FrameEdge>)
    case noBodyDetected

    enum Direction: String {
        case left, right, up, down
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - FramePositionResult
// ────────────────────────────────────────────────────────────────────

/// Complete analysis of the user's spatial positioning within the
/// camera frame, derived from the segmentation mask.
struct FramePositionResult: Equatable {
    /// Fraction of frame pixels occupied by the body (0-1).
    let coverage: Double

    /// Weighted center of the body silhouette in normalized coords.
    let centroid: CGPoint

    /// Tight bounding box of the body in normalized coords.
    let boundingBox: CGRect

    /// Frame edges where the body silhouette is being clipped.
    let edgeTruncation: Set<FrameEdge>

    /// The primary positioning correction needed.
    let guidance: FrameGuidance

    /// Human-readable coaching message for the Good Coach personality.
    var messageGood: String? {
        Self.message(for: guidance, personality: .good)
    }

    /// Human-readable coaching message for the Drill Sergeant personality.
    var messageDrill: String? {
        Self.message(for: guidance, personality: .drill)
    }

    /// Returns the coaching message for a given personality, or `nil`
    /// when the user is well-positioned or no body is detected.
    static func message(
        for guidance: FrameGuidance,
        personality: CoachPersonality
    ) -> String? {
        switch guidance {
        case .wellPositioned, .noBodyDetected:
            return nil

        case .tooClose:
            switch personality {
            case .good:
                return "You're too close — take a step back so the camera can see your full body"
            case .drill:
                return "Back UP! You're practically kissing the camera!"
            }

        case .tooFar:
            switch personality {
            case .good:
                return "You're a bit far away — step closer to the camera"
            case .drill:
                return "Get CLOSER! I can barely see you over there!"
            }

        case .offCenter(let direction):
            switch direction {
            case .left:
                switch personality {
                case .good:  return "Shift a bit to your right to center yourself"
                case .drill: return "CENTER yourself! Move to the right!"
                }
            case .right:
                switch personality {
                case .good:  return "Shift a bit to your left to center yourself"
                case .drill: return "CENTER yourself! Move to the left!"
                }
            case .up:
                switch personality {
                case .good:  return "You're too high in frame — move the camera up or step back"
                case .drill: return "Fix your position! You're too high in the frame!"
                }
            case .down:
                switch personality {
                case .good:  return "You're too low in frame — move the camera down or step back"
                case .drill: return "Fix your position! You're too low in the frame!"
                }
            }

        case .bodyClipped(let edges):
            return clippedMessage(edges: edges, personality: personality)
        }
    }

    /// Builds a message describing which edges are clipping the body.
    /// Prioritizes top/bottom (head/feet) over left/right.
    private static func clippedMessage(
        edges: Set<FrameEdge>,
        personality: CoachPersonality
    ) -> String {
        if edges.contains(.top) && edges.contains(.bottom) {
            switch personality {
            case .good:
                return "Your head and feet are cut off — step back from the camera"
            case .drill:
                return "I can't see your head OR feet! Step BACK!"
            }
        }

        if edges.contains(.top) {
            switch personality {
            case .good:
                return "Your head is cut off — step back or lower your phone"
            case .drill:
                return "I can't see your head! Fix your camera angle NOW!"
            }
        }

        if edges.contains(.bottom) {
            switch personality {
            case .good:
                return "Your feet are cut off — step back or raise your phone"
            case .drill:
                return "Your feet are out of frame! Step back!"
            }
        }

        if edges.contains(.left) && edges.contains(.right) {
            switch personality {
            case .good:
                return "You're too close — step back so your full body is in frame"
            case .drill:
                return "Back UP! You're spilling off both sides of the screen!"
            }
        }

        if edges.contains(.left) {
            switch personality {
            case .good:
                return "You're too far left — shift to your right"
            case .drill:
                return "Move RIGHT! You're falling off the screen!"
            }
        }

        // .right
        switch personality {
        case .good:
            return "You're too far right — shift to your left"
        case .drill:
            return "Move LEFT! Center yourself!"
        }
    }
}
