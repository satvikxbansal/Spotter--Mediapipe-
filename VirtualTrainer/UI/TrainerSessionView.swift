import SwiftUI
import Vision

// ────────────────────────────────────────────────────────────────────
// MARK: - TrainerSessionView
// ────────────────────────────────────────────────────────────────────

/// Full-screen workout camera view with the "No-Fluff Noir" HUD overlay.
///
/// Layers (bottom → top):
///   1. Live camera feed (edge-to-edge)
///   2. Skeleton overlay (joints + bones from PoseEstimator)
///   3. Glowing active-session border
///   4. Rep counter + status chrome
struct TrainerSessionView: View {

    let workout: WorkoutPlan

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var poseEstimator = PoseEstimator()

    @State private var glowPulse = false
    @State private var visibilityResult = BodyVisibilityChecker.Result(
        isReady: false,
        visibility: 0,
        message: "Step into the frame so the camera can see you",
        missingJoints: []
    )

    private let borderWidth: CGFloat = 3
    private let dropShadow = Shadow(
        color: .black.opacity(0.75),
        radius: 6,
        x: 0,
        y: 3
    )

    var body: some View {
        ZStack {
            cameraLayer
            skeletonLayer
            glowBorder
            hudOverlay
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            cameraManager.onFrame = { [weak poseEstimator] pixelBuffer in
                poseEstimator?.processFrame(pixelBuffer)
            }
            cameraManager.start()
            withAnimation(
                .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
            ) {
                glowPulse = true
            }
        }
        .onDisappear {
            cameraManager.stop()
        }
        .onChange(of: poseEstimator.bodyJoints) {
            let exercise = workout.exercises.first?.exerciseType ?? .squat
            visibilityResult = BodyVisibilityChecker.evaluate(
                joints: poseEstimator.bodyJoints,
                for: exercise
            )
        }
    }

    // MARK: - Camera Layer

    private var cameraLayer: some View {
        CameraPreviewView(session: cameraManager.session)
            .ignoresSafeArea()
    }

    // MARK: - Skeleton Overlay

    private var skeletonLayer: some View {
        TrainerOverlayView(bodyJoints: poseEstimator.bodyJoints)
            .ignoresSafeArea()
    }

    // MARK: - Active-Session Glow Border

    /// Warm Amber glow pulses gently while the camera is live.
    private var glowBorder: some View {
        RoundedRectangle(cornerRadius: 0)
            .stroke(
                Theme.Colors.accent,
                lineWidth: borderWidth
            )
            .shadow(color: Theme.Colors.accent.opacity(0.6), radius: glowPulse ? 18 : 8)
            .opacity(cameraManager.isRunning ? 1 : 0)
            .animation(Theme.Motion.smooth, value: cameraManager.isRunning)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: - HUD Overlay

    private var hudOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                workoutTitleLabel
                Spacer()
                repCounterBadge
            }
            .padding(.top, 60)
            .padding(.horizontal, Theme.Spacing.lg)

            if let message = visibilityResult.message, !visibilityResult.isReady {
                BodyVisibilityBannerView(
                    message: message,
                    visibility: visibilityResult.visibility
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, Theme.Spacing.sm)
            }

            Spacer()

            bottomBar
                .padding(.bottom, 40)
                .padding(.horizontal, Theme.Spacing.lg)
        }
        .animation(Theme.Motion.smooth, value: visibilityResult.isReady)
    }

    // MARK: - Workout Title

    private var workoutTitleLabel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(workout.title)
                .font(.system(size: 20, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(Theme.Colors.textPrimary)
                .shadow(
                    color: dropShadow.color,
                    radius: dropShadow.radius,
                    x: dropShadow.x,
                    y: dropShadow.y
                )

            Text("\(workout.exercises.count) sets · \(workout.estimatedMinutes) min")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Theme.Colors.textSecondary)
                .shadow(
                    color: dropShadow.color,
                    radius: dropShadow.radius,
                    x: dropShadow.x,
                    y: dropShadow.y
                )
        }
    }

    // MARK: - Rep Counter

    private var repCounterBadge: some View {
        Text("0")
            .font(.system(size: 96, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.Colors.textPrimary)
            .shadow(
                color: dropShadow.color,
                radius: dropShadow.radius,
                x: dropShadow.x,
                y: dropShadow.y
            )
    }

    // MARK: - Bottom Status Bar

    private var bottomBar: some View {
        HStack {
            statusIndicator
            Spacer()
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(cameraManager.isRunning ? Theme.Colors.positive : Theme.Colors.danger)
                .frame(width: 8, height: 8)
                .shadow(color: cameraManager.isRunning ? Theme.Colors.positive.opacity(0.7) : .clear,
                        radius: 4)

            Text(cameraManager.isRunning ? "LIVE" : "STARTING…")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textPrimary)
                .shadow(
                    color: dropShadow.color,
                    radius: dropShadow.radius,
                    x: dropShadow.x,
                    y: dropShadow.y
                )
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Shadow Token
// ────────────────────────────────────────────────────────────────────

private struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ────────────────────────────────────────────────────────────────────

#Preview {
    TrainerSessionView(workout: WorkoutPlan.MockData.legDay)
}
