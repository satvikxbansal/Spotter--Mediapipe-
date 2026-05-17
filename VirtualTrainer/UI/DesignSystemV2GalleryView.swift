#if DEBUG
import SwiftUI

struct DesignSystemV2GalleryView: View {
    @EnvironmentObject private var backendStatusStore: BackendStatusStore

    private let columns = [
        GridItem(.flexible(), spacing: SpotterV2.Spacing.sm),
        GridItem(.flexible(), spacing: SpotterV2.Spacing.sm)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxl) {
                Text("V2 Design Gallery")
                    .font(SpotterV2Typography.display(size: 38))
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)

                ForEach(SpotterThemeOption.allCases) { theme in
                    themeSection(theme)
                }
            }
            .padding(SpotterV2.Spacing.xl)
            .padding(.bottom, SpotterV2.Spacing.xxxl)
        }
        .background(SpotterV2.Tokens.background)
        .navigationTitle("V2 Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private func themeSection(_ theme: SpotterThemeOption) -> some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.lg) {
            V2SectionHeader(
                title: theme.displayName,
                trailingTitle: "All components",
                trailingSystemImage: "square.grid.2x2.fill"
            )

            V2Card(
                theme: theme,
                radius: SpotterV2.Radius.lg,
                hardShadowColor: SpotterV2.Tokens.primary(theme)
            ) {
                VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                    V2StatusPill(theme: theme, label: "Prime condition", pulsingDot: true)
                    Text("Hyper Sprint")
                        .font(SpotterV2Typography.display(size: 42))
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.58)
                    V2CTAButton(title: "Start Training", systemImage: "bolt.fill", theme: theme) {}
                    V2SecondaryButton(title: "Open Evidence", systemImage: "doc.text.magnifyingglass", theme: theme) {}
                    V2DestructiveButton(title: "Delete Workout", systemImage: "trash.fill") {}
                }
            }

            LazyVGrid(columns: columns, spacing: SpotterV2.Spacing.sm) {
                V2MetricPill(theme: theme, eyebrow: "Current streak", value: "12", detail: "Active days", systemImage: "flame.fill")
                V2MetricPill(theme: theme, eyebrow: "Form quality", value: "94%", detail: "Last session", systemImage: "brain.head.profile")
            }

            HStack(alignment: .center, spacing: SpotterV2.Spacing.xl) {
                V2ProgressRing(theme: theme, progress: 0.72, value: "72%", caption: "Trophy")
                V2HeroNumber(value: "07", caption: "Reps", theme: theme)
            }

            V2InsightCard(
                theme: theme,
                eyebrow: "Spotter insight",
                headline: "The first cue is landing earlier.",
                bodyText: "Repeat the same setup for one more workout before increasing target volume.",
                onOpenEvidence: {},
                onHelpful: {},
                onNotHelpful: {}
            )

            V2WorkoutHistoryRow(
                theme: theme,
                date: Date(timeIntervalSince1970: 1_778_067_200),
                title: "Full Body Engine",
                mode: "Planned",
                metrics: ["34m", "48 reps", "94% form"],
                action: {}
            )

            VStack(spacing: SpotterV2.Spacing.sm) {
                V2ExerciseRow(theme: theme, index: 1, name: "Air Squats", target: "3 x 12")
                V2ExerciseRow(theme: theme, index: 2, name: "Running Analysis", target: "Research", isDisabled: true)
            }

            V2TrophyCard(
                theme: theme,
                systemImage: "trophy.fill",
                title: "Depth Charge",
                subtitle: "Complete clean squat reps with reliable depth.",
                rarity: "Rare",
                progress: 0.72
            )

            LazyVGrid(columns: columns, spacing: SpotterV2.Spacing.sm) {
                ForEach(SpotterThemeOption.allCases) { option in
                    V2ThemeOptionCard(theme: option, isSelected: option == theme) {}
                }
            }

            V2EmptyState(
                theme: theme,
                title: "No saved workouts",
                bodyText: "Planned workouts and free-analysis saves will appear here.",
                ctaTitle: "Train now",
                ctaAction: {}
            )

            V2BottomSheetShell(theme: theme, title: "Adjust Movement", onClose: {}) {
                VStack(spacing: SpotterV2.Spacing.sm) {
                    V2ExerciseRow(theme: theme, index: 1, name: "Push Ups", target: "3 x AMRAP")
                    V2SecondaryButton(title: "Reset to Original Plan", systemImage: "arrow.clockwise", theme: theme) {}
                }
            }

            V2BackendStatusChip(mode: backendStatusStore.activeBackendMode, theme: theme)
        }
    }
}

private struct DesignSystemV2GalleryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationStack {
                DesignSystemV2GalleryView()
                    .environmentObject(BackendStatusStore())
            }
            .previewDisplayName("Gallery - SE")
            .previewDevice("iPhone SE (3rd generation)")

            NavigationStack {
                DesignSystemV2GalleryView()
                    .environmentObject(BackendStatusStore())
            }
            .previewDisplayName("Gallery - Pro Max")
            .previewDevice("iPhone 17 Pro Max")
        }
    }
}
#endif
