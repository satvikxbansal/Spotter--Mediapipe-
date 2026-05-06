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
                    onSelect: openSummary
                )
            }
            .sheet(item: $selectedSummary) { summary in
                WorkoutDetailSheetView(summary: summary)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear(perform: refreshProfileData)
            .onChange(of: historyStore.summaries) {
                refreshProfileData()
            }
            .onChange(of: calibrationStore.status) {
                refreshTrophies()
            }
            .onChange(of: onboardingStore.profile) {
                themeStore.sync(with: onboardingStore.profile)
                refreshProfileData()
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
                    onGoalChange: { _ = onboardingStore.updatePrimaryGoal($0) },
                    onCoachChange: { _ = onboardingStore.updatePreferredCoach($0) },
                    onSessionLengthChange: { _ = onboardingStore.updatePreferredSessionLength($0) }
                )

                ProfileStatsGrid(stats: stats)

                WorkoutSnapshotCard(
                    snapshot: trendSnapshot,
                    calendarSnapshot: calendarSnapshot,
                    accent: themeStore.selectedTheme.accentColor
                )

                CoachInsightsCard(profile: profile, insights: profileInsights)

                WorkoutHistorySection(
                    summaries: historyStore.fetchRecentSummaries(limit: 5),
                    onSelect: openSummary,
                    onViewAll: {
                        HapticsEngine.shared.buttonTap()
                        isShowingAllHistory = true
                    }
                )

                SettingsDebugSection(
                    profile: profile,
                    calibrationStatus: calibrationStore.status,
                    onResetOnboarding: onboardingStore.resetOnboarding,
                    onResetCalibration: calibrationStore.resetForDebug
                )
            }
            .padding(Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
    }

    private func refreshProfileData() {
        themeStore.sync(with: onboardingStore.profile)
        guard let profile = onboardingStore.profile else {
            profileInsights = []
            return
        }
        let now = Date()
        trophyStore.updateAll(
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status,
            now: now
        )
        refreshProfileInsights(profile: profile, now: now)
    }

    private func refreshTrophies() {
        let now = Date()
        trophyStore.updateAll(
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status,
            now: now
        )
        if let profile = onboardingStore.profile {
            refreshProfileInsights(profile: profile, now: now)
        }
    }

    private func refreshProfileInsights(
        profile: UserProfile,
        now: Date
    ) {
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
            trophies: trophyStore.snapshot
        )
        let generated = InsightEngine().generateProfileInsights(
            profile: profile,
            trendSnapshot: trendSnapshot,
            signals: signals,
            trophies: trophyStore.snapshot
        )
        profileInsights = insightStore.selectInsights(
            generated,
            for: .profile,
            limit: 2,
            now: now
        )
    }

    private func updateTheme(_ theme: SpotterThemeOption) {
        HapticsEngine.shared.buttonTap()
        guard onboardingStore.updateSelectedTheme(theme) else { return }
        themeStore.updateSelectedTheme(theme)
    }

    private func openSummary(_ summaryID: UUID) {
        guard let summary = ProfileHistorySelection.detailSummary(
            for: summaryID,
            in: historyStore.summaries
        ) else { return }
        HapticsEngine.shared.buttonTap()
        selectedSummary = summary
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
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ProfileSectionHeader(title: "Workout Snapshot")

            CalendarSnapshotView(snapshot: calendarSnapshot, accent: accent)

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
                        ProfileInsightRow(insight: insight)
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
            }

            Spacer(minLength: Theme.Spacing.xs)
        }
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
        case .consistency, .completion:
            return "flame.fill"
        case .formImprovement, .volumeIncrease, .exerciseMastery:
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
        case .cameraFriction:
            return "camera.fill"
        case .qualityCapacity, .targetFit, .progressionReadiness, .qualityPR:
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
                        Button {
                            onSelect(summary.id)
                        } label: {
                            ProfileWorkoutHistoryRow(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct WorkoutHistoryListView: View {
    let summaries: [WorkoutSessionSummary]
    let onSelect: (UUID) -> Void

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
                        Button {
                            onSelect(summary.id)
                        } label: {
                            ProfileWorkoutHistoryRow(summary: summary)
                        }
                        .buttonStyle(.plain)
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
    let onResetOnboarding: () -> Void
    let onResetCalibration: () -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ProfileInfoRow(label: "Age bracket", value: profile.ageBracket.displayName)
                ProfileInfoRow(label: "Fitness level", value: profile.fitnessLevel.displayName)
                ProfileInfoRow(label: "Equipment", value: profile.equipment.map(\.displayName).joined(separator: ", "))
                ProfileInfoRow(label: "Calibration", value: calibrationStatus.displayName)

                HStack(spacing: Theme.Spacing.sm) {
                    Button("Reset onboarding", action: onResetOnboarding)
                        .buttonStyle(CompactDebugButtonStyle())
                    Button("Reset calibration", action: onResetCalibration)
                        .buttonStyle(CompactDebugButtonStyle())
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .black))
            .textCase(.uppercase)
            .foregroundStyle(Theme.Colors.danger)
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

#Preview {
    ProfileView()
        .environmentObject(OnboardingStore())
        .environmentObject(CalibrationStore())
        .environmentObject(WorkoutHistoryStore())
        .environmentObject(TrophyStore())
        .environmentObject(ThemeStore())
        .environmentObject(InsightStore())
}
