import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @EnvironmentObject private var trophyStore: TrophyStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var insightStore: InsightStore

    @State private var selectedSummary: WorkoutSessionSummary?
    @State private var isShowingAllHistory = false
    @State private var profileInsights: [AIInsight] = []
    @State private var weeklyRecap: WeeklyRecap?
    @State private var selectedInsightEvidence: AIInsight?
    @State private var pendingDeleteSummary: WorkoutSessionSummary?
    @State private var isConfirmingHistoryDelete = false
    @State private var isSampleDataEnabled = false
    @State private var debugStatusMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let profile = onboardingStore.profile {
                    profileContent(for: profile)
                } else {
                    MissingProfileHub()
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $isShowingAllHistory) {
                WorkoutHistoryListView(
                    summaries: historyStore.fetchRecentSummaries(limit: historyStore.summaries.count),
                    onSelect: openSummary,
                    onDelete: requestDelete
                )
            }
            .sheet(item: $selectedSummary) { summary in
                WorkoutDetailSheetView(summary: summary)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "Delete Workout?",
                isPresented: $isConfirmingHistoryDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Workout", role: .destructive) {
                    if let pendingDeleteSummary {
                        deleteSummary(pendingDeleteSummary)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the workout from your visible history.")
            }
            .sheet(item: $selectedInsightEvidence) { insight in
                InsightEvidenceSheetView(
                    insight: insight,
                    summaries: historyStore.summaries
                ) { kind in
                    Task {
                        await insightStore.recordEngagement(insight, kind: kind)
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                Task {
                    await refreshProfileData()
                }
            }
            .onChange(of: historyStore.summaries) {
                Task {
                    await refreshProfileData()
                }
            }
            .onChange(of: calibrationStore.status) {
                Task {
                    await refreshTrophies()
                }
            }
            .onChange(of: onboardingStore.profile) {
                Task {
                    await themeStore.sync(with: onboardingStore.profile)
                    await refreshProfileData()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func profileContent(for profile: UserProfile) -> some View {
        let now = Date()
        let stats = StatsEngine().makeStats(
            history: historyStore.summaries,
            trophySnapshot: trophyStore.snapshot,
            now: now
        )
        let trendEngine = TrendEngine()
        let trendSnapshot = trendEngine.buildSnapshot(
            history: historyStore.summaries,
            profile: profile,
            trophies: trophyStore.snapshot,
            now: now
        )
        let calendarSnapshot = trendEngine.monthSnapshot(
            history: historyStore.summaries,
            profile: profile,
            now: now
        )
        let heatmapSummary = trendEngine.dailyIntensitySummary(
            history: historyStore.summaries,
            profile: profile,
            days: TrainingHeatmapView.defaultDayCount,
            now: now
        )
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ProfileHeaderView(
                    profile: profile,
                    stats: stats,
                    accent: themeStore.selectedTheme.accentColor
                )

                TrophyShowcaseSection(snapshot: trophyStore.snapshot)

                ProfileThemeSelector(
                    selectedTheme: themeStore.selectedTheme,
                    onSelect: updateTheme
                )

                TrainingPreferenceSection(
                    profile: profile,
                    accent: themeStore.selectedTheme.accentColor,
                    onGoalChange: { goal in
                        Task {
                            _ = await onboardingStore.updatePrimaryGoal(goal)
                        }
                    },
                    onCoachChange: { coach in
                        Task {
                            _ = await onboardingStore.updatePreferredCoach(coach)
                        }
                    },
                    onSessionLengthChange: { sessionLength in
                        Task {
                            _ = await onboardingStore.updatePreferredSessionLength(sessionLength)
                        }
                    }
                )

                ProfileStatsGrid(stats: stats)

                WorkoutSnapshotCard(
                    snapshot: trendSnapshot,
                    calendarSnapshot: calendarSnapshot,
                    heatmapSummary: heatmapSummary,
                    profile: profile,
                    accent: themeStore.selectedTheme.accentColor
                )

                if let weeklyRecap {
                    ProfileWeeklyRecapCard(
                        recap: weeklyRecap,
                        onAppear: {
                            Task {
                                await insightStore.recordPresentation(
                                    dedupeKey: weeklyRecap.dedupeKey,
                                    on: .profile
                                )
                            }
                        }
                    )
                }

                CoachInsightsCard(
                    profile: profile,
                    insights: profileInsights,
                    onAppear: { insight in
                        Task {
                            await insightStore.recordImpression(insight, on: .profile)
                        }
                    },
                    onEngagement: { insight, kind in
                        Task {
                            await insightStore.recordEngagement(insight, kind: kind)
                        }
                    },
                    onOpenEvidence: { insight in
                        Task {
                            await insightStore.recordEngagement(insight, kind: .opened)
                        }
                        selectedInsightEvidence = insight
                    }
                )

                WorkoutHistorySection(
                    summaries: historyStore.fetchRecentSummaries(limit: 5),
                    onSelect: openSummary,
                    onDelete: requestDelete,
                    onViewAll: {
                        HapticsEngine.shared.buttonTap()
                        isShowingAllHistory = true
                    }
                )

                SettingsDebugSection(
                    profile: profile,
                    calibrationStatus: calibrationStore.status,
                    isSampleDataEnabled: isSampleDataEnabled,
                    debugStatusMessage: debugStatusMessage,
                    onSampleDataToggle: setSampleDataEnabledForTesting,
                    onResetOnboarding: {
                        Task {
                            await onboardingStore.resetOnboarding()
                        }
                    },
                    onResetCalibration: {
                        Task {
                            await calibrationStore.resetForDebug()
                        }
                    }
                )
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
    }

    private func refreshProfileData() async {
        await themeStore.sync(with: onboardingStore.profile)
        guard let profile = onboardingStore.profile else {
            profileInsights = []
            weeklyRecap = nil
            isSampleDataEnabled = false
            return
        }
        let now = Date()
        await trophyStore.updateAll(
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status,
            now: now
        )
        weeklyRecap = makeWeeklyRecap(profile: profile, now: now)
        await refreshProfileInsights(profile: profile, now: now)
        isSampleDataEnabled = LocalUITestingSampleData.isPresent(
            history: historyStore.summaries,
            insights: insightStore.recentInsights
        )
    }

    private func refreshTrophies() async {
        let now = Date()
        await trophyStore.updateAll(
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status,
            now: now
        )
        if let profile = onboardingStore.profile {
            weeklyRecap = makeWeeklyRecap(profile: profile, now: now)
            await refreshProfileInsights(profile: profile, now: now)
        }
    }

    private func refreshProfileInsights(
        profile: UserProfile,
        now: Date
    ) async {
        let trendEngine = TrendEngine()
        let trendSnapshot = trendEngine.buildSnapshot(
            history: historyStore.summaries,
            profile: profile,
            trophies: trophyStore.snapshot,
            now: now
        )
        let signals = SignalExtractor(trendEngine: trendEngine).extractSignals(
            snapshot: trendSnapshot,
            history: historyStore.summaries,
            profile: profile,
            trophies: trophyStore.snapshot,
            context: SignalGenerationContext(historySessionCount: historyStore.summaries.count)
        )
        let generated = await InsightEngine().generateProfileInsights(
            profile: profile,
            trendSnapshot: trendSnapshot,
            signals: signals,
            trophies: trophyStore.snapshot,
            engagementRecords: insightStore.engagementRecordsSnapshot(),
            now: now
        )
        profileInsights = await insightStore.selectInsights(
            generated,
            for: .profile,
            profile: profile,
            limit: 2,
            now: now
        )
    }

    private func makeWeeklyRecap(
        profile: UserProfile,
        now: Date
    ) -> WeeklyRecap? {
        guard let recap = WeeklyRecapBuilder().build(
            history: historyStore.summaries,
            profile: profile,
            trophies: trophyStore.snapshot,
            now: now
        ) else { return nil }
        return insightStore.canPresentOnce(dedupeKey: recap.dedupeKey, on: .profile) ? recap : nil
    }

    private func updateTheme(_ theme: SpotterThemeOption) {
        HapticsEngine.shared.buttonTap()
        Task {
            guard await onboardingStore.updateSelectedTheme(theme) else { return }
            await themeStore.updateSelectedTheme(theme)
        }
    }

    private func openSummary(_ summaryID: UUID) {
        guard let summary = ProfileHistorySelection.detailSummary(
            for: summaryID,
            in: historyStore.summaries
        ) else { return }
        HapticsEngine.shared.buttonTap()
        selectedSummary = summary
    }

    private func requestDelete(_ summary: WorkoutSessionSummary) {
        HapticsEngine.shared.buttonTap()
        pendingDeleteSummary = summary
        isConfirmingHistoryDelete = true
    }

    private func setSampleDataEnabledForTesting(_ isEnabled: Bool) {
        Task {
            if isEnabled {
                await loadSampleDataForTesting()
            } else {
                await clearSampleDataForTesting()
            }
        }
    }

    private func loadSampleDataForTesting() async {
        guard let profile = onboardingStore.profile else { return }

        debugStatusMessage = nil
        let now = Date()
        let sampleHistory = LocalUITestingSampleData.workoutHistory(
            now: now,
            coach: profile.preferredCoach.coachPersonality
        )
        var didSaveHistory = true
        for summary in sampleHistory {
            didSaveHistory = await historyStore.addSummary(summary) && didSaveHistory
        }

        guard didSaveHistory else {
            debugStatusMessage = historyStore.persistenceError ?? "Could not save sample workout history."
            return
        }

        await trophyStore.updateAll(
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status,
            now: now
        )
        let didSaveInsights = await insightStore.seedInsightsForDebug(
            LocalUITestingSampleData.insights(
                for: sampleHistory,
                profile: profile,
                now: now
            ),
            replacingInsightsReferencing: LocalUITestingSampleData.workoutIDs,
            now: now
        )
        guard didSaveInsights else {
            debugStatusMessage = insightStore.persistenceError ?? "Could not save sample coach insights."
            return
        }
        await refreshProfileData()
        isSampleDataEnabled = true
        debugStatusMessage = "Loaded 4 sample workouts and 3 coach insights."
        HapticsEngine.shared.successRipple()
    }

    private func clearSampleDataForTesting() async {
        debugStatusMessage = nil
        let sampleWorkoutIDs = LocalUITestingSampleData.workoutIDs
        let now = Date()

        guard await historyStore.removeSummariesForDebug(ids: sampleWorkoutIDs) else {
            debugStatusMessage = historyStore.persistenceError ?? "Could not clear sample workout history."
            return
        }
        guard await insightStore.removeInsightsForDebug(
            dedupeKeys: LocalUITestingSampleData.insightDedupeKeys,
            referencingWorkoutIds: sampleWorkoutIDs
        ) else {
            debugStatusMessage = insightStore.persistenceError ?? "Could not clear sample coach insights."
            return
        }
        guard await trophyStore.recalculateForDebug(
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status,
            now: now
        ) else {
            debugStatusMessage = trophyStore.persistenceError ?? "Could not refresh trophies after clearing sample data."
            return
        }

        if let selectedSummary, sampleWorkoutIDs.contains(selectedSummary.id) {
            self.selectedSummary = nil
        }
        if let pendingDeleteSummary, sampleWorkoutIDs.contains(pendingDeleteSummary.id) {
            self.pendingDeleteSummary = nil
            isConfirmingHistoryDelete = false
        }
        if let selectedInsightEvidence,
           LocalUITestingSampleData.isSampleInsight(selectedInsightEvidence) {
            self.selectedInsightEvidence = nil
        }

        await refreshProfileData()
        isSampleDataEnabled = false
        debugStatusMessage = "Cleared sample workouts and coach insights."
        HapticsEngine.shared.successRipple()
    }

    private func deleteSummary(_ summary: WorkoutSessionSummary) {
        Task {
            guard await historyStore.deleteSummary(id: summary.id) else { return }
            _ = await insightStore.invalidateInsightsReferencingWorkout(id: summary.id)
            await trophyStore.updateAll(
                history: historyStore.summaries,
                calibrationStatus: calibrationStore.status
            )
            if selectedSummary?.id == summary.id {
                selectedSummary = nil
            }
            pendingDeleteSummary = nil
            await refreshProfileData()
            HapticsEngine.shared.successRipple()
        }
    }
}

private struct ProfileHeaderView: View {
    let profile: UserProfile
    let stats: UserStats
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Text(initials)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Colors.background)
                    .frame(width: 72, height: 72)
                    .background(accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg)
                            .stroke(Theme.Colors.textPrimary.opacity(0.18), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(profile.displayName ?? "Athlete")
                        .header(size: 32)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text("Level \(stats.level) / \(stats.xp) XP")
                        .font(.system(size: 12, weight: .black))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(accent)
                }

                Spacer(minLength: Theme.Spacing.sm)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ProgressView(value: stats.levelProgressFraction)
                    .tint(accent)

                HStack {
                    Text("\(stats.xpIntoCurrentLevel)/\(stats.xpNeededForNextLevel) XP to Level \(stats.level + 1)")
                    Spacer()
                    Text("\(stats.trophiesEarned) trophies")
                }
                .caption()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var initials: String {
        let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = String(parts).uppercased()
        return value.isEmpty ? "S" : value
    }
}

private struct TrophyShowcaseSection: View {
    let snapshot: TrophyProgressSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ProfileSectionHeader(title: "Trophies") {
                NavigationLink {
                    TrophyCollectionView()
                } label: {
                    Text("View All")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }

            let earned = earnedProgress
            if earned.isEmpty {
                EmptyProfileCard(
                    systemImage: "trophy.fill",
                    title: "No trophies earned yet",
                    subtitle: "Save a workout or complete calibration to start the collection."
                )
            } else {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(earned.prefix(4)) { progress in
                        if let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId) {
                            TrophyMiniTile(definition: definition)
                        }
                    }
                }
            }

            if let nearest = snapshot.nearestInProgress,
               let definition = TrophyDefinitionCatalog.definition(for: nearest.trophyId) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Nearest")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    TrophyProgressCard(definition: definition, progress: nearest)
                }
            }
        }
    }

    private var earnedProgress: [TrophyProgress] {
        snapshot.earnedProgress
            .filter { TrophyDefinitionCatalog.definition(for: $0.trophyId)?.isComingSoon == false }
            .sorted { lhs, rhs in
                let lhsDate = lhs.earnedAt ?? .distantPast
                let rhsDate = rhs.earnedAt ?? .distantPast
                if lhsDate == rhsDate {
                    return sortOrder(lhs) < sortOrder(rhs)
                }
                return lhsDate > rhsDate
            }
    }

    private func sortOrder(_ progress: TrophyProgress) -> Int {
        TrophyDefinitionCatalog.definition(for: progress.trophyId)?.sortOrder ?? Int.max
    }
}

