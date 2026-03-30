import SwiftUI

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
///   5. Ready-check overlay (positioning → thumbs up → countdown)
struct TrainerSessionView: View {

    let workout: WorkoutPlan
    var coachPersonality: CoachPersonality = .good

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var poseEstimator = PoseEstimator()
    @StateObject private var handGesture = HandGestureDetector()
    @StateObject private var faceLandmarker = FaceLandmarkerService()
    @StateObject private var exertionAnalyzer = ExertionAnalyzer()
    @StateObject private var readyCoordinator = WorkoutReadyCoordinator()
    @StateObject private var motivationEngine = MotivationEngine()
    @ObservedObject private var voiceCoach = VoiceCoachManager.shared

    @State private var glowPulse = false
    @State private var repCount: Int = 0
    @State private var previousRepCount: Int = 0
    @State private var currentPhase: RepPhase = .idle
    @State private var coachCues: [CoachCue] = []
    @State private var debugAngle: Double?
    @State private var motivationScale: CGFloat = 0.3
    @State private var visibilityResult = BodyVisibilityChecker.Result(
        isReady: false,
        visibility: 0,
        message: "Step into the frame so the camera can see you",
        missingJoints: []
    )

    private let repCounter = SquatRepCounter()

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
            readyCheckOverlay
            motivationOverlay
            VStack {
                voiceErrorBanner
                Spacer()
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            motivationEngine.personality = coachPersonality
            readyCoordinator.setPersonality(coachPersonality)

            cameraManager.onFrame = { [weak poseEstimator, weak handGesture, weak faceLandmarker] sampleBuffer in
                poseEstimator?.processFrame(sampleBuffer)
                handGesture?.processFrame(sampleBuffer)
                faceLandmarker?.processFrame(sampleBuffer)
            }
            cameraManager.start()
            withAnimation(
                .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
            ) {
                glowPulse = true
            }

            Task {
                await voiceCoach.prefetchRepCounts(
                    upTo: 20,
                    personality: coachPersonality
                )
            }
        }
        .onDisappear {
            cameraManager.stop()
            handGesture.reset()
            readyCoordinator.reset()
            exertionAnalyzer.reset()
        }
        .onChange(of: poseEstimator.bodyJoints) {
            let joints = poseEstimator.bodyJoints
            let exercise = workout.exercises.first?.exerciseType ?? .squat

            visibilityResult = BodyVisibilityChecker.evaluate(
                joints: joints,
                for: exercise
            )

            // Feed visibility into ready coordinator
            if visibilityResult.isReady {
                readyCoordinator.bodyIsVisible()
            } else {
                readyCoordinator.bodyLost()
            }

            // Only process reps when exercise is active
            guard readyCoordinator.state == .exerciseActive else { return }

            let output = repCounter.processReps(
                joints: joints,
                worldJoints: poseEstimator.worldJoints
            )
            repCount = output.repCount
            currentPhase = output.phase
            coachCues = output.cues
            debugAngle = repCounter.lastKneeAngle

            if repCount > previousRepCount {
                previousRepCount = repCount
                motivationEngine.evaluateEffort(
                    currentRepCount: repCount,
                    faceEffortScore: exertionAnalyzer.effortScore
                )

                Task { await voiceCoach.playRep(count: repCount) }
            }
        }
        .onChange(of: handGesture.currentGesture) {
            switch handGesture.currentGesture {
            case .thumbsUp:
                readyCoordinator.thumbsUpDetected()
            case .thumbsDown:
                readyCoordinator.thumbsDownDetected()
            default:
                break
            }
        }
        .onChange(of: faceLandmarker.blendshapes) {
            guard readyCoordinator.state == .exerciseActive else { return }
            exertionAnalyzer.update(blendshapes: faceLandmarker.blendshapes)
        }
    }

    // MARK: - Camera Layer

    private var cameraLayer: some View {
        CameraPreviewView(session: cameraManager.session)
            .ignoresSafeArea()
    }

    // MARK: - Skeleton Overlay

    private var skeletonLayer: some View {
        TrainerOverlayView(
            bodyJoints: poseEstimator.bodyJoints,
            allHandLandmarks: handGesture.allHandLandmarks
        )
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

    // MARK: - Ready-Check Overlay

    private var readyCheckOverlay: some View {
        Group {
            if readyCoordinator.state != .exerciseActive {
                ZStack {
                    // Semi-transparent backdrop
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: Theme.Spacing.md) {
                        // Gesture indicator
                        if readyCoordinator.state == .askingReady {
                            gestureIndicator
                        }

                        // Main state message
                        Text(readyCoordinator.state.displayMessage)
                            .font(.system(size: readyCoordinator.state.isCountdown ? 72 : 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .shadow(color: .black.opacity(0.5), radius: 8)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.3), value: readyCoordinator.state)

                        // Subtitle
                        if let subtitle = readyCoordinator.state.subtitle {
                            Text(subtitle)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.xl)
                        }

                        // Coach message
                        if !readyCoordinator.coachMessage.isEmpty {
                            Text(readyCoordinator.coachMessage)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(coachPersonality.accentColor.opacity(0.85))
                                )
                                .padding(.horizontal, Theme.Spacing.lg)
                                .transition(.scale.combined(with: .opacity))
                        }

                        // Visibility progress
                        if readyCoordinator.state == .positioning {
                            visibilityProgress
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Theme.Motion.smooth, value: readyCoordinator.state)
    }

    private var gestureIndicator: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.Colors.positive)
                Text("Start")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "hand.thumbsdown.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.Colors.danger)
                Text("Not yet")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var visibilityProgress: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ProgressView(value: visibilityResult.visibility)
                .progressViewStyle(.linear)
                .tint(Theme.Colors.accent)
                .frame(width: 200)

            if let message = visibilityResult.message {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
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

            if readyCoordinator.state == .exerciseActive,
               let message = visibilityResult.message,
               !visibilityResult.isReady {
                BodyVisibilityBannerView(
                    message: message,
                    visibility: visibilityResult.visibility
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, Theme.Spacing.sm)
            }

            Spacer()

            VStack(spacing: Theme.Spacing.sm) {
                if let cue = coachCues.first {
                    coachCueBanner(cue)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if readyCoordinator.state == .exerciseActive {
                    HStack(spacing: Theme.Spacing.sm) {
                        if let angle = debugAngle {
                            debugAngleBadge(angle)
                        }
                        if faceLandmarker.faceDetected {
                            effortBadge
                        }
                    }
                }

                bottomBar
            }
            .padding(.bottom, 40)
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .animation(Theme.Motion.smooth, value: visibilityResult.isReady)
        .animation(Theme.Motion.smooth, value: coachCues.first?.id)
    }

    // MARK: - Workout Title

    private var workoutTitleLabel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(workout.title.uppercased())
                .font(.system(size: 14, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.accent)
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
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(repCount)")
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
                .shadow(
                    color: dropShadow.color,
                    radius: dropShadow.radius,
                    x: dropShadow.x,
                    y: dropShadow.y
                )
                .contentTransition(.numericText(value: Double(repCount)))
                .animation(.snappy(duration: 0.3), value: repCount)

            phaseLabel
        }
    }

    private var phaseLabel: some View {
        Text(currentPhase.rawValue.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.5)
            .foregroundStyle(phaseColor)
            .shadow(
                color: dropShadow.color,
                radius: dropShadow.radius,
                x: dropShadow.x,
                y: dropShadow.y
            )
    }

    private var phaseColor: Color {
        switch currentPhase {
        case .idle: Theme.Colors.textSecondary
        case .down: Theme.Colors.accent
        case .up:   Theme.Colors.positive
        }
    }

    // MARK: - Voice Error Debug Banner

    private var voiceErrorBanner: some View {
        Group {
            if let error = voiceCoach.voiceError {
                Text(error)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.danger.opacity(0.85))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.smooth, value: voiceCoach.voiceError)
    }

    // MARK: - Motivation Overlay

    private var motivationTint: Color {
        coachPersonality == .drill ? Theme.Colors.danger : Theme.Colors.accent
    }

    private var motivationOverlay: some View {
        Group {
            if let message = motivationEngine.activeMessage,
               readyCoordinator.state == .exerciseActive {
                Text(message)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(motivationTint)
                    .shadow(color: motivationTint.opacity(0.9), radius: 20)
                    .shadow(color: motivationTint.opacity(0.5), radius: 40)
                    .shadow(color: motivationTint.opacity(0.25), radius: 60)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .scaleEffect(motivationScale)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(Theme.Motion.bounce, value: motivationEngine.activeMessage == nil)
        .onChange(of: motivationEngine.activeMessage) { _, newValue in
            if newValue != nil {
                motivationScale = 0.3
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                    motivationScale = 1.0
                }
            }
        }
    }

    // MARK: - Coach Cue Banner

    private func coachCueBanner(_ cue: CoachCue) -> some View {
        Text(cue.message)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(cue.severity >= .warning
                          ? Theme.Colors.accent.opacity(0.85)
                          : Color.white.opacity(0.15))
            )
    }

    // MARK: - Debug Angle

    private func debugAngleBadge(_ angle: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "angle")
                .font(.system(size: 10, weight: .bold))
            Text("Knee: \(Int(angle))°")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
        )
    }

    // MARK: - Effort Badge

    private var effortBadge: some View {
        let effort = exertionAnalyzer.effortScore
        let color: Color = effort > 0.7
            ? Theme.Colors.danger
            : effort > 0.4 ? Theme.Colors.accent : Theme.Colors.positive

        return HStack(spacing: 6) {
            Image(systemName: "face.smiling")
                .font(.system(size: 10, weight: .bold))
            Text("Effort: \(Int(effort * 100))%")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
        )
    }

    // MARK: - Gesture Debug Label

    private var gestureDebugLabel: some View {
        Group {
            let gesture = handGesture.currentGesture
            let text: String = switch gesture {
            case .thumbsUp:    "👍 Thumbs Up"
            case .thumbsDown:  "👎 Thumbs Down"
            case .openPalm:    "🖐️ Open Palm"
            case .fist:        "✊ Fist"
            case .victory:     "✌️ Victory"
            case .pointingUp:  "☝️ Pointing Up"
            case .none:        handGesture.handDetected ? "🤚 Hand Detected" : "No Hand"
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(gesture != .none ? Theme.Colors.positive : Theme.Colors.textSecondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(text)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(gesture != .none ? Theme.Colors.positive : Theme.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
            )
        }
    }

    // MARK: - Bottom Status Bar

    private var bottomBar: some View {
        HStack {
            statusIndicator
            Spacer()
            gestureDebugLabel
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
// MARK: - WorkoutReadyState Helpers
// ────────────────────────────────────────────────────────────────────

extension WorkoutReadyState {
    var isCountdown: Bool {
        if case .countdown = self { return true }
        return false
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ────────────────────────────────────────────────────────────────────

#Preview {
    TrainerSessionView(workout: WorkoutPlan.MockData.legDay)
}
