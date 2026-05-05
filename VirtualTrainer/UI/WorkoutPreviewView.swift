import SwiftUI

struct WorkoutPreviewView: View {
    let plan: WorkoutPlanV2

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                reasonCard
                planBlocks
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(plan.title)
                .header(size: 36)

            Text(plan.subtitle)
                .bodyText()
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.sm) {
                PreviewPill(text: "\(plan.estimatedMinutes) min", systemImage: "clock.fill")
                PreviewPill(text: plan.difficulty.rawValue.capitalized, systemImage: "chart.bar.fill")
                PreviewPill(text: plan.coach.displayName, systemImage: "person.fill")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reasonCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Why this plan")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(plan.planReason)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .previewCard()
    }

    private var planBlocks: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Exercises")
                .header(size: 24)

            ForEach(Array(plan.blocks.enumerated()), id: \.offset) { _, block in
                WorkoutPreviewBlockView(block: block)
            }
        }
    }
}

private struct WorkoutPreviewBlockView: View {
    let block: WorkoutBlock

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(block.title)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.Colors.accent)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(block.exercises.enumerated()), id: \.offset) { _, exercise in
                    WorkoutPreviewExerciseRow(exercise: exercise)
                }
            }
        }
        .previewCard()
    }
}

private struct WorkoutPreviewExerciseRow: View {
    let exercise: PlannedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                    Text(exercise.exerciseType.displayName)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(exercise.coachingFocus)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.md)

                Text(cameraText)
                    .caption()
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(exercise.sets, id: \.setIndex) { set in
                    Text("Set \(set.setIndex): \(set.target.formattedText)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(Theme.Colors.surfaceRaised)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var cameraText: String {
        switch exercise.cameraPosition {
        case .front:
            return "Front"
        case .side:
            return "Side"
        }
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
            .background(Theme.Colors.accentMuted)
            .clipShape(Capsule())
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
    NavigationStack {
        WorkoutPreviewView(plan: PlanService().generateDailyPlan(profile: UserProfile(
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
            equipment: [.bodyweight],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            onboardingCompletedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )))
    }
}