private struct TrophyMiniTile: View {
    let definition: TrophyDefinition

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: definition.iconName)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Theme.Colors.background)
                .frame(width: 38, height: 38)
                .background(Theme.Colors.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            Text(definition.title)
                .font(.system(size: 10, weight: .black))
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .padding(Theme.Spacing.xs)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Colors.divider, lineWidth: 1)
        )
    }
}

private struct ProfileThemeSelector: View {
    let selectedTheme: SpotterThemeOption
    let onSelect: (SpotterThemeOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("App Theme")
                .font(.system(size: 12, weight: .black))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textTertiary)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(SpotterThemeOption.allCases) { theme in
                    Button {
                        onSelect(theme)
                    } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [theme.accentColor, theme.secondaryAccentColor],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            selectedTheme == theme ? theme.accentColor : Theme.Colors.divider,
                                            lineWidth: selectedTheme == theme ? 3 : 1
                                        )
                                )

                            Text(theme.displayName)
                                .font(.system(size: 10, weight: .black))
                                .textCase(.uppercase)
                                .foregroundStyle(selectedTheme == theme ? theme.accentColor : Theme.Colors.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.displayName)
                    .accessibilityValue(selectedTheme == theme ? "Selected" : "")
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }
}

private struct TrainingPreferenceSection: View {
    let profile: UserProfile
    let accent: Color
    let onGoalChange: (FitnessGoal) -> Void
    let onCoachChange: (CoachPreference) -> Void
    let onSessionLengthChange: (PlanSessionLength) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Training Preferences")
                .font(.system(size: 12, weight: .black))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textTertiary)

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PreferenceChoiceGroup(
                    title: "Main Goal",
                    systemImage: "target",
                    options: FitnessGoal.allCases,
                    selected: profile.primaryGoal,
                    accent: accent,
                    label: \.displayName,
                    action: onGoalChange
                )

                PreferenceChoiceGroup(
                    title: "Coach Style",
                    systemImage: "person.wave.2.fill",
                    options: CoachPreference.allCases,
                    selected: profile.preferredCoach,
                    accent: accent,
                    label: \.displayName,
                    action: onCoachChange
                )

                PreferenceChoiceGroup(
                    title: "Daily Plan Length",
                    systemImage: "timer",
                    options: PlanSessionLength.dailyPreferenceCases,
                    selected: profile.preferredSessionLength,
                    accent: accent,
                    label: \.displayName,
                    action: onSessionLengthChange
                )
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }
}

