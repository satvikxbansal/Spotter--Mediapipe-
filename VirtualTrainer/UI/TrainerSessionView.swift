import SwiftUI
import Combine
import simd

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

    @Environment(\.dismiss) private var dismiss

    private let context: LiveSessionContext
    private let onFreeAnalysisEnded: ((FreeAnalysisSummary) -> Void)?

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
    @State private var holdDuration: TimeInterval = 0
    @State private var isHolding: Bool = false
    @State private var lastFormScore: FormScore?
    @State private var sessionStartedAt: Date?
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var peakEffort: Double = 0
    @State private var visibilityResult = BodyVisibilityChecker.Result(
        isReady: false,
        visibility: 0,
        message: "Step into the frame so the camera can see you",
        missingJoints: []
    )

    private let formEngine = FormFeedbackEngine()

    init(workout: WorkoutPlan, coachPersonality: CoachPersonality = .good) {
        self.context = LiveSessionContext.plannedWorkout(
            workout: workout,
            coach: coachPersonality
        )
        self.onFreeAnalysisEnded = nil
    }

    init(
        context: LiveSessionContext,
        onFreeAnalysisEnded: ((FreeAnalysisSummary) -> Void)? = nil
    ) {
        self.context = context
        self.onFreeAnalysisEnded = onFreeAnalysisEnded
    }

    private var coachPersonality: CoachPersonality {
        context.coach
    }

    private var exerciseType: ExerciseType {
        context.exerciseType
    }

    private var exerciseDefinition: ExerciseDefinition {
        exerciseType.definition ?? ExerciseLibrary.squats
    }

    @State private var repCounter: UniversalRepCounter?
    @State private var angleOverlays: [TrainerOverlayView.AngleOverlayData] = []
    @State private var violatedJoints: Set<JointName> = []

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
            sessionStartedAt = Date()
            repCounter = UniversalRepCounter(exerciseType: exerciseType)
            motivationEngine.personality = coachPersonality
            readyCoordinator.setPersonality(coachPersonality)
            if context.startsActive {
                readyCoordinator.activateImmediately()
            }

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

            voiceCoach.prefetchRepCounts(
                upTo: 20,
                personality: coachPersonality
            )
        }
        .onDisappear {
            cameraManager.stop()
            handGesture.reset()
            readyCoordinator.reset()
            exertionAnalyzer.reset()
            repCounter?.reset()
            formEngine.reset()
        }
        .onChange(of: poseEstimator.bodyJoints) {
            let joints = poseEstimator.bodyJoints

            visibilityResult = BodyVisibilityChecker.evaluateFrame(
                mask: poseEstimator.segmentationMask,
                joints: joints,
                for: exerciseType,
                personality: coachPersonality
            )

            // Feed visibility into ready coordinator
            if visibilityResult.isReady {
                readyCoordinator.bodyIsVisible()
            } else {
                readyCoordinator.bodyLost()
            }

            guard readyCoordinator.state == .exerciseActive,
                  let counter = repCounter else {
                angleOverlays = []
                violatedJoints = []
                return
            }

            let output = counter.processJoints(
                joints,
                worldJoints: poseEstimator.worldJoints,
                jointVisibility: poseEstimator.jointVisibility,
                personality: coachPersonality
            )
            repCount = output.repCount
            currentPhase = output.phase
            debugAngle = counter.lastPrimaryAngle
            holdDuration = output.holdDuration
            isHolding = output.isHolding

            let formFeedbacks = formEngine.evaluate(
                joints: joints,
                angles: counter.lastAngles,
                phase: currentPhase,
                definition: exerciseDefinition,
                personality: coachPersonality,
                bilateralAngles: counter.lastBilateralAngles,
                worldJoints: poseEstimator.worldJoints,
                jointVisibility: poseEstimator.jointVisibility,
                activeSide: counter.lastActiveSide,
                frameMask: poseEstimator.segmentationMask
            )

            if !formFeedbacks.isEmpty {
                coachCues = formFeedbacks.map { $0.asCoachCue }
                counter.recordFeedbackDuringRep()
                if let cue = coachCues.first, cue.severity >= .warning {
                    voiceCoach.playCue(cue, personality: coachPersonality)
                }
            } else {
                coachCues = output.cues
            }

            if let score = output.formScore {
                lastFormScore = score
            }

            angleOverlays = buildAngleOverlays(
                angles: counter.lastAngles,
                definition: exerciseDefinition,
                joints: joints,
                worldJoints: poseEstimator.worldJoints,
                jointVisibility: poseEstimator.jointVisibility,
                activeSide: counter.lastActiveSide
            )

            violatedJoints = buildViolatedJoints(
                feedbacks: formFeedbacks,
                definition: exerciseDefinition
            )

            if repCount > previousRepCount {
                previousRepCount = repCount
                HapticsEngine.shared.repTick()
                motivationEngine.evaluateEffort(
                    currentRepCount: repCount,
                    faceEffortScore: exertionAnalyzer.effortScore
                )

                voiceCoach.playRep(count: repCount)
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
            peakEffort = max(peakEffort, exertionAnalyzer.effortScore)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            guard readyCoordinator.state == .exerciseActive,
                  let sessionStartedAt else { return }
            elapsedSeconds = now.timeIntervalSince(sessionStartedAt)
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
            bodyJoints: poseEstimator.overlayBodyJoints,
            allHandLandmarks: handGesture.allHandLandmarks,
            angleOverlays: angleOverlays,
            violatedJoints: violatedJoints,
            imageAspectRatio: poseEstimator.imageAspectRatio
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
                        if readyCoordinator.state == .positioning,
                           exerciseDefinition.cameraPosition == .side {
                            cameraPositionGuide
                        }

                        if readyCoordinator.state == .positioning {
                            Text(exerciseDefinition.setupInstruction)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Colors.accent)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.xl)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                        .fill(Color.black.opacity(0.5))
                                )
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        if readyCoordinator.state == .askingReady {
                            gestureIndicator
                        }

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

    // MARK: - Camera Position Guide

    private var cameraPositionGuide: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "rotate.3d.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text("SIDE VIEW REQUIRED")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.Colors.accent)

                Text("Turn sideways to the camera")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.Colors.accent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var activeSideViewBanner: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "rotate.3d.fill")
                .font(.system(size: 10, weight: .bold))
            Text("Side view")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.5)
        }
        .foregroundStyle(Theme.Colors.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Theme.Colors.accent.opacity(0.15))
        )
    }

    // MARK: - HUD Overlay

    private var hudOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                workoutTitleLabel
                Spacer()
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    if context.isFreeAnalysis {
                        endFreeAnalysisButton
                    }
                    repCounterBadge
                }
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
                        if context.isFreeAnalysis {
                            elapsedTimeBadge
                        }
                        if let angle = debugAngle {
                            debugAngleBadge(angle)
                        }
                        if !isIsometric, let score = lastFormScore {
                            formScoreBadge(score)
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
            Text(sessionEyebrow.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.accent)
                .shadow(
                    color: dropShadow.color,
                    radius: dropShadow.radius,
                    x: dropShadow.x,
                    y: dropShadow.y
                )

            Text(exerciseType.displayName.uppercased())
                .font(.system(size: 24, weight: .heavy))
                .tracking(0.2)
                .foregroundStyle(Theme.Colors.textPrimary)
                .shadow(
                    color: dropShadow.color,
                    radius: dropShadow.radius,
                    x: dropShadow.x,
                    y: dropShadow.y
                )

            if let sessionDetailText {
                Text(sessionDetailText)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .shadow(
                        color: dropShadow.color,
                        radius: dropShadow.radius,
                        x: dropShadow.x,
                        y: dropShadow.y
                    )
            }

            if exerciseDefinition.cameraPosition == .side {
                activeSideViewBanner
            }
        }
    }

    private var sessionEyebrow: String {
        context.isFreeAnalysis ? "Free analysis" : context.title
    }

    private var sessionDetailText: String? {
        if context.isFreeAnalysis {
            return "Open practice"
        }

        var details: [String] = []
        if let setIndex = context.setIndex,
           let totalSets = context.totalSets {
            details.append("Set \(setIndex + 1) of \(totalSets)")
        }
        if let targetText {
            details.append(targetText)
        }
        return details.isEmpty ? nil : details.joined(separator: " • ")
    }

    private var targetText: String? {
        guard let target = context.target else { return nil }
        switch target {
        case .open:
            return "Open target"
        case .reps(let reps):
            return "\(reps) \(reps == 1 ? "rep" : "reps")"
        case .seconds(let seconds):
            return "\(max(seconds, 0)) sec"
        }
    }

    private var endFreeAnalysisButton: some View {
        Button {
            endFreeAnalysis()
        } label: {
            Text("Done")
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.Colors.background)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.Colors.accent)
                .clipShape(Capsule())
        }
    }

    // MARK: - Rep Counter / Hold Timer

    private var isIsometric: Bool {
        exerciseDefinition.movementType == .isometric
    }

    @ViewBuilder
    private var repCounterBadge: some View {
        if isIsometric {
            isometricHoldBadge
        } else {
            repetitionCounterBadge
        }
    }

    private var repetitionCounterBadge: some View {
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

    // MARK: Isometric Hold Timer + Progress Ring

    private var holdTimerText: String {
        let totalSeconds = Int(holdDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return "\(seconds)"
    }

    private var holdTargetSeconds: Double {
        guard case .seconds(let seconds) = context.target else { return 0 }
        return Double(seconds)
    }

    private var holdProgress: Double {
        guard holdTargetSeconds > 0 else { return 0 }
        return min(holdDuration / holdTargetSeconds, 1.0)
    }

    private var isometricHoldBadge: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack {
                // Background track
                Circle()
                    .stroke(
                        Theme.Colors.textSecondary.opacity(0.2),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )

                // Progress arc
                if holdTargetSeconds > 0 {
                    Circle()
                        .trim(from: 0, to: holdProgress)
                        .stroke(
                            isHolding ? Theme.Colors.accent : Theme.Colors.textSecondary.opacity(0.5),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: holdProgress)
                }

                // Timer digits
                Text(holdTimerText)
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText(value: holdDuration))
                    .animation(.snappy(duration: 0.3), value: Int(holdDuration))
            }
            .frame(width: 100, height: 100)
            .shadow(
                color: isHolding ? Theme.Colors.accent.opacity(0.4) : .clear,
                radius: 12
            )

            // Phase label
            Text(isHolding ? "HOLDING" : (holdDuration > 0 ? "PAUSED" : "GET SET"))
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(isHolding ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .shadow(
                    color: dropShadow.color,
                    radius: dropShadow.radius,
                    x: dropShadow.x,
                    y: dropShadow.y
                )
                .animation(.easeInOut(duration: 0.2), value: isHolding)
        }
    }

    private var elapsedTimeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .bold))
            Text(elapsedTimeText)
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

    private var elapsedTimeText: String {
        let seconds = max(Int(elapsedSeconds), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
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

    // MARK: - Overlay Data Builders

    private func buildAngleOverlays(
        angles: [String: Double],
        definition: ExerciseDefinition,
        joints: [JointName: CGPoint],
        worldJoints: [JointName: SIMD3<Float>],
        jointVisibility: [JointName: Float],
        activeSide: String?
    ) -> [TrainerOverlayView.AngleOverlayData] {
        var result: [TrainerOverlayView.AngleOverlayData] = []
        for angleDef in definition.angles {
            guard let degrees = angles[angleDef.key] else { continue }

            let lockedSide = lockedOverlaySide(
                for: angleDef,
                definition: definition,
                activeSide: activeSide
            )

            if let side = lockedSide ?? AngleCalculator.preferredOverlaySide(
                for: angleDef,
                joints2D: joints,
                joints3D: worldJoints,
                jointVisibility: jointVisibility
            ), let triple = AngleCalculator.resolveJointTriple(for: angleDef, side: side) {
                result.append(.init(
                    label: angleDef.label,
                    degrees: degrees,
                    vertexJoint: triple.mid,
                    startJoint: triple.start,
                    endJoint: triple.end
                ))
            }
        }
        return result
    }

    private func lockedOverlaySide(
        for angleDef: AngleDefinition,
        definition: ExerciseDefinition,
        activeSide: String?
    ) -> String? {
        guard angleDef.key == definition.primaryAngleKey,
              (angleDef.side == .moreFlexed || angleDef.side == .lessFlexed),
              let activeSide,
              AngleCalculator.resolveJointTriple(for: angleDef, side: activeSide) != nil
        else { return nil }

        return activeSide
    }

    private func buildViolatedJoints(
        feedbacks: [FormFeedbackEngine.Feedback],
        definition: ExerciseDefinition
    ) -> Set<JointName> {
        guard !feedbacks.isEmpty else { return [] }

        var joints = Set<JointName>()
        let violatedRuleIds = feedbacks
            .filter { $0.type == .exerciseRule }
            .compactMap { $0.ruleId }

        for ruleId in violatedRuleIds {
            let angleDef: AngleDefinition?
            if let rule = definition.formRules.first(where: { $0.id == ruleId }) {
                angleDef = definition.angles.first(where: { $0.key == rule.angleKey })
            } else if let check = definition.positionalChecks.first(where: { $0.id == ruleId }) {
                angleDef = angleDefinition(for: check, definition: definition)
            } else {
                angleDef = nil
            }
            guard let angleDef else { continue }

            for side in ["right", "left"] {
                if let triple = AngleCalculator.resolveJointTriple(for: angleDef, side: side) {
                    joints.insert(triple.start)
                    joints.insert(triple.mid)
                    joints.insert(triple.end)
                }
            }
        }
        return joints
    }

    private func angleDefinition(
        for check: PositionalCheck,
        definition: ExerciseDefinition
    ) -> AngleDefinition? {
        switch check.checkType {
        case .kneeValgus, .heelRise:
            return definition.angles.first { $0.key.lowercased().contains("knee") }
        case .kneeOverFootLine, .kneeOverAnkle:
            return definition.angles.first { $0.key.lowercased().contains("knee") }
                ?? definition.angles.first
        case .stanceWidth, .hipBetweenKnees, .pelvisLevel:
            return definition.angles.first { $0.key.lowercased().contains("hip") || $0.key.lowercased().contains("knee") }
                ?? definition.angles.first
        case .hipHeightRelativeToLine, .trunkLean:
            return definition.angles.first { $0.key.lowercased().contains("hip") || $0.key == "bodyLineAngle" }
                ?? definition.angles.first
        case .shoulderOverSupport, .wristOverElbow:
            return definition.angles.first { $0.key.lowercased().contains("shoulder") || $0.key.lowercased().contains("elbow") }
                ?? definition.angles.first
        case .footPlanted:
            return definition.angles.first { $0.key.lowercased().contains("ankle") || $0.key.lowercased().contains("knee") }
                ?? definition.angles.first
        case .controlledLower, .pauseAtTop:
            return definition.angles.first
        case .shoulderLevel:
            return definition.angles.first { $0.startJoint.contains("shoulder") || $0.midJoint.contains("shoulder") }
                ?? definition.angles.first
        case .jointAboveJoint, .jointAlignedX:
            return definition.angles.first
        case .hipRotationStability:
            return definition.angles.first { $0.key == "trunkTwistMagnitude" }
                ?? definition.angles.first { $0.key == "signedTrunkTwistAngle" }
                ?? definition.angles.first
        }
    }

    private func endFreeAnalysis() {
        let summary = FreeAnalysisSummary(
            exerciseType: exerciseType,
            duration: elapsedSeconds,
            reps: repCount,
            latestFormScore: lastFormScore,
            peakEffort: peakEffort,
            lastCue: coachCues.first
        )
        onFreeAnalysisEnded?(summary)
        dismiss()
    }

    // MARK: - Debug Angle

    private var primaryAngleLabel: String {
        exerciseDefinition.angles
            .first { $0.key == exerciseDefinition.primaryAngleKey }?
            .label ?? "Angle"
    }

    private func debugAngleBadge(_ angle: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "angle")
                .font(.system(size: 10, weight: .bold))
            Text("\(primaryAngleLabel): \(Int(angle))°")
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

    // MARK: - Form Score Badge

    private func formScoreBadge(_ score: FormScore) -> some View {
        let color: Color = switch score.grade {
        case .A: Theme.Colors.positive
        case .B: Theme.Colors.accent
        case .C: Theme.Colors.accent
        case .D: Theme.Colors.danger.opacity(0.8)
        case .F: Theme.Colors.danger
        }

        return HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .bold))
            Text("\(score.grade.rawValue) \(score.score)")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
        )
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: score.score)
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
