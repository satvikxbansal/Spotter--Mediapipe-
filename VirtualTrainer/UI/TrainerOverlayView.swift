import SwiftUI
import Vision

// ────────────────────────────────────────────────────────────────────
// MARK: - TrainerOverlayView
// ────────────────────────────────────────────────────────────────────

/// Draws the detected body skeleton over the live camera feed.
///
/// Joint positions arrive as normalised 0…1 values (already in
/// SwiftUI's top-left coordinate space thanks to `PoseEstimator`).
/// A `GeometryReader` maps them to screen pixels, then a `Canvas`
/// renders bones and joint dots in a single draw pass — far cheaper
/// than stacking individual SwiftUI `Circle` views for 19 joints
/// at 30 fps.
struct TrainerOverlayView: View {

    let bodyJoints: [VNHumanBodyPoseObservation.JointName: CGPoint]

    // MARK: - Visual Tuning

    private let boneColor = Theme.Colors.accent
    private let boneLineWidth: CGFloat = 4
    private let boneOpacity: Double = 0.75

    private let jointRadius: CGFloat = 6
    private let jointColor = Color.white

    // MARK: - Bone Definitions

    /// Pairs of joints that should be connected with a line.
    /// Ordered head → extremities for natural layering.
    private static let bonePairs: [(VNHumanBodyPoseObservation.JointName,
                                    VNHumanBodyPoseObservation.JointName)] = [
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

        // Right leg
        (.rightHip,      .rightKnee),
        (.rightKnee,     .rightAnkle),

        // Neck / head
        (.neck,          .leftShoulder),
        (.neck,          .rightShoulder),
        (.neck,          .nose),
    ]

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                drawBones(context: &context, size: size)
                drawJoints(context: &context, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drawing

    private func drawBones(context: inout GraphicsContext, size: CGSize) {
        var bonePath = Path()

        for (from, to) in Self.bonePairs {
            guard
                let a = bodyJoints[from],
                let b = bodyJoints[to]
            else { continue }

            let screenA = CGPoint(x: a.x * size.width, y: a.y * size.height)
            let screenB = CGPoint(x: b.x * size.width, y: b.y * size.height)

            bonePath.move(to: screenA)
            bonePath.addLine(to: screenB)
        }

        context.opacity = boneOpacity
        context.stroke(
            bonePath,
            with: .color(boneColor),
            style: StrokeStyle(lineWidth: boneLineWidth, lineCap: .round)
        )
        context.opacity = 1
    }

    private func drawJoints(context: inout GraphicsContext, size: CGSize) {
        for (_, point) in bodyJoints {
            let screen = CGPoint(x: point.x * size.width, y: point.y * size.height)

            let rect = CGRect(
                x: screen.x - jointRadius,
                y: screen.y - jointRadius,
                width: jointRadius * 2,
                height: jointRadius * 2
            )

            context.fill(
                Path(ellipseIn: rect),
                with: .color(jointColor)
            )

            // Subtle glow ring around each dot for visibility on dark backgrounds.
            let glowRect = rect.insetBy(dx: -2, dy: -2)
            context.opacity = 0.35
            context.stroke(
                Path(ellipseIn: glowRect),
                with: .color(boneColor),
                style: StrokeStyle(lineWidth: 2)
            )
            context.opacity = 1
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ────────────────────────────────────────────────────────────────────

#Preview("Skeleton Overlay — Mock Pose") {
    ZStack {
        Color.black.ignoresSafeArea()

        TrainerOverlayView(bodyJoints: TrainerOverlayView.mockJoints)
    }
}

extension TrainerOverlayView {
    /// A plausible standing pose for Xcode previews.
    static let mockJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [
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
    ]
}