private struct PreferenceChoiceGroup<Option: Identifiable & Equatable>: View {
    let title: String
    let systemImage: String
    let options: [Option]
    let selected: Option
    let accent: Color
    let label: (Option) -> String
    let action: (Option) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .black))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(options) { option in
                    Button {
                        HapticsEngine.shared.buttonTap()
                        action(option)
                    } label: {
                        Text(label(option))
                            .font(.system(size: 12, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(selected == option ? Theme.Colors.background : Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(selected == option ? accent : Theme.Colors.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selected == option ? "Selected" : "")
                }
            }
        }
    }
}

private struct ProfileStatsGrid: View {
    let stats: UserStats

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.sm),
        GridItem(.flexible(), spacing: Theme.Spacing.sm)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Stats")
                .font(.system(size: 12, weight: .black))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textTertiary)

            LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                ProfileStatCard(label: "Workouts", value: "\(stats.totalWorkouts)", detail: "\(stats.workoutsThisWeek) this week")
                ProfileStatCard(label: "Streak", value: "\(stats.currentStreak)d", detail: "Best \(stats.longestStreak)d")
                ProfileStatCard(label: "Reps", value: "\(stats.totalReps)", detail: "\(stats.totalExcellentFormReps) excellent")
                ProfileStatCard(label: "Hold", value: ProfileFormat.durationText(stats.totalHoldSeconds), detail: "Isometric time")
                ProfileStatCard(label: "Avg Form", value: ProfileFormat.formText(stats.averageFormScore), detail: "\(stats.totalGoodFormReps) good reps")
                ProfileStatCard(label: "Time", value: ProfileFormat.durationText(stats.totalDurationSeconds), detail: "Total duration")
            }
        }
    }
}

