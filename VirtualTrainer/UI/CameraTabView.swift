import SwiftUI

nonisolated struct FreeAnalysisCameraLaunchConfiguration: Equatable {
    let exerciseType: ExerciseType
    let coach: CoachPersonality

    static func make(
        exerciseType: ExerciseType,
        profile: UserProfile?
    ) -> FreeAnalysisCameraLaunchConfiguration {
        FreeAnalysisCameraLaunchConfiguration(
            exerciseType: exerciseType,
            coach: profile?.preferredCoach.coachPersonality ?? .good
        )
    }
}

struct CameraTabView: View {
    @State private var summary: FreeAnalysisSummary?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Camera")
                        .header(size: 36)

                    Text("Run an open-ended form check without plans, sets, or target reps.")
                        .bodyText()
                        .foregroundStyle(Theme.Colors.textSecondary)

                    NavigationLink {
                        FormCheckSelectionView { summary = $0 }
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Theme.Colors.accent)
                            Text("Form Check / Free Analysis")
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("Select an exercise, pass readiness, then train until you tap Done.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.lg)
                        .background(Theme.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: Theme.Spacing.xxl)
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $summary) { summary in
                FreeAnalysisSummaryView(summary: summary)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

struct FormCheckSelectionView: View {
    let onSummary: (FreeAnalysisSummary) -> Void
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                TextField("Search exercises", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .listRowBackground(Theme.Colors.surface)

            ForEach(BodyCategory.allCases) { category in
                let exercises = filteredExercises(in: category)
                if !exercises.isEmpty {
                    Section(category.freeAnalysisTitle) {
                        ForEach(exercises) { option in
                            if let exerciseType = option.type {
                                let launchConfiguration = FreeAnalysisCameraLaunchConfiguration.make(
                                    exerciseType: exerciseType,
                                    profile: onboardingStore.profile
                                )
                                NavigationLink {
                                    CameraReadinessView(
                                        exerciseType: launchConfiguration.exerciseType,
                                        coach: launchConfiguration.coach,
                                        onSummary: onSummary
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                                        Text(option.name)
                                            .font(.system(size: 16, weight: .bold))
                                        Text(exerciseType.visibilityHint)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Theme.Colors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.Colors.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Select Exercise")
    }

    private func filteredExercises(in category: BodyCategory) -> [ExerciseOption] {
        let options = category.exercises.filter(\.available)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

struct CameraReadinessView: View {
    let exerciseType: ExerciseType
    let coach: CoachPersonality
    private let readinessTitle: String
    private let activeNavigationTitle: String
    private let startButtonTitle: String
    private let targetRepsForFailure: Int
    private let makeContext: () -> LiveSessionContext
    private let onSummary: ((FreeAnalysisSummary) -> Void)?
    private let onCalibrationCompleted: ((CalibrationRecord) -> Void)?
    private let onCalibrationFailed: ((CalibrationRecord) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLevelPresenter) private var appLevelPresenter
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var designSystemV2Toggle: DesignSystemV2ToggleStore
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var poseEstimator = PoseEstimator()
    @StateObject private var handGesture = HandGestureDetector()
    @StateObject private var readyCoordinator = WorkoutReadyCoordinator()

    @State private var visibilityResult = BodyVisibilityChecker.Result(
        isReady: false,
        visibility: 0,
        message: "Step into the frame so the camera can see you",
        missingJoints: []
    )
    @State private var activeContext: LiveSessionContext?

    private var exerciseDefinition: ExerciseDefinition {
        exerciseType.definition ?? ExerciseLibrary.squats
    }

    init(
        exerciseType: ExerciseType,
        coach: CoachPersonality,
        onSummary: @escaping (FreeAnalysisSummary) -> Void
    ) {
        self.exerciseType = exerciseType
        self.coach = coach
        self.readinessTitle = "Get camera ready"
        self.activeNavigationTitle = "Readiness"
        self.startButtonTitle = "Start free analysis"
        self.targetRepsForFailure = CalibrationDefaults.targetReps
        self.makeContext = {
            LiveSessionContext.freeAnalysis(
                exerciseType: exerciseType,
                coach: coach,
                startsActive: true
            )
        }
        self.onSummary = onSummary
        self.onCalibrationCompleted = nil
        self.onCalibrationFailed = nil
    }

    init(
        calibrationExerciseType exerciseType: ExerciseType = CalibrationDefaults.exerciseType,
        targetReps: Int = CalibrationDefaults.targetReps,
        coach: CoachPersonality,
        onCompleted: @escaping (CalibrationRecord) -> Void,
        onFailed: @escaping (CalibrationRecord) -> Void
    ) {
        self.exerciseType = exerciseType
        self.coach = coach
        self.readinessTitle = "Set up calibration"
        self.activeNavigationTitle = "Calibration"
        self.startButtonTitle = "Start calibration"
        self.targetRepsForFailure = targetReps
        self.makeContext = {
            LiveSessionContext.calibration(
                exerciseType: exerciseType,
                targetReps: targetReps,
                coach: coach,
                startsActive: true
            )
        }
        self.onSummary = nil
        self.onCalibrationCompleted = onCompleted
        self.onCalibrationFailed = onFailed
    }

    var body: some View {
        ZStack {
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            TrainerOverlayView(
                bodyJoints: poseEstimator.overlayBodyJoints,
                allHandLandmarks: handGesture.allHandLandmarks,
                imageAspectRatio: poseEstimator.imageAspectRatio
            )
            .ignoresSafeArea()

            if designSystemV2Toggle.isEffectivelyEnabled {
                V2CameraReadinessView(
                    theme: themeStore.selectedTheme,
                    state: v2ReadinessState,
                    orientationInstruction: v2OrientationInstruction,
                    visibilityPercent: Int((visibilityResult.visibility * 100).rounded()),
                    onStartTracking: startSession,
                    onOpenSettings: { V2CameraReadinessView.openAppSettings() },
                    onClose: closeReadiness
                )
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    readinessHeader
                    Spacer()
                    readinessCard
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle(activeNavigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            readyCoordinator.setPersonality(coach)
            poseEstimator.reset()
            handGesture.reset()
            cameraManager.onFrame = { [weak poseEstimator, weak handGesture] sampleBuffer in
                poseEstimator?.processFrame(sampleBuffer)
                handGesture?.processFrame(sampleBuffer)
            }
            cameraManager.start()
        }
        .onDisappear {
            stopReadinessCamera()
            poseEstimator.reset()
            handGesture.reset()
            readyCoordinator.reset()
        }
        .onChange(of: poseEstimator.bodyJoints) {
            visibilityResult = BodyVisibilityChecker.evaluateFrame(
                mask: poseEstimator.segmentationMask,
                joints: poseEstimator.bodyJoints,
                for: exerciseType,
                personality: coach
            )

            if visibilityResult.isReady {
                readyCoordinator.bodyIsVisible(currentGesture: handGesture.currentGesture)
            } else {
                readyCoordinator.bodyLost()
            }
        }
        .onChange(of: handGesture.currentGesture) {
            readyCoordinator.handleGesture(handGesture.currentGesture)
        }
        .onChange(of: readyCoordinator.state) { _, state in
            if state == .askingReady {
                readyCoordinator.handleGesture(handGesture.currentGesture)
            }
            if state == .exerciseActive {
                startSession()
            }
        }
        .fullScreenCover(item: $activeContext, onDismiss: {
            appLevelPresenter.setLiveWorkoutPresented(false)
        }) { context in
            if context.isCalibration {
                TrainerSessionView(
                    calibrationContext: context,
                    onCalibrationCompleted: { record in
                        appLevelPresenter.setLiveWorkoutPresented(false)
                        activeContext = nil
                        onCalibrationCompleted?(record)
                        dismiss()
                    },
                    onCalibrationFailed: { record in
                        appLevelPresenter.setLiveWorkoutPresented(false)
                        activeContext = nil
                        onCalibrationFailed?(record)
                        dismiss()
                    }
                )
            } else {
                TrainerSessionView(context: context) { summary in
                    appLevelPresenter.setLiveWorkoutPresented(false)
                    activeContext = nil
                    onSummary?(summary)
                    dismiss()
                }
            }
        }
    }

    private var readinessHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(exerciseType.displayName.uppercased())
                .font(.system(size: 13, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Theme.Colors.accent)
            Text(readinessTitle)
                .header(size: 32)
            Text(exerciseDefinition.setupInstruction)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if cameraManager.permissionStatus == .denied {
                permissionDeniedContent
            } else {
                readinessProgressContent
            }
        }
        .padding(Theme.Spacing.md)
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    private var readinessProgressContent: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                    Text(cameraOrientationText)
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.Colors.accent)
                    Text(readyCoordinator.state.displayMessage)
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Spacer()
                Text("\(Int(visibilityResult.visibility * 100))%")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            ProgressView(value: visibilityResult.visibility)
                .tint(Theme.Colors.accent)

            if let message = visibilityResult.message {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if readyCoordinator.state == .askingReady {
                Text("Thumbs up to start, thumbs down if you need more time.")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            Button(readinessButtonTitle) {
                startSession()
            }
            .buttonStyle(PrimaryCTAStyle())
            .disabled(!canStartSession)
            .opacity(canStartSession ? 1 : 0.55)
        }
    }

    private var permissionDeniedContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Camera access is off")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Spotter needs camera access to verify body visibility. No frames are stored or uploaded.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
            Button(permissionDeniedButtonTitle) {
                handlePermissionDeniedExit()
            }
            .buttonStyle(PrimaryCTAStyle())
        }
    }

    private var cameraOrientationText: String {
        switch exerciseDefinition.cameraPosition {
        case .front:
            "FRONT VIEW"
        case .side:
            "SIDE VIEW REQUIRED"
        }
    }

    private var v2OrientationInstruction: String {
        switch exerciseDefinition.cameraPosition {
        case .front:
            "Face camera for \(exerciseType.displayName.lowercased())"
        case .side:
            "Turn phone sideways for \(exerciseType.displayName.lowercased())"
        }
    }

    private var v2ReadinessState: V2CameraReadinessUIState {
        V2CameraReadinessAdapter.makeState(
            permissionStatus: cameraManager.permissionStatus,
            visibilityResult: visibilityResult,
            coordinatorState: readyCoordinator.state,
            setupInstruction: exerciseDefinition.setupInstruction
        )
    }

    private var canStartSession: Bool {
        activeContext == nil &&
            cameraManager.permissionStatus != .denied &&
            (readyCoordinator.state == .askingReady || readyCoordinator.state == .exerciseActive)
    }

    private var readinessButtonTitle: String {
        canStartSession ? startButtonTitle : "Get fully in frame"
    }

    private var permissionDeniedButtonTitle: String {
        onCalibrationFailed == nil ? "Back to exercises" : "Return to calibration"
    }

    private func startSession() {
        guard canStartSession else {
            HapticsEngine.shared.warningPulse()
            return
        }
        stopReadinessCamera()
        appLevelPresenter.setLiveWorkoutPresented(true)
        activeContext = makeContext()
    }

    private func handlePermissionDeniedExit() {
        if let onCalibrationFailed {
            let now = Date()
            onCalibrationFailed(
                .failed(
                    exerciseType: exerciseType,
                    targetReps: targetRepsForFailure,
                    startedAt: now,
                    completedAt: now,
                    notes: "Camera permission was unavailable during calibration."
                )
            )
        }
        dismiss()
    }

    private func closeReadiness() {
        if cameraManager.permissionStatus == .denied {
            handlePermissionDeniedExit()
        } else {
            dismiss()
        }
    }

    private func stopReadinessCamera() {
        cameraManager.onFrame = nil
        cameraManager.stop()
    }
}

struct FreeAnalysisSummaryView: View {
    let summary: FreeAnalysisSummary

    @EnvironmentObject private var appDependencies: AppDependencies
    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @EnvironmentObject private var trophyStore: TrophyStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var designSystemV2Toggle: DesignSystemV2ToggleStore
    @State private var didSave = false
    @State private var savedHistorySummary: WorkoutSessionSummary?
    @State private var detailSummary: WorkoutSessionSummary?
    @State private var newlyEarnedTrophyEvents: [TrophyUnlockEvent] = []
    @State private var nearestTrophyProgress: TrophyProgress?

    var body: some View {
        Group {
            if designSystemV2Toggle.isEffectivelyEnabled {
                v2Body
            } else {
                v1Body
            }
        }
        .onAppear {
            if let existing = historyStore.fetchSummary(id: summary.id) {
                didSave = true
                savedHistorySummary = existing
            }
        }
        .sheet(item: $detailSummary) { detail in
            WorkoutDetailSheetView(summary: detail)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
    }

    private var v1Body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Free Analysis Summary")
                    .header(size: 28)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SummaryRow(label: "Exercise", value: summary.exerciseType.displayName)
                    SummaryRow(label: "Duration", value: summary.durationText)
                    SummaryRow(label: "Reps", value: "\(summary.reps)")
                    if summary.holdDuration > 0 {
                        SummaryRow(label: "Hold", value: "\(Int(summary.holdDuration.rounded()))s")
                    }
                    SummaryRow(label: "Form", value: summary.latestFormScore.map { "\($0.grade.rawValue) \($0.score)" } ?? "No completed rep yet")
                    SummaryRow(label: "Peak effort", value: "\(Int(summary.peakEffort * 100))%")
                    SummaryRow(label: "Last cue", value: summary.lastCue?.message ?? "None")
                }

                if let persistenceError = historyStore.persistenceError {
                    Text(persistenceError)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Colors.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FreeAnalysisTrophySection(
                    events: newlyEarnedTrophyEvents,
                    nearestProgress: nearestTrophyProgress
                )

                VStack(spacing: Theme.Spacing.sm) {
                    Button(didSave ? "Saved to history" : "Save to history") {
                        Task {
                            await saveSummary()
                        }
                    }
                    .buttonStyle(PrimaryCTAStyle())
                    .disabled(didSave)
                    .opacity(didSave ? 0.68 : 1)

                    if let savedHistorySummary {
                        Button("View detail") {
                            HapticsEngine.shared.buttonTap()
                            detailSummary = savedHistorySummary
                        }
                        .buttonStyle(SecondaryCTAStyle())
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
    }

    private var v2Body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xs) {
                    Text("Form Check")
                        .font(SpotterV2Typography.caption())
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.primary(themeStore.selectedTheme))

                    Text("Session Summary")
                        .font(SpotterV2Typography.display(size: 38))
                        .fontWidth(.compressed)
                        .italic()
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.58)
                }

                V2Card(theme: themeStore.selectedTheme, radius: SpotterV2.Radius.xl) {
                    VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                        V2SummaryRow(theme: themeStore.selectedTheme, label: "Exercise", value: summary.exerciseType.displayName, systemImage: "figure.strengthtraining.traditional")
                        V2SummaryRow(theme: themeStore.selectedTheme, label: "Duration", value: summary.durationText, systemImage: "timer")
                        V2SummaryRow(theme: themeStore.selectedTheme, label: "Reps", value: "\(summary.reps)", systemImage: "repeat")
                        if summary.holdDuration > 0 {
                            V2SummaryRow(theme: themeStore.selectedTheme, label: "Hold", value: "\(Int(summary.holdDuration.rounded()))s", systemImage: "pause.fill")
                        }
                        V2SummaryRow(
                            theme: themeStore.selectedTheme,
                            label: "Form",
                            value: summary.latestFormScore.map { "\($0.grade.rawValue) \($0.score)" } ?? "No completed rep yet",
                            systemImage: "checkmark.seal.fill"
                        )
                        V2SummaryRow(theme: themeStore.selectedTheme, label: "Peak Effort", value: "\(Int(summary.peakEffort * 100))%", systemImage: "bolt.fill")
                        V2SummaryRow(theme: themeStore.selectedTheme, label: "Last Cue", value: summary.lastCue?.message ?? "None", systemImage: "quote.bubble.fill")
                    }
                }

                if let persistenceError = historyStore.persistenceError {
                    V2Card(
                        theme: themeStore.selectedTheme,
                        borderColor: SpotterV2.Tokens.destructive
                    ) {
                        Text(persistenceError)
                            .font(SpotterV2Typography.body(size: 13, weight: .bold))
                            .foregroundStyle(SpotterV2.Tokens.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                V2FreeAnalysisTrophySection(
                    theme: themeStore.selectedTheme,
                    events: newlyEarnedTrophyEvents,
                    nearestProgress: nearestTrophyProgress
                )

                VStack(spacing: SpotterV2.Spacing.md) {
                    V2CTAButton(
                        title: didSave ? "Saved to History" : "Save to History",
                        systemImage: didSave ? "checkmark" : "tray.and.arrow.down.fill",
                        theme: themeStore.selectedTheme,
                        isDisabled: didSave
                    ) {
                        Task {
                            await saveSummary()
                        }
                    }

                    if let savedHistorySummary {
                        V2SecondaryButton(
                            title: "View Detail",
                            systemImage: "arrow.right",
                            theme: themeStore.selectedTheme
                        ) {
                            HapticsEngine.shared.buttonTap()
                            detailSummary = savedHistorySummary
                        }
                    }
                }
            }
            .padding(SpotterV2.Spacing.xl)
            .padding(.bottom, SpotterV2.Spacing.xl)
        }
        .background(SpotterV2.Tokens.background)
    }

    private func saveSummary() async {
        let historySummary = WorkoutSessionSummary.freeAnalysis(from: summary)
        guard await historyStore.addSummary(historySummary) else { return }
        HapticsEngine.shared.successRipple()
        newlyEarnedTrophyEvents = await trophyStore.update(
            after: historySummary,
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status
        )
        appDependencies.analytics.trackWorkoutSaved(mode: .freeAnalysis)
        appDependencies.analytics.trackTrophyUnlocks(newlyEarnedTrophyEvents)
        nearestTrophyProgress = trophyStore.snapshot.nearestInProgress
        didSave = true
        savedHistorySummary = historySummary
    }
}

private struct FreeAnalysisTrophySection: View {
    let events: [TrophyUnlockEvent]
    let nearestProgress: TrophyProgress?

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Trophies Earned")
                    .font(.system(size: 15, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textPrimary)

                ForEach(events) { event in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Theme.Colors.background)
                            .frame(width: 42, height: 42)
                            .background(Theme.Colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                            Text(event.title)
                                .font(.system(size: 15, weight: .black))
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.Colors.accent)
                            Text(event.reason)
                                .caption()
                        }
                        Spacer()
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.accentMuted)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
            }
        } else if let nearestProgress,
                  let definition = TrophyDefinitionCatalog.definition(for: nearestProgress.trophyId) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Closest Trophy")
                    .font(.system(size: 15, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textPrimary)
                TrophyProgressCard(definition: definition, progress: nearestProgress)
            }
        }
    }
}

private struct V2FreeAnalysisTrophySection: View {
    let theme: SpotterThemeOption
    let events: [TrophyUnlockEvent]
    let nearestProgress: TrophyProgress?

    var body: some View {
        if !events.isEmpty {
            V2Card(
                theme: theme,
                radius: SpotterV2.Radius.lg,
                borderColor: SpotterV2.Tokens.primary(theme).opacity(0.55)
            ) {
                VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                    V2SectionHeader(title: "Trophies Earned")
                    ForEach(events) { event in
                        HStack(spacing: SpotterV2.Spacing.md) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 18, weight: .black))
                                .foregroundStyle(.black)
                                .frame(width: 42, height: 42)
                                .background(SpotterV2.Tokens.primary(theme))
                                .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.sm))

                            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                                Text(event.title)
                                    .font(SpotterV2Typography.heading(size: 15))
                                    .fontWidth(.compressed)
                                    .textCase(.uppercase)
                                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.72)
                                Text(event.reason)
                                    .font(SpotterV2Typography.body(size: 12, weight: .semibold))
                                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                                    .lineLimit(3)
                            }

                            Spacer(minLength: SpotterV2.Spacing.xs)
                        }
                    }
                }
            }
        } else if let nearestProgress,
                  let definition = TrophyDefinitionCatalog.definition(for: nearestProgress.trophyId) {
            V2Card(theme: theme, radius: SpotterV2.Radius.lg) {
                HStack(spacing: SpotterV2.Spacing.md) {
                    Image(systemName: definition.iconName)
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(SpotterV2.Tokens.primary(theme))
                        .frame(width: 44, height: 44)
                        .background(SpotterV2.Tokens.primary(theme).opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.sm))

                    VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                        Text("Closest Trophy")
                            .font(SpotterV2Typography.caption())
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        Text(definition.title)
                            .font(SpotterV2Typography.heading(size: 17))
                            .fontWidth(.compressed)
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.foreground)
                        Text(nearestProgress.progressLabel)
                            .font(SpotterV2Typography.body(size: 12, weight: .semibold))
                            .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    }
                    Spacer(minLength: SpotterV2.Spacing.xs)
                }
            }
        }
    }
}

