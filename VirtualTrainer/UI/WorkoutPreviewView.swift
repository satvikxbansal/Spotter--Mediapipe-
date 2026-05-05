import SwiftUI

struct WorkoutPreviewView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore

    @State private var previewState: WorkoutPreviewState
    @State private var activePlan: WorkoutPlanV2?
    @State private var statusMessage: String?

    init(plan: WorkoutPlanV2, profile: UserProfile? = nil) {
        _previewState = State(
            initialValue: WorkoutPreviewState(
                plan: plan,
                profile: profile
            )
        )
    }

    private var plan: WorkoutPlanV2 {
        previewState.displayPlan
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                coachSelector
                reasonCard
                insightPlaceholder
                cameraPlanCard
                planBlocks
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            startSessionBar
        }
        .fullScreenCover(item: $activePlan) { plan in
            PlannedWorkoutSessionView(plan: plan)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(plan.title)
                .header(size: 36)

            Text(plan.subtitle)
                .bodyText()
                .foregroundStyle(Theme.Colors.textSecondary)

            Text(plan.goal)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: Theme.Spacing.sm)],
                alignment: .leading,
                spacing: Theme.Spacing.sm
            ) {
                PreviewPill(text: "\(plan.estimatedMinutes) min", systemImage: "clock.fill")
                PreviewPill(text: plan.difficulty.rawValue.capitalized, systemImage: "chart.bar.fill")
                PreviewPill(text: plan.coach.coachName, systemImage: "person.fill")
                PreviewPill(text: "\(previewState.exerciseCount) moves", systemImage: "figure.strengthtraining.traditional")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .previewCard()
    }

    private var coachSelector: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                    Text("Coach")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Applies to this plan unless saved as your default.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                saveDefaultButton
            }

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(CoachPersonality.allCases) { coach in
                    Button {
                        selectCoach(coach)
                    } label: {
                        CoachOptionCard(
                            coach: coach,
                            isSelected: previewState.selectedCoach == coach
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Use \(coach.coachName) for this planned session")
                }
            }
        }
        .previewCard()
    }

    @ViewBuilder
    private var saveDefaultButton: some View {
        if let profile = onboardingStore.profile,
           profile.preferredCoach.coachPersonality != previewState.selectedCoach {
            Button("Save default") {
                saveCoachAsDefault()
            }
            .font(.system(size: 11, weight: .black))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.accent)
        }
    }

    private var reasonCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Why this plan")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(plan.planReason)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .previewCard()
    }

    private var insightPlaceholder: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Theme.Colors.accent)
                Text("Plan insight")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            Text(plan.planReason)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .previewCard()
    }

    private var cameraPlanCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Camera setup")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("\(previewState.cameraSwitchCount)/\(previewState.cameraSwitchLimit) switches")
                    .caption()
            }

            Text(previewState.cameraSequenceText)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.Colors.accent)
                .fixedSize(horizontal: false, vertical: true)

            Text("Swaps are limited to keep this within the plan's camera-switch rule.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .previewCard()
    }

    private var planBlocks: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Exercises")
                    .header(size: 24)
                Spacer()
                Button("Swap all") {
                    swapAll()
                }
                .font(.system(size: 12, weight: .black))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.accent)
            }

            ForEach(Array(plan.blocks.enumerated()), id: \.offset) { _, block in
                WorkoutPreviewBlockView(
                    block: block,
                    onSwap: swapExercise
                )
            }
        }
    }

    private var startSessionBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                startSession()
            } label: {
                Label("Start Session", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryCTAStyle())
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
        .background(Theme.Colors.background)
    }

    private func selectCoach(_ coach: CoachPersonality) {
        guard previewState.selectedCoach != coach else { return }
        HapticsEngine.shared.buttonTap()
        previewState.selectCoach(coach)
        statusMessage = "\(coach.coachName) selected for this plan."
    }

    private func saveCoachAsDefault() {
        HapticsEngine.shared.buttonTap()
        onboardingStore.updatePreferredCoach(
            CoachPreference(coachPersonality: previewState.selectedCoach)
        )
        statusMessage = "\(previewState.selectedCoach.coachName) saved as default."
    }

    private func swapExercise(_ exerciseType: ExerciseType) {
        HapticsEngine.shared.buttonTap()
        let didSwap = previewState.swapExercise(exerciseType)
        statusMessage = didSwap
            ? "Safe swap applied."
            : "No safe swap found for this movement and equipment."
    }

    private func swapAll() {
        HapticsEngine.shared.buttonTap()
        let didSwap = previewState.swapAll()
        statusMessage = didSwap
            ? "Safe swaps applied where available."
            : "No safe swap set found for this plan."
    }

    private func startSession() {
        HapticsEngine.shared.buttonTap()
        guard previewState.startSessionContext() != nil else {
            statusMessage = "This plan has no trackable exercise yet."
            return
        }
        activePlan = previewState.displayPlan
    }
}