private struct ProfileStatCard: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(label)
                .font(.system(size: 10, weight: .black))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(detail)
                .caption()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

private struct WorkoutSnapshotCard: View {
    let snapshot: UserTrainingTrendSnapshot
    let calendarSnapshot: WorkoutCalendarSnapshot
    let heatmapSummary: [Date: DayIntensitySummary]
    let profile: UserProfile
    let accent: Color

    @State private var isShowingMonth = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ProfileSectionHeader(title: "Workout Snapshot")

            TrainingHeatmapView(
                summariesByDay: heatmapSummary,
                profile: profile,
                accent: accent
            )

            Button {
                withAnimation(Theme.Motion.snappy) {
                    isShowingMonth.toggle()
                }
            } label: {
                HStack {
                    Text("This Month")
                        .font(.system(size: 12, weight: .black))
                        .tracking(1.1)
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: isShowingMonth ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .black))
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isShowingMonth {
                CalendarSnapshotView(snapshot: calendarSnapshot, accent: accent)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                spacing: Theme.Spacing.sm
            ) {
                ProfileStatCard(
                    label: "Form Trend",
                    value: trendLabel(snapshot.overallFormTrend),
                    detail: snapshot.improvingExercise?.displayName ?? "More scored reps refine this"
                )
                ProfileStatCard(
                    label: "Volume",
                    value: trendLabel(snapshot.volumeTrend),
                    detail: snapshot.strongestExercise?.displayName ?? "Reps and holds combined"
                )
            }
        }
    }

    private func trendLabel(_ trend: TrainingTrendDirection) -> String {
        switch trend {
        case .unavailable:
            return "N/A"
        case .improving:
            return "Up"
        case .declining:
            return "Down"
        case .steady:
            return "Steady"
        case .increasing:
            return "Rising"
        case .decreasing:
            return "Lower"
        case .elevated:
            return "High"
        }
    }
}

private struct CoachInsightsCard: View {
    let profile: UserProfile
    let insights: [AIInsight]
    let onAppear: (AIInsight) -> Void
    let onEngagement: (AIInsight, InsightEngagementKind) -> Void
    let onOpenEvidence: (AIInsight) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ProfileSectionHeader(title: "Coach Insights")

            if insights.isEmpty {
                EmptyProfileCard(
                    systemImage: "brain.head.profile",
                    title: "No fresh insights yet",
                    subtitle: "Save more workouts to build evidence-backed coaching stories for \(profile.primaryGoal.displayName.lowercased())."
                )
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(insights.prefix(2))) { insight in
                        ProfileInsightRow(
                            insight: insight,
                            onAppear: {
                                onAppear(insight)
                            },
                            onEngagement: { kind in
                                onEngagement(insight, kind)
                            },
                            onOpenEvidence: {
                                onOpenEvidence(insight)
                            }
                        )
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
    }
}

private struct ProfileInsightRow: View {
    let insight: AIInsight
    let onAppear: () -> Void
    let onEngagement: (InsightEngagementKind) -> Void
    let onOpenEvidence: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(insight.headline)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.message)
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)

                InsightEvidenceButton(action: onOpenEvidence)
                InsightEngagementPrompt(onSelect: onEngagement)
            }

            Spacer(minLength: Theme.Spacing.xs)
        }
        .onAppear(perform: onAppear)
    }

    private var tint: Color {
        switch insight.severity {
        case .positive:
            return Theme.Colors.positive
        case .neutral:
            return Theme.Colors.accent
        case .caution, .important:
            return Theme.Colors.danger
        }
    }

    private var iconName: String {
        switch insight.type {
        case .consistency:
            return "flame.fill"
        case .growthCelebration, .dayOverDayTrend:
            return "chart.line.uptrend.xyaxis"
        case .formCorrection, .safety:
            return "exclamationmark.triangle.fill"
        case .recovery:
            return "timer"
        case .trophyProgress:
            return "trophy.fill"
        default:
            return "brain.head.profile"
        }
    }
}

private struct ProfileWeeklyRecapCard: View {
    let recap: WeeklyRecap
    let onAppear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ProfileSectionHeader(title: "Weekly Recap")

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(recap.headline)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(recap.narrative)
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 82), spacing: Theme.Spacing.sm)],
                    alignment: .leading,
                    spacing: Theme.Spacing.sm
                ) {
                    ForEach(recap.stats) { stat in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                            Text(stat.value)
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(stat.label)
                                .font(.system(size: 9, weight: .black))
                                .tracking(0.7)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                RecapLine(label: "Top moment", value: recap.topMoment)
                RecapLine(label: "Surprise", value: recap.biggestSurprise)
                RecapLine(label: "Next", value: recap.nextWeekFocus)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .id(recap.dedupeKey)
        .onAppear(perform: onAppear)
    }
}

private struct RecapLine: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
            Text(label)
                .font(.system(size: 10, weight: .black))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TrainingSignalRow: View {
    let signal: UserTrainingSignal

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(signal.title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detailText)
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.xs)
        }
    }

    private var detailText: String {
        var pieces = [signal.value]
        if let comparisonValue = signal.comparisonValue {
            pieces.append(comparisonValue)
        }
        pieces.append(signal.confidence.rawValue.capitalized)
        return pieces.joined(separator: " / ")
    }

    private var tint: Color {
        switch signal.confidence {
        case .high:
            return Theme.Colors.accent
        case .medium:
            return Theme.Colors.positive
        case .low:
            return Theme.Colors.textSecondary
        }
    }

    private var iconName: String {
        switch signal.type {
        case .consistency, .completion, .firstSession:
            return "flame.fill"
        case .formImprovement, .volumeIncrease, .exerciseMastery, .repeatExerciseProgress, .personalBaseline:
            return "chart.line.uptrend.xyaxis"
        case .formDropOff, .volumeDrop, .exerciseStruggle, .planFit:
            return "exclamationmark.triangle.fill"
        case .fatigue, .restBehavior:
            return "waveform.path.ecg"
        case .skippedExercise:
            return "forward.fill"
        case .repeatedCue:
            return "quote.bubble.fill"
        case .trophyProximity:
            return "trophy.fill"
        case .cameraFriction, .setupQuality:
            return "camera.fill"
        case .qualityCapacity, .targetFit, .progressionReadiness, .qualityPR, .repCleanlinessIntro:
            return "target"
        case .movementBalance:
            return "square.grid.3x3.fill"
        case .cueCluster:
            return "quote.bubble.fill"
        case .restResponse, .sessionFit:
            return "timer"
        case .exerciseReacquisition:
            return "arrow.clockwise"
        case .exercisePreference:
            return "slider.horizontal.3"
        }
    }
}