private struct V2SummaryRow: View {
    let theme: SpotterThemeOption
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: SpotterV2.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.primary(theme))
                .frame(width: 34, height: 34)
                .background(SpotterV2.Tokens.foreground.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xs))

            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                Text(label)
                    .font(SpotterV2Typography.caption())
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                Text(value)
                    .font(SpotterV2Typography.body(size: 15, weight: .bold))
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: SpotterV2.Spacing.xs)
        }
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label.uppercased())
                .caption()
                .frame(width: 100, alignment: .leading)
            Text(value)
                .bodyText()
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

private extension BodyCategory {
    var freeAnalysisTitle: String {
        switch self {
        case .upperBody: "Upper Body"
        case .lowerBody: "Lower Body"
        case .fullBody: "Full Body / Core"
        case .yoga: "Yoga / Mobility"
        }
    }
}

#Preview {
    let dependencies = AppDependencies.local()
    CameraTabView()
        .environmentObject(OnboardingStore())
        .environmentObject(CalibrationStore())
        .environmentObject(WorkoutHistoryStore())
        .environmentObject(TrophyStore())
        .environmentObject(ThemeStore())
        .environmentObject(dependencies)
        .environmentObject(
            DesignSystemV2ToggleStore(
                remoteFlagSnapshotProvider: { false },
                userDefaults: UserDefaults(suiteName: "CameraTabPreview.DesignSystemV2") ?? .standard
            )
        )
}
