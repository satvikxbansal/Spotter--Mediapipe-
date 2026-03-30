import SwiftUI

// ────────────────────────────────────────────────────────────────────
// MARK: - TrainerOverlayView
// ────────────────────────────────────────────────────────────────────

/// Draws the detected body and hand skeletons over the live camera feed.
///
/// Joint positions arrive as normalised 0…1 values (already in
/// SwiftUI's top-left coordinate space thanks to `PoseEstimator`).
/// A `GeometryReader` maps them to screen pixels, then a `Canvas`
/// renders bones and joint dots in a single draw pass.
///
/// ## Visual Style
///
/// Unified white skeleton with a subtle luminous glow. Body bones
/// are slightly thicker than hand bones to convey hierarchy, but
/// both share the same color palette for a cohesive look.
struct TrainerOverlayView: View {

    let bodyJoints: [JointName: CGPoint]
    var allHandLandmarks: [[Int: CGPoint]] = []

    // MARK: - Unified Color Palette

    private static let skeletonWhite = Color.white
    private static let glowColor = Color.white.opacity(0.35)

    // MARK: - Body Skeleton Metrics

    private let bodyBoneWidth: CGFloat = 5
    private let bodyBoneOpacity: Double = 1.0
    private let bodyJointRadius: CGFloat = 5

    // MARK: - Hand Skeleton Metrics

    private let handBoneWidth: CGFloat = 2.5
    private let handBoneOpacity: Double = 1.0
    private let handJointRadius: CGFloat = 3
    private let handTipRadius: CGFloat = 4

    private static let fingerTipIndices: Set<Int> = [4, 8, 12, 16, 20]

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                drawBodyBones(context: &context, size: size)
                drawBodyJoints(context: &context, size: size)
                for hand in allHandLandmarks {
                    drawHandBones(context: &context, size: size, landmarks: hand)
                    drawHandJoints(context: &context, size: size, landmarks: hand)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Body Skeleton Drawing

    private func drawBodyBones(context: inout GraphicsContext, size: CGSize) {
        var bonePath = Path()

        for (from, to) in JointName.bonePairs {
            guard let a = bodyJoints[from], let b = bodyJoints[to] else { continue }
            bonePath.move(to: screenPoint(a, in: size))
            bonePath.addLine(to: screenPoint(b, in: size))
        }

        context.opacity = bodyBoneOpacity
        context.stroke(
            bonePath,
            with: .color(Self.skeletonWhite),
            style: StrokeStyle(lineWidth: bodyBoneWidth, lineCap: .round)
        )
        context.opacity = 1
    }

    private func drawBodyJoints(context: inout GraphicsContext, size: CGSize) {
        for (_, point) in bodyJoints {
            let screen = screenPoint(point, in: size)
            let r = bodyJointRadius

            let rect = CGRect(
                x: screen.x - r, y: screen.y - r,
                width: r * 2, height: r * 2
            )

            context.fill(Path(ellipseIn: rect), with: .color(Self.skeletonWhite))

            let glowRect = rect.insetBy(dx: -2.5, dy: -2.5)
            context.opacity = 0.25
            context.stroke(
                Path(ellipseIn: glowRect),
                with: .color(Self.skeletonWhite),
                style: StrokeStyle(lineWidth: 2)
            )
            context.opacity = 1
        }
    }

    // MARK: - Hand Skeleton Drawing

    private func drawHandBones(context: inout GraphicsContext, size: CGSize, landmarks: [Int: CGPoint]) {
        var handPath = Path()

        for (from, to) in HandGestureDetector.handBonePairs {
            guard let a = landmarks[from], let b = landmarks[to] else { continue }
            handPath.move(to: screenPoint(a, in: size))
            handPath.addLine(to: screenPoint(b, in: size))
        }

        context.opacity = handBoneOpacity
        context.stroke(
            handPath,
            with: .color(Self.skeletonWhite),
            style: StrokeStyle(lineWidth: handBoneWidth, lineCap: .round)
        )
        context.opacity = 1
    }

    private func drawHandJoints(context: inout GraphicsContext, size: CGSize, landmarks: [Int: CGPoint]) {
        for (index, point) in landmarks {
            let screen = screenPoint(point, in: size)
            let isTip = Self.fingerTipIndices.contains(index)
            let r = isTip ? handTipRadius : handJointRadius

            let rect = CGRect(
                x: screen.x - r, y: screen.y - r,
                width: r * 2, height: r * 2
            )

            context.fill(Path(ellipseIn: rect), with: .color(Self.skeletonWhite))

            if isTip {
                let glowRect = rect.insetBy(dx: -2, dy: -2)
                context.opacity = 0.3
                context.stroke(
                    Path(ellipseIn: glowRect),
                    with: .color(Self.skeletonWhite),
                    style: StrokeStyle(lineWidth: 1.5)
                )
                context.opacity = 1
            }
        }
    }

    // MARK: - Helpers

    private func screenPoint(_ pt: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: pt.x * size.width, y: pt.y * size.height)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ────────────────────────────────────────────────────────────────────

#Preview("Skeleton Overlay — Mock Pose") {
    ZStack {
        Color.black.ignoresSafeArea()

        TrainerOverlayView(
            bodyJoints: TrainerOverlayView.mockJoints,
            allHandLandmarks: [TrainerOverlayView.mockHandLandmarks]
        )
    }
}

extension TrainerOverlayView {
    /// A plausible standing pose for Xcode previews.
    static let mockJoints: [JointName: CGPoint] = [
        .nose:           CGPoint(x: 0.50, y: 0.12),
        .neck:           CGPoint(x: 0.50, y: 0.18),
        .leftShoulder:   CGPoint(x: 0.42, y: 0.22),
        .rightShoulder:  CGPoint(x: 0.58, y: 0.22),
        .leftElbow:      CGPoint(x: 0.36, y: 0.35),
        .rightElbow:     CGPoint(x: 0.64, y: 0.35),
        .leftWrist:      CGPoint(x: 0.34, y: 0.48),
        .rightWrist:     CGPoint(x: 0.66, y: 0.48),
        .leftHip:        CGPoint(x: 0.44, y: 0.50),
        .rightHip:       CGPoint(x: 0.56, y: 0.50),
        .leftKnee:       CGPoint(x: 0.43, y: 0.68),
        .rightKnee:      CGPoint(x: 0.57, y: 0.68),
        .leftAnkle:      CGPoint(x: 0.42, y: 0.85),
        .rightAnkle:     CGPoint(x: 0.58, y: 0.85),
        .leftHeel:       CGPoint(x: 0.41, y: 0.87),
        .rightHeel:      CGPoint(x: 0.59, y: 0.87),
        .leftFootIndex:  CGPoint(x: 0.43, y: 0.88),
        .rightFootIndex: CGPoint(x: 0.57, y: 0.88),
    ]

