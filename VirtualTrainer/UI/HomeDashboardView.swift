import SwiftUI

// ────────────────────────────────────────────────────────────────────
// MARK: - HomeDashboardView
// ────────────────────────────────────────────────────────────────────

struct HomeDashboardView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @EnvironmentObject private var trophyStore: TrophyStore

    @State private var dashboardContent: DashboardContent?
    @State private var previewPlan: WorkoutPlanV2?
    @State private var isShowingPlanPreview = false
    @State private var isShowingFormCheckSelection = false
    @State private var isShowingTrophyTeaser = false
    @State private var freeAnalysisSummary: FreeAnalysisSummary?

    private let contentFactory = DashboardContentFactory()

    var body: some View {
        NavigationStack {
            Group {
                if let profile = onboardingStore.profile {
                    dashboard(for: profile)
                } else {
                    MissingProfileDashboard {
                        onboardingStore.resetOnboarding()
                    }
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $isShowingPlanPreview) {
                if let previewPlan {
                    WorkoutPreviewView(
                        plan: previewPlan,
                        profile: onboardingStore.profile
                    )
                }
            }
            .navigationDestination(isPresented: $isShowingFormCheckSelection) {
                FormCheckSelectionView { summary in
                    freeAnalysisSummary = summary
                }
            }
            .navigationDestination(isPresented: $isShowingTrophyTeaser) {
                TrophiesView()
            }
            .sheet(item: $freeAnalysisSummary) { summary in
                FreeAnalysisSummaryView(summary: summary)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .preferredColorScheme(.dark)
        }
        .onAppear(perform: refreshDashboard)
            .onChange(of: onboardingStore.profile) {
                refreshDashboard()
            }
            .onChange(of: historyStore.summaries) {
                refreshDashboard()
            }
    }

    private func dashboard(for profile: UserProfile) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if let dashboardContent {
                    DashboardHeader(content: dashboardContent)

                    SmartStartCard(
                        variant: dashboardContent.currentSmartStart,
                        totalVariants: dashboardContent.smartStartDeck.variants.count,
                        onStart: {
                            openPreview(for: dashboardContent.currentSmartStart.plan)
                        },
                        onSwap: cycleSmartStartPlan
                    )

                    DailyPlanCard(summary: dashboardContent.dailyPlan) {
                        openPreview(for: dashboardContent.dailyPlan.plan)
                    }

                    QuickActionGrid(
                        actions: dashboardContent.quickActions,
                        onSelect: handleQuickAction
                    )

                    TrophyTeaserCard(text: dashboardContent.trophyTeaserText) {
                        isShowingTrophyTeaser = true
                    }

                    if let recentWorkout = dashboardContent.recentWorkout {
                        RecentWorkoutCard(recentWorkout: recentWorkout)
                    }
                } else {
                    ProgressView()
                        .tint(Theme.Colors.accent)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .refreshable {
            trophyStore.updateAll(
                history: historyStore.summaries,
                calibrationStatus: calibrationStore.status
            )
            dashboardContent = contentFactory.makeContent(
                profile: profile,
                recentWorkoutHistory: historyStore.recentWorkoutHistoryItems(),
                currentStreakDayCount: historyStore.aggregateStats().currentStreak,
                trophySnapshot: trophyStore.snapshot
            )
        }
    }

    private func refreshDashboard() {
        guard let profile = onboardingStore.profile else {
            dashboardContent = nil
            return
        }

        trophyStore.updateAll(
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status
        )

        dashboardContent = contentFactory.makeContent(
            profile: profile,
            recentWorkoutHistory: historyStore.recentWorkoutHistoryItems(),
            currentStreakDayCount: historyStore.aggregateStats().currentStreak,
            trophySnapshot: trophyStore.snapshot
        )
    }

    private func openPreview(for plan: WorkoutPlanV2) {
        HapticsEngine.shared.buttonTap()
        previewPlan = plan
        isShowingPlanPreview = true
    }

    private func cycleSmartStartPlan() {
        guard var content = dashboardContent else { return }
        HapticsEngine.shared.buttonTap()
        content.advanceSmartStartPlan()
        withAnimation(Theme.Motion.snappy) {
            dashboardContent = content
        }
    }

    private func handleQuickAction(_ action: DashboardQuickAction) {
        guard action.isEnabled else { return }
        HapticsEngine.shared.buttonTap()

        switch action.destination {
        case .formCheckSelection:
            isShowingFormCheckSelection = true
        case .trophies:
            isShowingTrophyTeaser = true
        case .runningAnalysis, nil:
            break
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Header
// ────────────────────────────────────────────────────────────────────

private struct DashboardHeader: View {
    let content: DashboardContent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(content.greeting)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text(content.athleteName)
                    .header(size: 42)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Label(content.streak.title, systemImage: "flame.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.accentMuted)
                    .clipShape(Capsule())

                Text(content.streak.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Text("Train Now")
                .header(size: 36)
                .padding(.top, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Plan Cards
// ────────────────────────────────────────────────────────────────────

private struct SmartStartCard: View {
    let variant: QuickStartPlanVariant
    let totalVariants: Int
    let onStart: () -> Void
    let onSwap: () -> Void

    private var summary: DashboardPlanSummary {
        DashboardPlanSummary(plan: variant.plan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                DashboardBadge(text: variant.intensityLabel.displayName)
                Spacer()
                Text(summary.durationText)
                    .caption()
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Smart Start")
                    .header(size: 30)
                Text(summary.title)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(summary.reason)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(3)
            }

            HStack(spacing: Theme.Spacing.sm) {
                if totalVariants > 1 {
                    Button(action: onSwap) {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(SecondaryCTAStyle())
                    .accessibilityHint("Show another Quick Start plan")
                }

                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryCTAStyle())
            }
        }
        .dashboardCard()
        .id(variant.id)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

private struct DailyPlanCard: View {
    let summary: DashboardPlanSummary
    let onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Daily Plan")
                        .header(size: 26)
                    Text(summary.title)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("\(summary.exerciseCount) exercises • \(summary.durationText)")
                        .caption()
                }

                Spacer(minLength: Theme.Spacing.md)
            }

            Text(summary.reason)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(3)

            Button("Preview plan", action: onPreview)
                .buttonStyle(SecondaryCTAStyle())
        }
        .dashboardCard()
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Quick Actions
// ────────────────────────────────────────────────────────────────────

private struct QuickActionGrid: View {
    let actions: [DashboardQuickAction]
    let onSelect: (DashboardQuickAction) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.sm),
        GridItem(.flexible(), spacing: Theme.Spacing.sm),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
            ForEach(actions) { action in
                Button {
                    onSelect(action)
                } label: {
                    DashboardActionCard(action: action)
                }
                .buttonStyle(DashboardCardButtonStyle())
                .disabled(!action.isEnabled)
                .accessibilityHint(action.statusLabel ?? action.subtitle)
            }
        }
    }
}

private struct DashboardActionCard: View {
    let action: DashboardQuickAction

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: action.systemImage)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(action.isEnabled ? Theme.Colors.accent : Theme.Colors.textTertiary)

                Spacer()

                if let statusLabel = action.statusLabel {
                    DashboardBadge(text: statusLabel)
                        .opacity(action.isEnabled ? 1 : 0.75)
                }
            }

            Spacer(minLength: Theme.Spacing.md)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(action.title)
                    .font(.system(size: 18, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(action.isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(action.subtitle)
                    .caption()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(action.isEnabled ? Theme.Colors.surface : Theme.Colors.surface.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(action.isEnabled ? Theme.Colors.divider : Theme.Colors.textTertiary.opacity(0.35), lineWidth: 1)
        )
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Secondary Cards
// ────────────────────────────────────────────────────────────────────

private struct TrophyTeaserCard: View {
    let text: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.accentMuted)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Trophy Case")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .dashboardCard()
        }
        .buttonStyle(DashboardCardButtonStyle())
    }
}

private struct RecentWorkoutCard: View {
    let recentWorkout: DashboardRecentWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Recent Workout")
                .header(size: 22)
            HStack {
                Text(recentWorkout.title)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(recentWorkout.completedAt, style: .date)
                    .caption()
            }
        }
        .dashboardCard()
    }
}

private struct MissingProfileDashboard: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Spacer()

            Text("Profile Needed")
                .header(size: 34)
            Text("Dashboard plans need your local onboarding profile first.")
                .bodyText()
                .foregroundStyle(Theme.Colors.textSecondary)

            Button("Start onboarding", action: onStart)
                .buttonStyle(PrimaryCTAStyle())

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.background)
    }
}

private struct DashboardBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .black))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.background)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxxs)
            .background(Theme.Colors.accent)
            .clipShape(Capsule())
    }
}

private struct DashboardCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

private extension View {
    func dashboardCard() -> some View {
        self
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ────────────────────────────────────────────────────────────────────

#Preview {
    HomeDashboardView()
        .environmentObject(OnboardingStore())
        .environmentObject(CalibrationStore())
        .environmentObject(WorkoutHistoryStore())
        .environmentObject(TrophyStore())
}
