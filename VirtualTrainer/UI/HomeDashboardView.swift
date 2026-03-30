import SwiftUI

// ────────────────────────────────────────────────────────────────────
// MARK: - HomeDashboardView
// ────────────────────────────────────────────────────────────────────

struct HomeDashboardView: View {

    // MARK: - Splash Animation State

    @State private var splashPhase: SplashPhase = .hidden
    @State private var showDashboard = false

    // MARK: - Sheet State

    @State private var selectedCategory: BodyCategory?
    @State private var showExerciseSheet = false
    @State private var selectedExercise: String?
    @State private var showCoachSheet = false
    @State private var selectedPersonality: CoachPersonality = .good
    @State private var navigateToSession = false

    // MARK: - Dashboard Animation

    @State private var dashboardAppeared = false

    private enum SplashPhase {
        case hidden
        case welcomeVisible
        case brandRevealed
        case transitionOut
        case done
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if showDashboard {
                    dashboardContent
                        .transition(.opacity)
                }

                splashOverlay
            }
            .navigationDestination(isPresented: $navigateToSession) {
                TrainerSessionView(
                    workout: buildWorkoutPlan(),
                    coachPersonality: selectedPersonality
                )
            }
            .preferredColorScheme(.dark)
        }
        .onAppear { startSplashSequence() }
    }

    // MARK: - Splash Overlay

    private var splashOverlay: some View {
        ZStack {
            if splashPhase != .done {
                Color.black.ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 12) {
                    Text("Welcome to")
                        .font(.system(size: 18, weight: .medium))
                        .tracking(4.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Color(white: 0.5))
                        .opacity(splashWelcomeOpacity)

                    Text("Spotter")
                        .font(.system(size: 72, weight: .bold))
                        .tracking(-1.5)
                        .foregroundStyle(Color(white: 0.93))
                        .opacity(splashBrandOpacity)
                        .scaleEffect(splashBrandScale)
                }
                .offset(y: splashPhase == .transitionOut ? -30 : 0)
                .animation(.easeInOut(duration: 0.5), value: splashPhase)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: splashPhase)
    }

    private var splashWelcomeOpacity: Double {
        switch splashPhase {
        case .hidden: 0
        case .welcomeVisible, .brandRevealed: 1
        case .transitionOut, .done: 0
        }
    }

    private var splashBrandOpacity: Double {
        switch splashPhase {
        case .hidden, .welcomeVisible: 0
        case .brandRevealed: 1
        case .transitionOut, .done: 0
        }
    }

    private var splashBrandScale: CGFloat {
        switch splashPhase {
        case .hidden, .welcomeVisible: 0.88
        case .brandRevealed: 1.0
        case .transitionOut, .done: 0.95
        }
    }

    private func startSplashSequence() {
        withAnimation(.easeOut(duration: 0.5)) {
            splashPhase = .welcomeVisible
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.5)) {
                splashPhase = .brandRevealed
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showDashboard = true
            withAnimation(.easeInOut(duration: 0.5)) {
                splashPhase = .transitionOut
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            splashPhase = .done
            withAnimation(Theme.Motion.smooth.delay(0.1)) {
                dashboardAppeared = true
            }
        }
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                dashboardHeader
                categorySection
            }
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Color.black)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showExerciseSheet) {
            exerciseSelectionSheet
                .presentationDetents([exerciseSheetDetent])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showCoachSheet) {
            coachSelectionSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Dashboard Header

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("SPOTTER")
                            .font(.system(size: 14, weight: .black))
                            .tracking(2.0)
                            .foregroundStyle(Theme.Colors.accent)

                        Circle()
                            .fill(Theme.Colors.accent)
                            .frame(width: 4, height: 4)

                        Text(timeBasedGreeting().uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }

                    Text("Hey, \(UserProfile.firstName)")
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Spacer()
            }
            .opacity(dashboardAppeared ? 1 : 0)
            .offset(y: dashboardAppeared ? 0 : 10)

            Text("What would you like to train today?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .opacity(dashboardAppeared ? 1 : 0)
                .offset(y: dashboardAppeared ? 0 : 12)
                .animation(Theme.Motion.smooth.delay(0.08), value: dashboardAppeared)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xxl)
        .padding(.bottom, Theme.Spacing.xl)
    }

    // MARK: - Body Category Cards

    private var categorySection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(Array(BodyCategory.allCases.enumerated()), id: \.element.id) { index, category in
                Button {
                    HapticsEngine.shared.buttonTap()
                    selectedCategory = category
                    selectedExercise = nil
                    showExerciseSheet = true
                } label: {
                    BodyCategoryCard(category: category)
                }
                .buttonStyle(CardPressStyle())
                .opacity(dashboardAppeared ? 1 : 0)
                .offset(y: dashboardAppeared ? 0 : 20)
                .animation(
                    Theme.Motion.smooth.delay(0.15 + Double(index) * 0.08),
                    value: dashboardAppeared
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: - Exercise Selection Sheet

    private var exerciseSelectionSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let category = selectedCategory {
                let available = category.exercises.filter(\.available)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(category.displayName.uppercased())
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(1.8)
                        .foregroundStyle(Theme.Colors.accent)

                    Text("Pick an exercise")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(available) { exercise in
                        AvailableExerciseRow(
                            exercise: exercise,
                            isSelected: selectedExercise == exercise.id,
                            onTap: {
                                selectedExercise = exercise.id
                                HapticsEngine.shared.buttonTap()
                            }
                        )
                    }
                }

                Spacer(minLength: 0)

                Button {
                    HapticsEngine.shared.buttonTap()
                    showExerciseSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showCoachSheet = true
                    }
                } label: {
                    Text("Lock in & pick your coach")
                }
                .buttonStyle(PrimaryCTAStyle())
                .disabled(selectedExercise == nil)
                .opacity(selectedExercise == nil ? 0.5 : 1.0)
                .padding(.bottom, Theme.Spacing.xs)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xl)
    }

    // MARK: - Coach Selection Sheet

    private var coachSelectionSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("CHOOSE YOUR COACH")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1.8)
                    .foregroundStyle(Theme.Colors.accent)

                Text("Who's spotting you today?")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(CoachPersonality.allCases) { personality in
                    Button {
                        withAnimation(Theme.Motion.snappy) {
                            selectedPersonality = personality
                        }
                        HapticsEngine.shared.buttonTap()
                    } label: {
                        CoachPersonalityCard(
                            personality: personality,
                            isSelected: selectedPersonality == personality
                        )
                    }
                    .buttonStyle(CardPressStyle())
                }
            }

            Spacer(minLength: 0)

            Button {
                HapticsEngine.shared.buttonTap()
                showCoachSheet = false
                Task {
                    await VoiceCoachManager.shared.playMotivation(
                        text: "Welcome, lets get started",
                        personality: selectedPersonality
                    )
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    navigateToSession = true
                }
            } label: {
                Text("Let's go")
            }
            .buttonStyle(PrimaryCTAStyle())
            .padding(.bottom, Theme.Spacing.xs)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xl)
    }

    // MARK: - Logic

    /// Computes the ideal sheet height based on exercise count.
    private var exerciseSheetDetent: PresentationDetent {
        let count = selectedCategory?.exercises.filter(\.available).count ?? 0
        // Header (~100) + rows (56 each) + button (~70) + padding (~60)
        let height = CGFloat(100 + count * 56 + 70 + 60)
        return .height(height)
    }

    private func buildWorkoutPlan() -> WorkoutPlan {
        guard let category = selectedCategory,
              let exerciseId = selectedExercise,
              let exercise = category.exercises.first(where: { $0.id == exerciseId }),
              let type = exercise.type
        else {
            return WorkoutPlan.MockData.legDay
        }

        return WorkoutPlan(
            title: exercise.name,
            subtitle: category.displayName,
            exercises: [
                WorkoutSet(exerciseType: type, targetReps: 12),
                WorkoutSet(exerciseType: type, targetReps: 12),
                WorkoutSet(exerciseType: type, targetReps: 10),
            ],
            estimatedMinutes: 10
        )
    }

    private func timeBasedGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:   return "Morning"
        case 12..<17:  return "Afternoon"
        case 17..<22:  return "Evening"
        default:        return "Late Night"
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Body Category Card
// ────────────────────────────────────────────────────────────────────

