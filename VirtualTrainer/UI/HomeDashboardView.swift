import SwiftUI

// ────────────────────────────────────────────────────────────────────
// MARK: - HomeDashboardView
// ────────────────────────────────────────────────────────────────────

struct HomeDashboardView: View {

    private let workouts = WorkoutPlan.MockData.all
    private let greeting = Self.timeBasedGreeting()

    @State private var appearAnimationComplete = false
    @AppStorage("coachPersonality") private var selectedPersonality: CoachPersonality = .good

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    statsStrip
                    coachPickerSection
                    workoutSection
                }
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .background(Color.black)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(Theme.Motion.smooth.delay(0.15)) {
                appearAnimationComplete = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(greeting)
                .font(.system(size: 14, weight: .semibold))
                .tracking(2.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.accent)
                .opacity(appearAnimationComplete ? 1 : 0)
                .offset(y: appearAnimationComplete ? 0 : 8)

            Text("SATVIK")
                .font(.system(size: 42, weight: .heavy))
                .tracking(-1.0)
                .foregroundStyle(Theme.Colors.textPrimary)
                .opacity(appearAnimationComplete ? 1 : 0)
                .offset(y: appearAnimationComplete ? 0 : 12)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.xxl)
        .padding(.bottom, Theme.Spacing.lg)
    }

    // MARK: - Quick Stats

    private var statsStrip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button { } label: {
                StatPill(icon: "flame.fill", value: "3", label: "WORKOUTS", tint: Theme.Colors.accent)
            }
            .buttonStyle(PillPressStyle())

            Button { } label: {
                StatPill(icon: "clock.fill", value: "53", label: "MINUTES", tint: Theme.Colors.positive)
            }
            .buttonStyle(PillPressStyle())

            Button { } label: {
                StatPill(icon: "bolt.fill", value: "34", label: "REPS", tint: Theme.Colors.accent)
            }
            .buttonStyle(PillPressStyle())
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.xl)
        .opacity(appearAnimationComplete ? 1 : 0)
        .offset(y: appearAnimationComplete ? 0 : 16)
    }

    // MARK: - Coach Personality Picker

    private var coachPickerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("YOUR COACH")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.lg)

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
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(.bottom, Theme.Spacing.xl)
        .opacity(appearAnimationComplete ? 1 : 0)
        .offset(y: appearAnimationComplete ? 0 : 16)
        .animation(Theme.Motion.smooth.delay(0.18), value: appearAnimationComplete)
    }

    // MARK: - Workouts List

    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("YOUR WORKOUTS")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                    NavigationLink(destination: TrainerSessionView(workout: workout, coachPersonality: selectedPersonality)) {
                        WorkoutCard(workout: workout, index: index)
                    }
                    .buttonStyle(CardPressStyle())
                    .opacity(appearAnimationComplete ? 1 : 0)
                    .offset(y: appearAnimationComplete ? 0 : 20)
                    .animation(
                        Theme.Motion.smooth.delay(0.2 + Double(index) * 0.08),
                        value: appearAnimationComplete
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    // MARK: - Helpers

    private static func timeBasedGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:   return "Good Morning"
        case 12..<17:  return "Good Afternoon"
        case 17..<22:  return "Good Evening"
        default:        return "Late Night"
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Workout Card
// ────────────────────────────────────────────────────────────────────

private struct WorkoutCard: View {

    let workout: WorkoutPlan
    let index: Int

    private var accentColor: Color {
        index % 2 == 0 ? Theme.Colors.accent : Theme.Colors.positive
    }

    private var iconName: String {
        switch index % 3 {
        case 0:  return "figure.strengthtraining.traditional"
        case 1:  return "figure.arms.open"
        default: return "figure.run"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            accentStripe

            HStack(spacing: Theme.Spacing.md) {
                iconBadge
                cardContent
                Spacer(minLength: 0)
                chevron
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    // Thin left accent bar
    private var accentStripe: some View {
        accentColor
            .frame(width: 3)
    }

    // Circular icon badge
    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.12))
                .frame(width: 48, height: 48)

            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accentColor)
        }
    }

    // Title, subtitle, duration
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(workout.title)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)

            Text(workout.subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)

            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .bold))
                Text("\(workout.estimatedMinutes) min")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.top, Theme.Spacing.xxxs)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Stat Pill
// ────────────────────────────────────────────────────────────────────

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Card Press Style (haptics + scale)
// ────────────────────────────────────────────────────────────────────

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    HapticsEngine.shared.buttonTap()
                }
            }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Stat Pill Press Style (haptics + scale + brightness)
// ────────────────────────────────────────────────────────────────────

private struct PillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    HapticsEngine.shared.buttonTap()
                }
            }
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
        VStack(spacing: Theme.Spacing.sm) {
            illustration
            labels
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(isSelected ? tint.opacity(0.10) : Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(isSelected ? tint : Color.clear, lineWidth: 2)
        )
    }

    private var illustration: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(isSelected ? 0.18 : 0.08))
                .frame(width: 72, height: 72)

            Image(systemName: personality.icon)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: isSelected)
        }
    }

    private var labels: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text(personality.displayName)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(isSelected ? tint : Theme.Colors.textPrimary)
                .lineLimit(1)

            Text(personality.tagline)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ────────────────────────────────────────────────────────────────────

#Preview {
    HomeDashboardView()
}