    /// A plausible open-hand pose for Xcode previews (right hand near right wrist).
    static let mockHandLandmarks: [Int: CGPoint] = [
         0: CGPoint(x: 0.66, y: 0.48),  // wrist
         1: CGPoint(x: 0.64, y: 0.47),  // thumbCMC
         2: CGPoint(x: 0.62, y: 0.45),  // thumbMCP
         3: CGPoint(x: 0.61, y: 0.43),  // thumbIP
         4: CGPoint(x: 0.60, y: 0.41),  // thumbTIP
         5: CGPoint(x: 0.65, y: 0.44),  // indexMCP
         6: CGPoint(x: 0.65, y: 0.42),  // indexPIP
         7: CGPoint(x: 0.65, y: 0.40),  // indexDIP
         8: CGPoint(x: 0.65, y: 0.38),  // indexTIP
         9: CGPoint(x: 0.67, y: 0.44),  // middleMCP
        10: CGPoint(x: 0.67, y: 0.41),  // middlePIP
        11: CGPoint(x: 0.67, y: 0.39),  // middleDIP
        12: CGPoint(x: 0.67, y: 0.37),  // middleTIP
        13: CGPoint(x: 0.69, y: 0.44),  // ringMCP
        14: CGPoint(x: 0.69, y: 0.42),  // ringPIP
        15: CGPoint(x: 0.69, y: 0.40),  // ringDIP
        16: CGPoint(x: 0.69, y: 0.38),  // ringTIP
        17: CGPoint(x: 0.71, y: 0.45),  // pinkyMCP
        18: CGPoint(x: 0.71, y: 0.43),  // pinkyPIP
        19: CGPoint(x: 0.71, y: 0.41),  // pinkyDIP
        20: CGPoint(x: 0.71, y: 0.39),  // pinkyTIP
    ]
}