private struct WorkoutHistorySection: View {
    let summaries: [WorkoutSessionSummary]
    let onSelect: (UUID) -> Void
    let onDelete: (WorkoutSessionSummary) -> Void
    let onViewAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ProfileSectionHeader(title: "Workout History") {
                Button(action: onViewAll) {
                    Text("View All")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                .disabled(summaries.isEmpty)
                .opacity(summaries.isEmpty ? 0.45 : 1)
            }

            if summaries.isEmpty {
                EmptyProfileCard(
                    systemImage: "clock.arrow.circlepath",
                    title: "No saved workouts yet",
                    subtitle: "Planned workouts and free-analysis saves will appear here."
                )
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(summaries) { summary in
                        HStack(spacing: Theme.Spacing.sm) {
                            Button {
                                onSelect(summary.id)
                            } label: {
                                ProfileWorkoutHistoryRow(summary: summary)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)

                            Button(role: .destructive) {
                                onDelete(summary)
                            } label: {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(Theme.Colors.danger)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.Colors.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                            }
                            .accessibilityLabel("Delete \(summary.title)")
                        }
                    }
                }
            }
        }
    }
}

private struct WorkoutHistoryListView: View {
    let summaries: [WorkoutSessionSummary]
    let onSelect: (UUID) -> Void
    let onDelete: (WorkoutSessionSummary) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.Spacing.sm) {
                if summaries.isEmpty {
                    EmptyProfileCard(
                        systemImage: "clock.arrow.circlepath",
                        title: "No saved workouts yet",
                        subtitle: "Complete a session to populate history."
                    )
                } else {
                    ForEach(summaries) { summary in
                        HStack(spacing: Theme.Spacing.sm) {
                            Button {
                                onSelect(summary.id)
                            } label: {
                                ProfileWorkoutHistoryRow(summary: summary)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)

                            Button(role: .destructive) {
                                onDelete(summary)
                            } label: {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(Theme.Colors.danger)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.Colors.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                            }
                            .accessibilityLabel("Delete \(summary.title)")
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileWorkoutHistoryRow: View {
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
                    .minimumScaleFactor(0.75)
                Text(detailText)
                    .caption()
                    .lineLimit(2)
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
        var pieces = [summary.mode.displayName, ProfileFormat.durationText(summary.durationSeconds)]
        if summary.totalReps > 0 {
            pieces.append("\(summary.totalReps) reps")
        }
        if summary.totalHoldSeconds > 0 {
            pieces.append("\(ProfileFormat.durationText(summary.totalHoldSeconds)) hold")
        }
        if let score = summary.averageFormScore {
            pieces.append("\(Int(score.rounded()))% form")
        }
        return pieces.joined(separator: " / ")
    }
}

private struct SettingsDebugSection: View {
    let profile: UserProfile
    let calibrationStatus: CalibrationStatus
    let isSampleDataEnabled: Bool
    let debugStatusMessage: String?
    let onSampleDataToggle: (Bool) -> Void
    let onResetOnboarding: () -> Void
    let onResetCalibration: () -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ProfileInfoRow(label: "Age bracket", value: profile.ageBracket.displayName)
                ProfileInfoRow(label: "Fitness level", value: profile.fitnessLevel.displayName)
                ProfileInfoRow(label: "Equipment", value: profile.equipment.map(\.displayName).joined(separator: ", "))
                ProfileInfoRow(label: "Calibration", value: calibrationStatus.displayName)

                Toggle(
                    isOn: Binding(
                        get: { isSampleDataEnabled },
                        set: onSampleDataToggle
                    )
                ) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                        Text("Sample UI Data")
                            .font(.system(size: 12, weight: .black))
                            .tracking(1.0)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(isSampleDataEnabled ? "Loaded for local UI testing" : "Off")
                            .caption()
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.Colors.accent)

                HStack(spacing: Theme.Spacing.sm) {
                    Button("Reset onboarding", action: onResetOnboarding)
                        .buttonStyle(CompactDebugButtonStyle())
                    Button("Reset calibration", action: onResetCalibration)
                        .buttonStyle(CompactDebugButtonStyle())
                }

                if let debugStatusMessage {
                    Text(debugStatusMessage)
                        .caption()
                        .foregroundStyle(statusColor(for: debugStatusMessage))
                }

                Text("Debug resets only clear local onboarding or calibration state.")
                    .caption()
            }
            .padding(.top, Theme.Spacing.md)
        } label: {
            Text("Settings & Debug")
                .font(.system(size: 12, weight: .black))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .tint(Theme.Colors.textSecondary)
    }

    private func statusColor(for message: String) -> Color {
        message.localizedCaseInsensitiveContains("could not")
            ? Theme.Colors.danger
            : Theme.Colors.positive
    }
}

private struct ProfileInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .caption()
            Spacer(minLength: Theme.Spacing.sm)
            Text(value.isEmpty ? "None" : value)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct CompactDebugButtonStyle: ButtonStyle {
    let foregroundStyle: Color

    init(foregroundStyle: Color = Theme.Colors.danger) {
        self.foregroundStyle = foregroundStyle
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .black))
            .textCase(.uppercase)
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(Theme.Colors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private struct ProfileSectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(title: String) where Trailing == EmptyView {
        self.title = title
        self.trailing = EmptyView()
    }

    init(
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .black))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textTertiary)
            Spacer()
            trailing
        }
    }
}

