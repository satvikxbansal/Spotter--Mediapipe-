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
                        ProfileRow(
                            label: "Equipment",
                            value: profile.equipment.map(\.displayName).joined(separator: ", ")
                        )
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }

                Button("Reset onboarding") {
                    onboardingStore.resetOnboarding()
                }
                .buttonStyle(SecondaryCTAStyle())

                Text("Debug reset clears the local profile and restarts onboarding.")
                    .caption()
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
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

#Preview {
    MainTabView()
        .environmentObject(OnboardingStore())
}
