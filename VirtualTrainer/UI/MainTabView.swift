import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeDashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }

            CameraTabView()
                .tabItem {
                    Label("Camera", systemImage: "camera.fill")
                }

            TrophiesView()
                .tabItem {
                    Label("Trophies", systemImage: "trophy.fill")
                }

            ProfileDebugView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
        }
        .tint(Theme.Colors.accent)
        .preferredColorScheme(.dark)
    }
}

private struct ProfileDebugView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @State private var selectedSummary: WorkoutSessionSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Profile")
                    .header(size: 36)

                if let profile = onboardingStore.profile {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ProfileRow(label: "Name", value: profile.displayName ?? "Athlete")
                        ProfileRow(label: "Age bracket", value: profile.ageBracket.displayName)
                        ProfileRow(label: "Goal", value: profile.primaryGoal.displayName)
                        ProfileRow(label: "Level", value: profile.fitnessLevel.displayName)
                        ProfileRow(label: "Coach", value: profile.preferredCoach.displayName)
                        ProfileRow(label: "Theme", value: profile.selectedTheme.displayName)
                        ProfileRow(label: "Calibration", value: calibrationStore.status.displayName)
                        ProfileRow(
                            label: "Equipment",
                            value: profile.equipment.map(\.displayName).joined(separator: ", ")
                        )
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }

                historySection

                Button("Reset onboarding") {
                    onboardingStore.resetOnboarding()
                }
                .buttonStyle(SecondaryCTAStyle())

                Button("Reset calibration") {
                    calibrationStore.resetForDebug()
                }
                .buttonStyle(SecondaryCTAStyle())

                Text("Debug resets clear local onboarding or calibration state.")
                    .caption()
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
        .sheet(item: $selectedSummary) { summary in
            WorkoutDetailSheetView(summary: summary)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var historySection: some View {
        let stats = historyStore.aggregateStats()
        let recentSummaries = historyStore.fetchRecentSummaries(limit: 6)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Workout History")
                .header(size: 24)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                spacing: Theme.Spacing.sm
            ) {
                HistoryStatCard(label: "Sessions", value: "\(stats.sessionCount)")
                HistoryStatCard(label: "Reps", value: "\(stats.totalReps)")
                HistoryStatCard(label: "Hold", value: durationText(stats.totalHoldSeconds))
                HistoryStatCard(label: "Avg Form", value: stats.averageFormScore.map { "\(Int($0.rounded()))%" } ?? "N/A")
            }

            if recentSummaries.isEmpty {
                Text("Saved planned workouts and free-analysis sessions will appear here.")
                    .caption()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(recentSummaries) { summary in
                        Button {
                            HapticsEngine.shared.buttonTap()
                            selectedSummary = summary
                        } label: {
                            WorkoutHistoryRow(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func durationText(_ seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        guard safeSeconds >= 60 else { return "\(safeSeconds)s" }
        return String(format: "%d:%02d", safeSeconds / 60, safeSeconds % 60)
    }
}

private struct ProfileRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
            Text(label.uppercased())
                .caption()
            Text(value)
                .bodyText()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.xs)
    }
}

private struct HistoryStatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(label)
                .caption()
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

private struct WorkoutHistoryRow: View {
    let summary: WorkoutSessionSummary

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.xxxs) {
                Text(summary.endedAt, format: .dateTime.month(.abbreviated))
                Text(summary.endedAt, format: .dateTime.day())
            }
            .font(.system(size: 11, weight: .black))
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.accent)
            .frame(width: 50, height: 50)
            .background(Theme.Colors.accentMuted)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(summary.title)
                    .font(.system(size: 15, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(detailText)
                    .caption()
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var detailText: String {
        var pieces = [summary.mode.displayName, durationText(summary.durationSeconds)]
        if summary.totalReps > 0 {
            pieces.append("\(summary.totalReps) reps")
        }
        if let score = summary.averageFormScore {
            pieces.append("\(Int(score.rounded()))% form")
        }
        return pieces.joined(separator: " / ")
    }

    private func durationText(_ seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        guard safeSeconds >= 60 else { return "\(safeSeconds)s" }
        return String(format: "%d:%02d", safeSeconds / 60, safeSeconds % 60)
    }
}

#Preview {
    MainTabView()
        .environmentObject(OnboardingStore())
        .environmentObject(CalibrationStore())
        .environmentObject(WorkoutHistoryStore())
        .environmentObject(TrophyStore())
}