private struct EmptyProfileCard: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 42, height: 42)
                .background(Theme.Colors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(title)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .caption()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

private struct MissingProfileHub: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Spacer()
            Text("Profile Needed")
                .header(size: 34)
            Text("Complete onboarding to build your local profile hub.")
                .bodyText()
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ProfileFormat {
    static func durationText(_ seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        guard safeSeconds >= 60 else { return "\(safeSeconds)s" }
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60
        let remainingSeconds = safeSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    static func formText(_ score: Double?) -> String {
        guard let score else { return "N/A" }
        return "\(Int(score.rounded()))%"
    }
}

private enum LocalUITestingSampleData {
    static let strengthWorkoutID = fixedUUID("00000000-0000-0000-0000-00000000A101")
    static let coreWorkoutID = fixedUUID("00000000-0000-0000-0000-00000000A102")
    static let pushupWorkoutID = fixedUUID("00000000-0000-0000-0000-00000000A103")
    static let lowerBodyWorkoutID = fixedUUID("00000000-0000-0000-0000-00000000A104")
    static let workoutIDs: Set<UUID> = [
        strengthWorkoutID,
        coreWorkoutID,
        pushupWorkoutID,
        lowerBodyWorkoutID
    ]
    static let insightDedupeKeys: Set<String> = [
        "debug.sample.consistency",
        "debug.sample.pushup-brace",
        "debug.sample.squat-quality"
    ]

    static func workoutHistory(
        now: Date,
        coach: CoachPersonality
    ) -> [WorkoutSessionSummary] {
        [
            makeRepSummary(
                id: strengthWorkoutID,
                planId: fixedUUID("00000000-0000-0000-0000-00000000B101"),
                title: "Quick Strength Check",
                exerciseType: .squat,
                dayOffset: 0,
                hour: 18,
                minute: 15,
                targetReps: 12,
                scores: [82, 84, 86, 88, 90, 91, 92, 89, 91, 93, 94, 92],
                cueMessage: "Keep knees tracking over toes",
                cueSeverity: .info,
                goal: "Build clean strength.",
                coach: coach,
                now: now
            ),
            makeHoldSummary(
                id: coreWorkoutID,
                planId: fixedUUID("00000000-0000-0000-0000-00000000B102"),
                title: "Core Hold Builder",
                exerciseType: .plank,
                dayOffset: -1,
                hour: 19,
                minute: 0,
                targetHoldSeconds: 90,
                achievedHoldSeconds: 105,
                form: 86,
                cueMessage: "Press the floor away and keep breathing",
                cueSeverity: .info,
                goal: "Build a steadier core base.",
                coach: coach,
                now: now
            ),
            makeRepSummary(
                id: pushupWorkoutID,
                planId: nil,
                title: "Push-Up Form Check",
                mode: .freeAnalysis,
                exerciseType: .pushup,
                dayOffset: -3,
                hour: 17,
                minute: 45,
                targetReps: 14,
                scores: [74, 76, 79, 81, 83, 84, 82, 80, 84, 86, 87, 88, 89, 87],
                cueMessage: "Keep your core braced",
                cueSeverity: .warning,
                goal: nil,
                coach: coach,
                now: now
            ),
            makeRepSummary(
                id: lowerBodyWorkoutID,
                planId: fixedUUID("00000000-0000-0000-0000-00000000B104"),
                title: "Lower Body Baseline",
                exerciseType: .lunge,
                dayOffset: -8,
                hour: 18,
                minute: 30,
                targetReps: 20,
                scores: [72, 74, 77, 78, 80, 82, 81, 83, 84, 82, 80, 79, 81, 83, 84],
                cueMessage: "Slow the descent before you drive up",
                cueSeverity: .warning,
                goal: "Find a safe lower-body baseline.",
                coach: coach,
                now: now
            )
        ]
    }

    static func isPresent(
        history: [WorkoutSessionSummary],
        insights: [AIInsight]
    ) -> Bool {
        history.contains { workoutIDs.contains($0.id) } ||
            insights.contains { !$0.isDeleted && isSampleInsight($0) }
    }

    static func isSampleInsight(_ insight: AIInsight) -> Bool {
        insightDedupeKeys.contains(insight.dedupeKey) ||
            insight.evidence.contains { evidence in
                guard let workoutId = evidence.workoutId else { return false }
                return workoutIDs.contains(workoutId)
            }
    }

    static func insights(
        for history: [WorkoutSessionSummary],
        profile: UserProfile,
        now: Date
    ) -> [AIInsight] {
        guard history.count >= 4 else { return [] }
        let strength = history[0]
        let core = history[1]
        let pushup = history[2]

        return [
            AIInsight(
                type: .consistency,
                headline: "Two straight training days are live",
                message: "The sample history gives the dashboard an active streak, recent workouts, and enough week-level volume to test the filled-in state.",
                shortMessage: "Sample streak and recent history are ready.",
                evidence: [
                    InsightEvidence(
                        metric: "sampleStreak",
                        value: "2 days",
                        comparison: "Workouts saved today and yesterday",
                        workoutId: strength.id,
                        exerciseType: strength.primaryExerciseType,
                        confidence: 0.94
                    ),
                    InsightEvidence(
                        metric: "sampleCoreHold",
                        value: "1:45 hold",
                        comparison: "Yesterday's core session",
                        workoutId: core.id,
                        exerciseType: core.primaryExerciseType,
                        confidence: 0.9
                    )
                ],
                recommendedAction: .protectStreakWithSmartStart,
                severity: .positive,
                emotionalIntent: .reinforceConsistency,
                userValueScore: 132,
                confidence: 0.92,
                surfaces: [.dashboard, .profile],
                relatedExerciseType: strength.primaryExerciseType,
                relatedGoal: profile.primaryGoal,
                createdAt: now.addingTimeInterval(-240),
                dedupeKey: "debug.sample.consistency"
            ),
            AIInsight(
                type: .formCorrection,
                headline: "Push-ups still want a braced midline",
                message: "The sample form-check includes a repeated core-bracing cue, so the evidence sheet and insight controls have a caution case to render.",
                shortMessage: "Core brace cue is ready for testing.",
                evidence: [
                    InsightEvidence(
                        metric: "sampleCue",
                        value: "Keep your core braced",
                        comparison: "Warning cue near the middle reps",
                        workoutId: pushup.id,
                        exerciseType: .pushup,
                        setIndex: 1,
                        repIndex: 7,
                        confidence: 0.88
                    )
                ],
                recommendedAction: .focusCue,
                severity: .caution,
                emotionalIntent: .buildConfidence,
                userValueScore: 126,
                confidence: 0.88,
                surfaces: [.profile, .dashboard],
                relatedExerciseType: .pushup,
                relatedGoal: profile.primaryGoal,
                createdAt: now.addingTimeInterval(-180),
                dedupeKey: "debug.sample.pushup-brace"
            ),
            AIInsight(
                type: .growthCelebration,
                headline: "Squat quality is ready for a tiny bump",
                message: "The latest sample squat set finishes above 90% form, which gives progression cards a positive, evidence-backed coaching story.",
                shortMessage: "Latest squat set finished clean.",
                evidence: [
                    InsightEvidence(
                        metric: "sampleForm",
                        value: "90% avg form",
                        comparison: "Last six scored reps averaged above 91%",
                        workoutId: strength.id,
                        exerciseType: .squat,
                        setIndex: 1,
                        confidence: 0.93
                    )
                ],
                recommendedAction: .increaseTarget,
                severity: .positive,
                emotionalIntent: .celebrateGrowth,
                userValueScore: 118,
                confidence: 0.9,
                surfaces: [.profile, .workoutPreview],
                relatedExerciseType: .squat,
                relatedGoal: profile.primaryGoal,
                createdAt: now.addingTimeInterval(-120),
                dedupeKey: "debug.sample.squat-quality"
            )
        ]
    }

    private static func makeRepSummary(
        id: UUID,
        planId: UUID?,
        title: String,
        mode: WorkoutSessionSummaryMode = .plannedWorkout,
        exerciseType: ExerciseType,
        dayOffset: Int,
        hour: Int,
        minute: Int,
        targetReps: Int,
        scores: [Int],
        cueMessage: String,
        cueSeverity: CoachCue.Severity,
        goal: String?,
        coach: CoachPersonality,
        now: Date
    ) -> WorkoutSessionSummary {
        let endedAt = sampleEndDate(dayOffset: dayOffset, hour: hour, minute: minute, now: now)
        let durationSeconds = max(420, scores.count * 18 + 180)
        let startedAt = endedAt.addingTimeInterval(TimeInterval(-durationSeconds))
        let cueScoreIndex = max(scores.count / 2 - 1, 0)
        let cueFormScore = scores.indices.contains(cueScoreIndex) ? scores[cueScoreIndex] : nil
        let cue = CueEvent(
            timestamp: startedAt.addingTimeInterval(TimeInterval(durationSeconds / 2)),
            exerciseType: exerciseType,
            cueMessage: cueMessage,
            severity: cueSeverity,
            setIndex: 1,
            repIndex: scores.isEmpty ? nil : max(min(scores.count, scores.count / 2), 1),
            secondsIntoSet: TimeInterval(durationSeconds / 2),
            formScoreAtEvent: cueFormScore
        )
        let repQualityEvents = scores.enumerated().map { index, score in
            RepQualityEvent(
                exerciseType: exerciseType,
                setIndex: 1,
                repIndex: index + 1,
                timestamp: startedAt.addingTimeInterval(TimeInterval((index + 1) * 16)),
                secondsIntoSet: TimeInterval((index + 1) * 16),
                formScore: score,
                formGrade: formGrade(for: score),
                phase: "rep",
                cueMessageNearRep: index == scores.count / 2 ? cueMessage : nil,
                cueSeverityNearRep: index == scores.count / 2 ? cueSeverity : nil,
                effortAtRep: min(0.88, 0.38 + Double(index) * 0.025)
            )
        }
        let qualitySummary = SetQualitySummary.build(
            repQualityEvents: repQualityEvents,
            cueEvents: [cue]
        )
        let exerciseSummary = ExerciseSetSummary(
            exerciseType: exerciseType,
            setIndex: 1,
            target: mode == .plannedWorkout ? .reps(targetReps) : nil,
            achievedReps: scores.count,
            achievedHoldSeconds: 0,
            averageFormScore: qualitySummary.averageFormScore,
            cueEvents: [cue],
            qualitySummary: qualitySummary,
            repQualityEvents: repQualityEvents,
            completionSource: mode == .plannedWorkout ? .targetMet : nil,
            completedAt: endedAt,
            durationSeconds: durationSeconds,
            peakEffort: repQualityEvents.compactMap(\.effortAtRep).max(),
            bestCue: cueSeverity == .info ? cueMessage : nil,
            worstCue: cueSeverity >= .warning ? cueMessage : nil
        )
        let completionPercent = mode == .plannedWorkout
            ? min(Double(scores.count) / Double(max(targetReps, 1)), 1)
            : nil

        return WorkoutSessionSummary(
            id: id,
            mode: mode,
            planId: planId,
            planTitle: mode == .plannedWorkout ? title : nil,
            title: title,
            goal: goal,
            coach: coach,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            totalReps: scores.count,
            totalHoldSeconds: 0,
            averageFormScore: qualitySummary.averageFormScore,
            completionPercent: completionPercent,
            exerciseSummaries: [exerciseSummary],
            topCue: cue,
            effortSummary: "Sample session captured steady work and a clean form signal.",
            workoutOutcome: mode == .freeAnalysis ? .freeAnalysisSaved : nil,
            structuredEffortSummary: StructuredEffortSummary.build(
                repQualityEvents: repQualityEvents,
                peakEffort: repQualityEvents.compactMap(\.effortAtRep).max()
            ),
            createdAt: endedAt
        )
    }

    private static func makeHoldSummary(
        id: UUID,
        planId: UUID?,
        title: String,
        exerciseType: ExerciseType,
        dayOffset: Int,
        hour: Int,
        minute: Int,
        targetHoldSeconds: Int,
        achievedHoldSeconds: Int,
        form: Double,
        cueMessage: String,
        cueSeverity: CoachCue.Severity,
        goal: String,
        coach: CoachPersonality,
        now: Date
    ) -> WorkoutSessionSummary {
        let endedAt = sampleEndDate(dayOffset: dayOffset, hour: hour, minute: minute, now: now)
        let durationSeconds = max(achievedHoldSeconds + 180, 360)
        let startedAt = endedAt.addingTimeInterval(TimeInterval(-durationSeconds))
        let cue = CueEvent(
            timestamp: startedAt.addingTimeInterval(TimeInterval(durationSeconds / 2)),
            exerciseType: exerciseType,
            cueMessage: cueMessage,
            severity: cueSeverity,
            setIndex: 1,
            secondsIntoSet: TimeInterval(achievedHoldSeconds / 2),
            formScoreAtEvent: Int(form.rounded())
        )
        let exerciseSummary = ExerciseSetSummary(
            exerciseType: exerciseType,
            setIndex: 1,
            target: .hold(seconds: targetHoldSeconds),
            achievedReps: 0,
            achievedHoldSeconds: achievedHoldSeconds,
            averageFormScore: form,
            cueEvents: [cue],
            completedAt: endedAt,
            durationSeconds: durationSeconds,
            peakEffort: 0.64,
            bestCue: cueMessage
        )

        return WorkoutSessionSummary(
            id: id,
            mode: .plannedWorkout,
            planId: planId,
            planTitle: title,
            title: title,
            goal: goal,
            coach: coach,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            totalReps: 0,
            totalHoldSeconds: achievedHoldSeconds,
            averageFormScore: form,
            completionPercent: min(Double(achievedHoldSeconds) / Double(max(targetHoldSeconds, 1)), 1),
            exerciseSummaries: [exerciseSummary],
            topCue: cue,
            effortSummary: "Sample hold work stayed controlled with a steady brace.",
            structuredEffortSummary: StructuredEffortSummary(
                averageEffort: 0.48,
                peakEffort: 0.64,
                trend: .steady,
                source: .faceBlendshapeProxy
            ),
            createdAt: endedAt
        )
    }

    private static func sampleEndDate(
        dayOffset: Int,
        hour: Int,
        minute: Int,
        now: Date
    ) -> Date {
        guard dayOffset != 0 else {
            return now.addingTimeInterval(-90 * 60)
        }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let baseDay = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: calendar.startOfDay(for: now)
        ) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDay) ?? baseDay
    }

    private static func formGrade(for score: Int) -> String {
        switch score {
        case 90...:
            return "A"
        case 80..<90:
            return "B"
        case 70..<80:
            return "C"
        default:
            return "D"
        }
    }

    private static func fixedUUID(_ value: String) -> UUID {
        UUID(uuidString: value) ?? UUID()
    }
}