private struct BodyCategoryCard: View {

    let category: BodyCategory

    var body: some View {
        HStack(spacing: 0) {
            Theme.Colors.accent
                .frame(width: 3)

            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.accent.opacity(0.12))
                        .frame(width: 52, height: 52)

                    Image(systemName: category.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(category.displayName)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    Text(category.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Available Exercise Row (with checkbox)
// ────────────────────────────────────────────────────────────────────

private struct AvailableExerciseRow: View {

    let exercise: ExerciseOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.md) {
                // Radio button
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary,
                            lineWidth: 2
                        )
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Theme.Colors.accent)
                            .frame(width: 12, height: 12)
                    }
                }

                Text(exercise.name)
                    .font(.system(size: 16, weight: isSelected ? .heavy : .semibold))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textPrimary)

                Spacer()
            }
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isSelected ? Theme.Colors.accent.opacity(0.08) : Theme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? Theme.Colors.accent.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.snappy, value: isSelected)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Coach Personality Card
// ────────────────────────────────────────────────────────────────────

private struct CoachPersonalityCard: View {

    let personality: CoachPersonality
    let isSelected: Bool

    private var tint: Color { personality.accentColor }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            coachPhoto
            coachInfo
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.md + 2)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(isSelected ? tint.opacity(0.10) : Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(isSelected ? tint : Color.clear, lineWidth: 2)
        )
    }

    private var coachPhoto: some View {
        Image(personality.imageName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        isSelected ? tint : Theme.Colors.divider,
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .shadow(color: isSelected ? tint.opacity(0.4) : .clear, radius: 10)
    }

    private var coachInfo: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(personality.coachName)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(isSelected ? tint : Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(personality.tagline)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.xxs)
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Card Press Style
// ────────────────────────────────────────────────────────────────────

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ────────────────────────────────────────────────────────────────────

#Preview {
    HomeDashboardView()
}
