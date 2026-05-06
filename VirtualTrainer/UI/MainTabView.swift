import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var themeStore: ThemeStore

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

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
        }
        .tint(themeStore.selectedTheme.accentColor)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    MainTabView()
        .environmentObject(OnboardingStore())
        .environmentObject(CalibrationStore())
        .environmentObject(WorkoutHistoryStore())
        .environmentObject(TrophyStore())
        .environmentObject(ThemeStore())
        .environmentObject(InsightStore())
}