#Preview {
    let stores = ProfilePreviewData.makeStores()
    ProfileView()
        .environmentObject(stores.onboardingStore)
        .environmentObject(stores.calibrationStore)
        .environmentObject(stores.historyStore)
        .environmentObject(stores.trophyStore)
        .environmentObject(stores.themeStore)
        .environmentObject(stores.insightStore)
}

@MainActor
private struct ProfilePreviewStores {
    let onboardingStore: OnboardingStore
    let calibrationStore: CalibrationStore
    let historyStore: WorkoutHistoryStore
    let trophyStore: TrophyStore
    let themeStore: ThemeStore
    let insightStore: InsightStore
}

@MainActor
private enum ProfilePreviewData {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        return calendar
    }()

    static let now = Date(timeIntervalSince1970: 1_778_100_300)

    static func makeStores() -> ProfilePreviewStores {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotterProfilePreview", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let onboardingStore = OnboardingStore(fileURL: baseURL.appendingPathComponent("UserProfile.json"))
        onboardingStore.draft.displayName = "Preview Athlete"
        onboardingStore.draft.genderIdentity = .preferNotToSay
        onboardingStore.draft.age = "30"
        onboardingStore.draft.height = "170"
        onboardingStore.draft.weight = "70"
        onboardingStore.draft.primaryGoal = .strength
        onboardingStore.draft.fitnessLevel = .beginner
        onboardingStore.draft.equipment = [.bodyweight]
        onboardingStore.draft.preferredCoach = .bennett
        onboardingStore.draft.selectedTheme = .hyper
        onboardingStore.draft.timezoneIdentifier = "Asia/Kolkata"

        let historyStore = WorkoutHistoryStore(
            fileURL: baseURL.appendingPathComponent("WorkoutHistory.json"),
            calendar: calendar
        )

        let calibrationStore = CalibrationStore(fileURL: baseURL.appendingPathComponent("Calibration.json"))
        let trophyStore = TrophyStore(
            fileURL: baseURL.appendingPathComponent("Trophies.json"),
            calendar: calendar
        )
        Task {
            await onboardingStore.completeOnboarding()
            for summary in sampleHistory {
                _ = await historyStore.addSummary(summary)
            }
            await trophyStore.updateAll(
                history: historyStore.summaries,
                calibrationStatus: calibrationStore.status,
                now: now
            )
        }

        return ProfilePreviewStores(
            onboardingStore: onboardingStore,
            calibrationStore: calibrationStore,
            historyStore: historyStore,
            trophyStore: trophyStore,
            themeStore: ThemeStore(),
            insightStore: InsightStore(fileURL: baseURL.appendingPathComponent("Insights.json"))
        )
    }

    static var sampleHistory: [WorkoutSessionSummary] {
        [
            makeSummary(dayOffset: -1, exerciseType: .squat, reps: 48, holdSeconds: 0, form: 89),
            makeSummary(dayOffset: -2, exerciseType: .plank, reps: 0, holdSeconds: 130, form: 86),
            makeSummary(dayOffset: -7, exerciseType: .pushup, reps: 42, holdSeconds: 0, form: 81),
            makeSummary(dayOffset: -15, exerciseType: .lunge, reps: 72, holdSeconds: 0, form: 88),
            makeSummary(dayOffset: -28, exerciseType: .gluteBridge, reps: 120, holdSeconds: 0, form: 92),
            makeSummary(dayOffset: -49, exerciseType: .wallSit, reps: 0, holdSeconds: 180, form: 84)
        ]
    }

    static func makeSummary(
        dayOffset: Int,
        exerciseType: ExerciseType,
        reps: Int,
        holdSeconds: Int,
        form: Double
    ) -> WorkoutSessionSummary {
        let endedAt = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        let target: WorkoutTarget = reps > 0 ? .reps(reps) : .hold(seconds: holdSeconds)
        let set = ExerciseSetSummary(
            exerciseType: exerciseType,
            setIndex: 0,
            target: target,
            achievedReps: reps,
            achievedHoldSeconds: holdSeconds,
            averageFormScore: form,
            completedAt: endedAt,
            durationSeconds: max(360, holdSeconds)
        )

        return WorkoutSessionSummary(
            mode: .plannedWorkout,
            title: "\(exerciseType.displayName) Preview",
            goal: "Build clean strength.",
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-1_200),
            endedAt: endedAt,
            durationSeconds: 1_200,
            totalReps: reps,
            totalHoldSeconds: holdSeconds,
            averageFormScore: form,
            completionPercent: 1,
            exerciseSummaries: [set],
            topCue: nil,
            effortSummary: "Preview effort.",
            createdAt: endedAt
        )
    }
}