private struct WorkoutPreviewBlockView: View {
    let block: WorkoutBlock
    let onSwap: (ExerciseType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(block.title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.Colors.accent)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(block.exercises.enumerated()), id: \.offset) { _, exercise in
                    WorkoutPreviewExerciseRow(
                        exercise: exercise,
                        onSwap: onSwap
                    )
                }
            }
        }
        .previewCard()
    }
}

private struct WorkoutPreviewExerciseRow: View {
    let exercise: PlannedExercise
    let onSwap: (ExerciseType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(exercise.exerciseType.displayName)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(exercise.coachingFocus)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Button {
                    onSwap(exercise.exerciseType)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(exercise.allowSwap ? Theme.Colors.accent : Theme.Colors.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.surfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .disabled(!exercise.allowSwap)
                .accessibilityLabel("Swap \(exercise.exerciseType.displayName)")
            }

            FlowLayout(spacing: Theme.Spacing.xs) {
                ForEach(exercise.sets, id: \.setIndex) { set in
                    ExerciseChip(text: "Set \(set.setIndex): \(set.target.formattedText)")
                }
                ExerciseChip(text: "Rest \(restText)")
                ExerciseChip(text: "Camera \(cameraText)")
            }

            Text(exercise.exerciseType.visibilityHint)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var restText: String {
        let seconds = max(exercise.restSeconds, 0)
        guard seconds >= 60 else { return "\(seconds) sec" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if remainingSeconds == 0 {
            return "\(minutes) min"
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private var cameraText: String {
        WorkoutPreviewState.cameraText(for: exercise.cameraPosition)
    }
}

private struct CoachOptionCard: View {
    let coach: CoachPersonality
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(coach.imageName)
                .resizable()
                .scaledToFill()
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(coach.coachName)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(coach.tagline)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.Colors.accentMuted : Theme.Colors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(isSelected ? Theme.Colors.accent : Theme.Colors.divider, lineWidth: isSelected ? 2 : 1)
        )
    }
}

private struct ExerciseChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Theme.Colors.surfaceRaised)
            .clipShape(Capsule())
    }
}

private struct PreviewPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.accentMuted)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let containerWidth = proposal.width ?? 0
        let rows = rows(
            for: subviews,
            containerWidth: containerWidth
        )
        return CGSize(
            width: containerWidth,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = rows(
            for: subviews,
            containerWidth: bounds.width
        )

        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(
        for subviews: Subviews,
        containerWidth: CGFloat
    ) -> [Row] {
        guard containerWidth > 0 else {
            return [Row(items: subviews.map { Item(subview: $0, size: $0.sizeThatFits(.unspecified)) })]
        }

        var rows: [Row] = []
        var currentItems: [Item] = []
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width
            if nextWidth > containerWidth, !currentItems.isEmpty {
                rows.append(Row(items: currentItems))
                currentItems = [Item(subview: subview, size: size)]
                currentWidth = size.width
            } else {
                currentItems.append(Item(subview: subview, size: size))
                currentWidth = nextWidth
            }
        }

        if !currentItems.isEmpty {
            rows.append(Row(items: currentItems))
        }

        return rows
    }

    private struct Row {
        let items: [Item]

        var height: CGFloat {
            items.map(\.size.height).max() ?? 0
        }
    }

    private struct Item {
        let subview: LayoutSubview
        let size: CGSize
    }
}

private extension View {
    func previewCard() -> some View {
        self
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }
}

#Preview {
    let profile = UserProfile(
        id: UUID(),
        displayName: "Athlete",
        genderIdentity: .preferNotToSay,
        age: 30,
        height: 175,
        heightUnit: .metric,
        weight: 72,
        weightUnit: .metric,
        primaryGoal: .strength,
        fitnessLevel: .beginner,
        equipment: [.bodyweight, .wall, .mat],
        preferredCoach: .bennett,
        selectedTheme: .hyper,
        onboardingCompletedAt: Date(),
        createdAt: Date(),
        updatedAt: Date()
    )

    NavigationStack {
        WorkoutPreviewView(
            plan: PlanService().generateDailyPlan(profile: profile),
            profile: profile
        )
    }
    .environmentObject(OnboardingStore())
}
