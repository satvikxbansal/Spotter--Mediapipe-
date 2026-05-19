import SwiftUI

nonisolated enum V2DashboardPlanActions {
    static func selectedQuickStartPlan(from content: DashboardContent) -> WorkoutPlanV2 {
        content.currentSmartStart.plan
    }

    static func shuffledContent(from content: DashboardContent) -> DashboardContent {
        var updated = content
        updated.advanceSmartStartPlan()
        return updated
    }
}

nonisolated enum V2DashboardInsightPresentation {
    static func shouldSurface(_ insight: AIInsight?) -> Bool {
        insight?.surfaces.contains(.dashboard) == true
    }
}

nonisolated enum V2BackendFallbackBannerModel {
    static func shouldShow(
        desired: BackendMode,
        active: BackendMode,
        message: String?,
        isDismissed: Bool
    ) -> Bool {
        desired != active &&
            !(message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
            !isDismissed
    }
}

struct V2DashboardView: View {
    private static let backendBannerDismissedKey = "spotter.v2.dashboard.backendFallbackBanner.dismissed"

    @EnvironmentObject private var accountContext: AccountContext
    @EnvironmentObject private var appDependencies: AppDependencies
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @EnvironmentObject private var trophyStore: TrophyStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var insightStore: InsightStore
    @EnvironmentObject private var backendStatusStore: BackendStatusStore
    @EnvironmentObject private var featureFlagService: RemoteFeatureFlagService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dashboardContent: DashboardContent?
    @State private var dashboardInsight: AIInsight?
    @State private var weeklyRecap: WeeklyRecap?
    @State private var previewPlan: WorkoutPlanV2?
    @State private var isShowingPlanPreview = false
    @State private var isShowingTrophies = false
    @State private var selectedInsightEvidence: AIInsight?
    @State private var isBackendBannerDismissed = UserDefaults.standard.bool(forKey: backendBannerDismissedKey)

    private let initialProfile: UserProfile?
    private let onOpenCameraTab: () -> Void
    private let refreshOnAppear: Bool
    private let usesNavigationStack: Bool

    private let contentFactory = DashboardContentFactory()

    init(
        initialProfile: UserProfile? = nil,
        onOpenCameraTab: @escaping () -> Void = {},
        initialDashboardContent: DashboardContent? = nil,
        initialDashboardInsight: AIInsight? = nil,
        initialWeeklyRecap: WeeklyRecap? = nil,
        refreshOnAppear: Bool = true,
        usesNavigationStack: Bool = true
    ) {
        self.initialProfile = initialProfile
        self.onOpenCameraTab = onOpenCameraTab
        self.refreshOnAppear = refreshOnAppear
        self.usesNavigationStack = usesNavigationStack
        _dashboardContent = State(initialValue: initialDashboardContent)
        _dashboardInsight = State(initialValue: initialDashboardInsight)
        _weeklyRecap = State(initialValue: initialWeeklyRecap)
    }

    var body: some View {
        Group {
            if usesNavigationStack {
                NavigationStack {
                    dashboardRoot
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(isPresented: $isShowingPlanPreview) {
                            if let previewPlan {
                                WorkoutPreviewView(
                                    plan: previewPlan,
                                    profile: activeProfile
                                )
                            }
                        }
                        .navigationDestination(isPresented: $isShowingTrophies) {
                            TrophiesView()
                        }
                }
            } else {
                dashboardRoot
            }
        }
        .sheet(item: $selectedInsightEvidence) { insight in
            InsightEvidenceSheetView(
                insight: insight,
                summaries: historyStore.summaries
            ) { kind in
                Task {
                    await recordInsightEngagement(insight, kind: kind)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard refreshOnAppear else { return }
            Task {
                await refreshDashboard()
            }
        }
        .onChange(of: onboardingStore.profile) {
            Task {
                await refreshDashboard()
            }
        }
        .onChange(of: historyStore.summaries) {
            Task {
                await refreshDashboard()
            }
        }
        .onChange(of: featureFlagService.flags) {
            Task {
                await refreshDashboard()
            }
        }
    }

    @ViewBuilder
    private var dashboardRoot: some View {
        Group {
            if let profile = activeProfile {
                dashboard(for: profile)
            } else {
                V2EmptyState(
                    theme: themeStore.selectedTheme,
                    title: "Complete onboarding",
                    bodyText: "Complete onboarding to see your dashboard.",
                    ctaTitle: "Start onboarding",
                    ctaAction: {
                        Task {
                            await onboardingStore.resetOnboarding()
                        }
                    }
                )
            }
        }
        .background(SpotterV2.Tokens.background)
    }

    private var activeProfile: UserProfile? {
        onboardingStore.profile ?? initialProfile
    }

    private func dashboard(for profile: UserProfile) -> some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xl) {
                    if shouldShowBackendBanner {
                        V2DashboardBackendBanner(
                            theme: themeStore.selectedTheme,
                            message: backendStatusStore.userFacingMessage ?? "",
                            onDismiss: dismissBackendBanner
                        )
                    }

                    if let dashboardContent {
                        V2DashboardGreetingCard(
                            theme: themeStore.selectedTheme,
                            profile: profile,
                            content: dashboardContent
                        )

                        V2DashboardSmartStartCard(
                            theme: themeStore.selectedTheme,
                            variant: dashboardContent.currentSmartStart,
                            totalVariants: dashboardContent.smartStartDeck.variants.count,
                            contentWidth: Swift.max(0, proxy.size.width - SpotterV2.Spacing.xl * 2),
                            onStart: {
                                openPreview(
                                    for: V2DashboardPlanActions.selectedQuickStartPlan(
                                        from: dashboardContent
                                    )
                                )
                            },
                            onShuffle: cycleSmartStartPlan
                        )
                        .frame(
                            width: Swift.max(0, proxy.size.width - SpotterV2.Spacing.xl * 2),
                            alignment: .leading
                        )

                        if let milestone = nextMilestone {
                            V2DashboardMilestoneCard(
                                theme: themeStore.selectedTheme,
                                milestone: milestone
                            )
                        }

                        V2DashboardMetricGrid(
                            theme: themeStore.selectedTheme,
                            metrics: metricTiles(for: profile)
                        )

                        V2DashboardDailyPlanCard(
                            theme: themeStore.selectedTheme,
                            summary: dashboardContent.dailyPlan,
                            onPreview: {
                                openPreview(for: dashboardContent.dailyPlan.plan)
                            }
                        )

                        if let weeklyRecap {
                            V2DashboardWeeklyRecapCard(
                                theme: themeStore.selectedTheme,
                                recap: weeklyRecap
                            )
                            .onAppear {
                                Task {
                                    await insightStore.recordPresentation(
                                        dedupeKey: weeklyRecap.dedupeKey,
                                        on: .dashboard
                                    )
                                }
                            }
                        }

                        if V2DashboardInsightPresentation.shouldSurface(dashboardInsight),
                           let dashboardInsight {
                            V2InsightCard(
                                theme: themeStore.selectedTheme,
                                eyebrow: "Coach Insight",
                                headline: dashboardInsight.headline,
                                bodyText: dashboardInsight.shortMessage,
                                onOpenEvidence: {
                                    Task {
                                        await recordInsightEngagement(dashboardInsight, kind: .opened)
                                    }
                                    selectedInsightEvidence = dashboardInsight
                                },
                                onHelpful: {
                                    Task {
                                        await recordInsightEngagement(dashboardInsight, kind: .helpful)
                                    }
                                },
                                onNotHelpful: {
                                    Task {
                                        await recordInsightEngagement(dashboardInsight, kind: .notHelpful)
                                    }
                                }
                            )
                            .onAppear {
                                Task {
                                    await insightStore.recordImpression(dashboardInsight, on: .dashboard)
                                    appDependencies.analytics.trackInsightImpression(
                                        type: dashboardInsight.type,
                                        surface: .dashboard
                                    )
                                }
                            }
                        }

                        V2DashboardTrophyTeaserCard(
                            theme: themeStore.selectedTheme,
                            progress: trophyStore.snapshot.nearestInProgress,
                            onOpen: {
                                HapticsEngine.shared.buttonTap()
                                isShowingTrophies = true
                            }
                        )

                        if let recentSummary = historyStore.fetchRecentSummaries(limit: 1).first {
                            V2DashboardRecentWorkoutCard(
                                theme: themeStore.selectedTheme,
                                summary: recentSummary
                            )
                        }

                        V2DashboardActionGrid(
                            theme: themeStore.selectedTheme,
                            onOpenFormCheck: {
                                HapticsEngine.shared.buttonTap()
                                onOpenCameraTab()
                            }
                        )
                    } else {
                        ProgressView()
                            .tint(SpotterV2.Tokens.primary(themeStore.selectedTheme))
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .frame(
                    width: Swift.max(0, proxy.size.width - SpotterV2.Spacing.xl * 2),
                    alignment: .leading
                )
                .padding(.horizontal, SpotterV2.Spacing.xl)
                .padding(.top, SpotterV2.Spacing.xl)
                .padding(.bottom, 132)
            }
            .refreshable {
                await refreshDashboard()
            }
        }
    }

    private var shouldShowBackendBanner: Bool {
        V2BackendFallbackBannerModel.shouldShow(
            desired: backendStatusStore.desiredBackendMode,
            active: backendStatusStore.activeBackendMode,
            message: backendStatusStore.userFacingMessage,
            isDismissed: isBackendBannerDismissed
        )
    }

    private var nextMilestone: V2DashboardMilestone? {
        guard let progress = trophyStore.snapshot.nearestInProgress,
              let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId) else {
            return nil
        }
        return V2DashboardMilestone(
            title: definition.title,
            detail: progress.progressLabel,
            iconName: definition.iconName
        )
    }

    private func dismissBackendBanner() {
        isBackendBannerDismissed = true
        UserDefaults.standard.set(true, forKey: Self.backendBannerDismissedKey)
    }

    private func metricTiles(for profile: UserProfile) -> [V2DashboardMetricTile] {
        let hasHistory = !historyStore.summaries.isEmpty
        let stats = StatsEngine().makeStats(
            history: historyStore.summaries,
            trophySnapshot: trophyStore.snapshot
        )
        let trendEngine = TrendEngine()
        let formComparison = trendEngine.threeWorkoutComparison(
            history: historyStore.summaries,
            metric: .formScore
        )
        let weeklyVolume = currentWeekVolume(for: profile)
        let emptyCaption = "Save your first workout to see this"

        return [
            V2DashboardMetricTile(
                id: "form-score",
                title: "Form Score",
                value: hasHistory ? stats.averageFormScore.map { "\(Int($0.rounded()))%" } ?? "—" : "—",
                caption: hasHistory ? "Average saved form" : emptyCaption,
                systemImage: "wand.and.stars",
                tintKind: .chart
            ),
            V2DashboardMetricTile(
                id: "consistency",
                title: "Consistency Streak",
                value: hasHistory && stats.currentStreak > 0 ? "\(stats.currentStreak)" : "—",
                caption: hasHistory ? "Active days" : emptyCaption,
                systemImage: "flame.fill",
                tintKind: .primary
            ),
            V2DashboardMetricTile(
                id: "form-trend",
                title: "Recent Form Trend",
                value: recentFormTrendValue(from: formComparison, hasHistory: hasHistory),
                caption: hasHistory ? recentFormTrendCaption(from: formComparison) : emptyCaption,
                systemImage: "chart.line.uptrend.xyaxis",
                tintKind: .chart
            ),
            V2DashboardMetricTile(
                id: "weekly-volume",
                title: "Weekly Volume",
                value: hasHistory && weeklyVolume > 0 ? "\(weeklyVolume)" : "—",
                caption: hasHistory ? "Reps plus hold work" : emptyCaption,
                systemImage: "gauge.with.dots.needle.67percent",
                tintKind: .primary
            )
        ]
    }

    private func currentWeekVolume(for profile: UserProfile) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let currentWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
        let dailySummaries = TrendEngine().dailyIntensitySummary(
            history: historyStore.summaries,
            profile: profile,
            days: 7,
            now: now
        )
        let volume = dailySummaries.values.reduce(0) { total, summary in
            let workoutWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: summary.date)
            guard workoutWeek.weekOfYear == currentWeek.weekOfYear,
                  workoutWeek.yearForWeekOfYear == currentWeek.yearForWeekOfYear else {
                return total
            }
            return total + summary.volumeUnits
        }
        return Int(volume.rounded())
    }

    private func recentFormTrendValue(
        from comparison: TrendComparisonSummary,
        hasHistory: Bool
    ) -> String {
        guard hasHistory, let delta = comparison.delta else { return "—" }
        let rounded = Int(delta.rounded())
        if rounded == 0 { return "0%" }
        return rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
    }

    private func recentFormTrendCaption(from comparison: TrendComparisonSummary) -> String {
        guard let delta = comparison.delta else {
            return "Need more saved workouts"
        }
        if delta > 2 {
            return "Improving lately"
        }
        if delta < -2 {
            return "Watch the drop"
        }
        return "Holding steady"
    }

    private func refreshDashboard() async {
        guard let profile = onboardingStore.profile else {
            dashboardContent = nil
            dashboardInsight = nil
            weeklyRecap = nil
            return
        }

        let now = Date()
        await trophyStore.updateAll(
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status,
            now: now
        )

        dashboardContent = contentFactory.makeContent(
            profile: profile,
            now: now,
            recentWorkoutHistory: historyStore.recentWorkoutHistoryItems(),
            currentStreakDayCount: historyStore.aggregateStats(now: now).currentStreak,
            trophySnapshot: trophyStore.snapshot,
            featureFlags: featureFlagService.flags
        )
        weeklyRecap = makeWeeklyRecap(profile: profile, now: now)
        dashboardInsight = await makeDashboardInsight(profile: profile, now: now)
    }

    private func makeDashboardInsight(
        profile: UserProfile,
        now: Date
    ) async -> AIInsight? {
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
        let generated = await InsightEngine(featureFlags: featureFlagService.flags).generateDashboardInsights(
            profile: profile,
            trendSnapshot: trendSnapshot,
            signals: signals,
            trophies: trophyStore.snapshot,
            engagementRecords: insightStore.engagementRecordsSnapshot(),
            now: now
        )
        return await insightStore.selectInsights(
            generated,
            for: .dashboard,
            profile: profile,
            limit: 1,
            now: now
        ).first
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
        return insightStore.canPresentOnce(dedupeKey: recap.dedupeKey, on: .dashboard) ? recap : nil
    }

    private func openPreview(for plan: WorkoutPlanV2) {
        HapticsEngine.shared.buttonTap()
        previewPlan = plan
        isShowingPlanPreview = true
        cacheActivePlanIfNeeded(plan)
    }

    private func cacheActivePlanIfNeeded(_ plan: WorkoutPlanV2) {
        guard appDependencies.backendMode == .firebase,
              featureFlagService.allowsBackendSync,
              let accountId = accountContext.currentAccountId else {
            return
        }

        Task {
            _ = try? await appDependencies.plans.saveActivePlan(
                plan,
                accountId: accountId,
                operationId: UUID()
            )
        }
    }

    private func cycleSmartStartPlan() {
        guard let content = dashboardContent else { return }
        HapticsEngine.shared.buttonTap()
        let updated = V2DashboardPlanActions.shuffledContent(from: content)
        withAnimation(reduceMotion ? nil : SpotterV2.Motion.snappy) {
            dashboardContent = updated
        }
    }

    private func recordInsightEngagement(_ insight: AIInsight, kind: InsightEngagementKind) async {
        await insightStore.recordEngagement(insight, kind: kind)
        switch kind {
        case .helpful:
            appDependencies.analytics.trackInsightHelpful(type: insight.type)
        case .notHelpful:
            appDependencies.analytics.trackInsightNotHelpful(type: insight.type)
        case .opened, .dismissed:
            break
        }
    }
}

nonisolated struct V2DashboardMetricTile: Identifiable, Equatable {
    enum TintKind: Equatable {
        case primary
        case chart
    }

    let id: String
    let title: String
    let value: String
    let caption: String
    let systemImage: String
    let tintKind: TintKind
}

nonisolated struct V2DashboardMilestone: Equatable {
    let title: String
    let detail: String
    let iconName: String
}

private struct V2DashboardGreetingCard: View {
    let theme: SpotterThemeOption
    let profile: UserProfile
    let content: DashboardContent

    var body: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
            HStack(alignment: .top, spacing: SpotterV2.Spacing.lg) {
                VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                    Text("SPOTTER AI")
                        .font(SpotterV2Typography.mono(size: 10, weight: .black))
                        .tracking(4.0)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.primary(theme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("Keep it up,\n\(profile.firstName).")
                        .font(SpotterV2Typography.display(size: 48))
                        .fontWidth(.compressed)
                        .italic()
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.foreground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.46)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                V2DashboardAvatar(profile: profile)
                    .fixedSize()
            }

            V2StatusPill(theme: theme, label: "Status: Training Active", pulsingDot: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.greeting), \(profile.firstName). Status training active.")
    }
}

private struct V2DashboardAvatar: View {
    let profile: UserProfile

    private var initials: String {
        let parts = (profile.displayName ?? profile.firstName)
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = String(parts).uppercased()
        return value.isEmpty ? "" : value
    }

    var body: some View {
        ZStack {
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(SpotterV2.Tokens.foreground)
            } else {
                Text(initials)
                    .font(SpotterV2Typography.heading(size: 14))
                    .foregroundStyle(SpotterV2.Tokens.foreground)
            }
        }
        .frame(width: 56, height: 56)
        .background(SpotterV2.Tokens.muted)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
        )
        .background(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: SpotterV2.Radius.lg)
                .fill(SpotterV2.Tokens.foreground.opacity(0.1))
                .offset(x: 4, y: 4)
        }
        .rotationEffect(.degrees(3))
        .accessibilityLabel("Profile avatar")
    }
}

private struct V2DashboardMilestoneCard: View {
    let theme: SpotterThemeOption
    let milestone: V2DashboardMilestone

    var body: some View {
        V2Card(
            theme: theme,
            radius: SpotterV2.Radius.xl,
            padding: SpotterV2.Spacing.md,
            borderColor: SpotterV2.Tokens.primary(theme).opacity(0.32),
            hardShadowColor: nil
        ) {
            HStack(spacing: SpotterV2.Spacing.md) {
                Image(systemName: milestone.iconName)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
                    .frame(width: 52, height: 52)
                    .background(SpotterV2.Tokens.primary(theme).opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                            .stroke(SpotterV2.Tokens.primary(theme).opacity(0.28), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                    Text("Next Milestone")
                        .font(SpotterV2Typography.caption())
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.primary(theme).opacity(0.82))
                    Text("\(milestone.title): \(milestone.detail)")
                        .font(SpotterV2Typography.heading(size: 18))
                        .fontWidth(.compressed)
                        .italic()
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.primary(theme))
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                }

                Spacer(minLength: SpotterV2.Spacing.xs)

                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(SpotterV2.Tokens.primary(theme))
            }
        }
        .background(SpotterV2.Tokens.primary(theme).opacity(0.05))
        .accessibilityElement(children: .combine)
    }
}

private struct V2DashboardMetricGrid: View {
    let theme: SpotterThemeOption
    let metrics: [V2DashboardMetricTile]

    private let columns = [
        GridItem(.flexible(), spacing: SpotterV2.Spacing.md),
        GridItem(.flexible(), spacing: SpotterV2.Spacing.md)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: SpotterV2.Spacing.md) {
            ForEach(metrics) { metric in
                V2DashboardMetricTileView(theme: theme, metric: metric)
            }
        }
    }
}

private struct V2DashboardMetricTileView: View {
    let theme: SpotterThemeOption
    let metric: V2DashboardMetricTile

    private var tint: Color {
        metric.tintKind == .chart ? SpotterV2.Tokens.chart1 : SpotterV2.Tokens.primary(theme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.sm) {
            Image(systemName: metric.systemImage)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                        .stroke(tint.opacity(0.22), lineWidth: SpotterV2.BorderWidth.standard)
                )

            Spacer(minLength: SpotterV2.Spacing.xs)

            Text(metric.title)
                .font(SpotterV2Typography.caption())
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(metric.value)
                .font(SpotterV2Typography.display(size: 44))
                .fontWidth(.compressed)
                .italic()
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.45)

            Text(metric.caption)
                .font(SpotterV2Typography.caption(weight: .bold))
                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
        }
        .padding(SpotterV2.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
        .aspectRatio(1, contentMode: .fit)
        .background(SpotterV2.Tokens.card)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl)
                .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.bold)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title), \(metric.value), \(metric.caption)")
    }
}

private struct V2DashboardSmartStartCard: View {
    let theme: SpotterThemeOption
    let variant: QuickStartPlanVariant
    let totalVariants: Int
    let contentWidth: CGFloat?
    let onStart: () -> Void
    let onShuffle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var innerContentWidth: CGFloat? {
        contentWidth.map { Swift.max(0, $0 - SpotterV2.Spacing.xl * 2) }
    }

    private var focusPillTitle: String {
        if variant.subtitle.localizedCaseInsensitiveContains("Challenge Lite") {
            return "Challenge Lite"
        }
        let parts = variant.subtitle
            .components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.last ?? variant.subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Image("SpotterWelcomeHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: contentWidth)
                    .frame(height: 288)
                    .opacity(0.42)
                    .grayscale(0.72)
                    .clipped()
                    .accessibilityHidden(true)

                LinearGradient(
                    colors: [
                        SpotterV2.Tokens.background.opacity(0.08),
                        SpotterV2.Tokens.background.opacity(0.54),
                        SpotterV2.Tokens.background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.lg) {
                    HStack(alignment: .top) {
                        Text("Recommended")
                            .font(SpotterV2Typography.caption())
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .italic()
                            .foregroundStyle(.black)
                            .padding(.horizontal, SpotterV2.Spacing.md)
                            .padding(.vertical, SpotterV2.Spacing.xs)
                            .background(SpotterV2.Tokens.primary(theme))
                            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xs))

                        Spacer()

                        if totalVariants > 1 {
                            Button(action: onShuffle) {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundStyle(SpotterV2.Tokens.foreground)
                                    .frame(width: 44, height: 44)
                                    .background(SpotterV2.Tokens.background.opacity(0.74))
                                    .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                                            .stroke(SpotterV2.Tokens.border.opacity(0.22), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(V2DashboardPressableButtonStyle(reduceMotion: reduceMotion))
                            .accessibilityLabel("Shuffle Quick Start")
                            .accessibilityHint("Show another recommended Quick Start plan.")
                        }
                    }

                    HStack(alignment: .bottom, spacing: SpotterV2.Spacing.sm) {
                        VStack(alignment: .leading, spacing: SpotterV2.Spacing.sm) {
                            Text(variant.title)
                                .font(SpotterV2Typography.display(size: 44))
                                .fontWidth(.compressed)
                                .italic()
                                .textCase(.uppercase)
                                .foregroundStyle(SpotterV2.Tokens.foreground)
                                .lineLimit(2)
                                .minimumScaleFactor(0.5)

                            Text(variant.reason)
                                .font(SpotterV2Typography.body(size: 14, weight: .bold))
                                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: SpotterV2.Spacing.sm)

                        VStack(alignment: .trailing, spacing: SpotterV2.Spacing.xxxs) {
                            Text("\(variant.plan.estimatedMinutes)")
                                .font(SpotterV2Typography.display(size: 40))
                                .fontWidth(.compressed)
                                .italic()
                                .foregroundStyle(SpotterV2.Tokens.foreground)
                                .monospacedDigit()
                            Text("Minutes")
                                .font(SpotterV2Typography.caption())
                                .tracking(1.2)
                                .textCase(.uppercase)
                                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    HStack(spacing: SpotterV2.Spacing.sm) {
                        V2DashboardHeroPill(
                            title: focusPillTitle,
                            systemImage: "dumbbell.fill",
                            tint: SpotterV2.Tokens.foreground
                        )
                        V2DashboardHeroPill(
                            title: variant.intensityLabel.displayName,
                            systemImage: "bolt.fill",
                            tint: SpotterV2.Tokens.primary(theme)
                        )
                    }

                    V2DashboardHeroCTAButton(
                        title: "Start Training",
                        theme: theme,
                        action: onStart
                    )
                }
                .frame(width: innerContentWidth, alignment: .leading)
                .padding(SpotterV2.Spacing.xl)
            }
        }
        .id(variant.id)
        .frame(width: contentWidth, alignment: .leading)
        .background(SpotterV2.Tokens.card)
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl)
                .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
        )
        .background(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: SpotterV2.Radius.xxl)
                .fill(SpotterV2.Tokens.primary(theme).opacity(0.15))
                .offset(x: 8, y: 8)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityElement(children: .contain)
    }
}

private struct V2DashboardHeroCTAButton: View {
    let title: String
    let theme: SpotterThemeOption
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpotterV2.Spacing.md) {
                Text(title)
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(
            V2DashboardHeroCTAButtonStyle(
                theme: theme,
                reduceMotion: reduceMotion
            )
        )
        .accessibilityLabel(title)
    }
}

private struct V2DashboardHeroCTAButtonStyle: ButtonStyle {
    let theme: SpotterThemeOption
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SpotterV2Typography.heading(size: 20, weight: .black))
            .fontWidth(.compressed)
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(SpotterV2.Tokens.primary(theme))
            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xl))
            .background(alignment: .topLeading) {
                if !(configuration.isPressed && !reduceMotion) {
                    RoundedRectangle(cornerRadius: SpotterV2.Radius.xl)
                        .fill(.black.opacity(0.2))
                        .offset(x: 6, y: 6)
                }
            }
            .offset(
                x: configuration.isPressed && !reduceMotion ? 3 : 0,
                y: configuration.isPressed && !reduceMotion ? 3 : 0
            )
            .animation(reduceMotion ? nil : SpotterV2.Motion.press, value: configuration.isPressed)
    }
}

private struct V2DashboardHeroPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: SpotterV2.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(tint)
            Text(title)
                .font(SpotterV2Typography.caption())
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, SpotterV2.Spacing.sm)
        .padding(.vertical, SpotterV2.Spacing.xs)
        .background(SpotterV2.Tokens.foreground.opacity(0.05))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(SpotterV2.Tokens.border.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct V2DashboardPressableButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(
                x: configuration.isPressed && !reduceMotion ? 2 : 0,
                y: configuration.isPressed && !reduceMotion ? 2 : 0
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : SpotterV2.Motion.press, value: configuration.isPressed)
    }
}

private struct V2DashboardDailyPlanCard: View {
    let theme: SpotterThemeOption
    let summary: DashboardPlanSummary
    let onPreview: () -> Void

    var body: some View {
        V2Card(theme: theme, radius: SpotterV2.Radius.lg) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                V2SectionHeader(title: "Daily Plan", trailingTitle: summary.durationText, trailingSystemImage: "clock.fill")

                Text(summary.title)
                    .font(SpotterV2Typography.heading(size: 22))
                    .fontWidth(.compressed)
                    .textCase(.uppercase)
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text("\(summary.exerciseCount) exercises. \(summary.reason)")
                    .font(SpotterV2Typography.body(size: 13, weight: .semibold))
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .lineLimit(3)

                V2SecondaryButton(
                    title: "Preview Plan",
                    systemImage: "arrow.right",
                    theme: theme,
                    action: onPreview
                )
            }
        }
    }
}

private struct V2DashboardWeeklyRecapCard: View {
    let theme: SpotterThemeOption
    let recap: WeeklyRecap

    var body: some View {
        V2Card(theme: theme, borderColor: SpotterV2.Tokens.chart1.opacity(0.65)) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                V2SectionHeader(title: "Weekly Recap", trailingTitle: "Code-only", trailingSystemImage: "calendar.badge.clock")

                Text(recap.headline)
                    .font(SpotterV2Typography.heading(size: 18))
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                Text(recap.nextWeekFocus)
                    .font(SpotterV2Typography.body(size: 13, weight: .semibold))
                    .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SpotterV2.Spacing.sm) {
                    ForEach(recap.stats.prefix(3)) { stat in
                        VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxxs) {
                            Text(stat.value)
                                .font(SpotterV2Typography.mono(size: 18))
                                .foregroundStyle(SpotterV2.Tokens.chart1)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(stat.label)
                                .font(SpotterV2Typography.caption(weight: .bold))
                                .tracking(0.8)
                                .textCase(.uppercase)
                                .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                                .lineLimit(2)
                                .minimumScaleFactor(0.65)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct V2DashboardTrophyTeaserCard: View {
    let theme: SpotterThemeOption
    let progress: TrophyProgress?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            V2Card(theme: theme, radius: SpotterV2.Radius.lg) {
                HStack(spacing: SpotterV2.Spacing.md) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 52, height: 52)
                        .background(SpotterV2.Tokens.primary(theme))
                        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))

                    VStack(alignment: .leading, spacing: SpotterV2.Spacing.xxs) {
                        Text("Trophy Teaser")
                            .font(SpotterV2Typography.caption())
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.primary(theme))
                        Text(title)
                            .font(SpotterV2Typography.heading(size: 18))
                            .textCase(.uppercase)
                            .foregroundStyle(SpotterV2.Tokens.foreground)
                        Text(subtitle)
                            .font(SpotterV2Typography.body(size: 13, weight: .semibold))
                            .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                            .lineLimit(2)
                    }

                    Spacer(minLength: SpotterV2.Spacing.xs)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open trophies. \(title). \(subtitle)")
    }

    private var title: String {
        guard let progress,
              let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId) else {
            return "Hall of Gains"
        }
        return definition.title
    }

    private var subtitle: String {
        guard let progress else {
            return "Save a workout to start lighting up trophies."
        }
        return progress.progressLabel
    }
}

private struct V2DashboardRecentWorkoutCard: View {
    let theme: SpotterThemeOption
    let summary: WorkoutSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: SpotterV2.Spacing.sm) {
            V2SectionHeader(title: "Recent Workout")
            V2WorkoutHistoryRow(
                theme: theme,
                date: summary.authoritativeEndedAt,
                title: summary.title,
                mode: summary.mode.displayName,
                metrics: metrics
            )
        }
    }

    private var metrics: [String] {
        var values: [String] = []
        if summary.durationSeconds > 0 {
            values.append("\(summary.durationSeconds / 60)m")
        }
        if summary.totalReps > 0 {
            values.append("\(summary.totalReps) reps")
        }
        if summary.totalHoldSeconds > 0 {
            values.append("\(summary.totalHoldSeconds)s hold")
        }
        if let form = summary.averageFormScore {
            values.append("\(Int(form.rounded()))% form")
        }
        return values.isEmpty ? ["Saved"] : values
    }
}

private struct V2DashboardActionGrid: View {
    let theme: SpotterThemeOption
    let onOpenFormCheck: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: SpotterV2.Spacing.md),
        GridItem(.flexible(), spacing: SpotterV2.Spacing.md)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: SpotterV2.Spacing.md) {
            V2DashboardActionCard(
                theme: theme,
                title: "Form\nCheck",
                subtitle: "Exercise-specific",
                systemImage: "viewfinder",
                isEnabled: true,
                ribbon: nil,
                action: onOpenFormCheck
            )

            V2DashboardActionCard(
                theme: theme,
                title: "Running\nAnalysis",
                subtitle: "Gait and form AI",
                systemImage: "figure.run",
                isEnabled: false,
                ribbon: "Coming Soon",
                action: {}
            )
        }
    }
}

private struct V2DashboardActionCard: View {
    let theme: SpotterThemeOption
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    let ribbon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SpotterV2.Spacing.md) {
                HStack(alignment: .top) {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(isEnabled ? SpotterV2.Tokens.foreground : SpotterV2.Tokens.mutedForeground)
                        .frame(width: 52, height: 52)
                        .background(SpotterV2.Tokens.muted)
                        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: SpotterV2.Radius.md)
                                .stroke(SpotterV2.Tokens.border, lineWidth: SpotterV2.BorderWidth.standard)
                        )

                    Spacer()
                }

                Spacer(minLength: SpotterV2.Spacing.lg)

                VStack(alignment: .leading, spacing: SpotterV2.Spacing.xs) {
                    Text(title)
                        .font(SpotterV2Typography.heading(size: 20))
                        .fontWidth(.compressed)
                        .textCase(.uppercase)
                        .foregroundStyle(isEnabled ? SpotterV2.Tokens.foreground : SpotterV2.Tokens.mutedForeground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                    Text(subtitle)
                        .font(SpotterV2Typography.caption())
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(SpotterV2.Tokens.mutedForeground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(SpotterV2.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
            .aspectRatio(1, contentMode: .fit)
            .background(SpotterV2.Tokens.card)
            .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: SpotterV2.Radius.xl)
                    .stroke(
                        isEnabled ? SpotterV2.Tokens.border : SpotterV2.Tokens.border.opacity(0.5),
                        lineWidth: SpotterV2.BorderWidth.standard
                    )
            )
            .overlay(alignment: .topTrailing) {
                if let ribbon {
                    Text(ribbon)
                        .font(SpotterV2Typography.caption())
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(.black)
                        .padding(.horizontal, SpotterV2.Spacing.md)
                        .padding(.vertical, SpotterV2.Spacing.xxs)
                        .background(SpotterV2.Tokens.primary(theme))
                        .rotationEffect(.degrees(38))
                        .offset(x: 26, y: 18)
                }
            }
            .clipped()
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(isEnabled ? title.replacingOccurrences(of: "\n", with: " ") : "\(title.replacingOccurrences(of: "\n", with: " ")) coming soon")
    }
}

private struct V2DashboardBackendBanner: View {
    let theme: SpotterThemeOption
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SpotterV2.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(SpotterV2.Tokens.destructive)

            Text(message)
                .font(SpotterV2Typography.body(size: 12, weight: .semibold))
                .foregroundStyle(SpotterV2.Tokens.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: SpotterV2.Spacing.xs)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(SpotterV2.Tokens.foreground)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss backend status")
        }
        .padding(.horizontal, SpotterV2.Spacing.md)
        .padding(.vertical, SpotterV2.Spacing.sm)
        .background(SpotterV2.Tokens.destructive.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: SpotterV2.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: SpotterV2.Radius.sm)
                .stroke(SpotterV2.Tokens.destructive.opacity(0.55), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
private struct V2DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(SpotterThemeOption.allCases) { theme in
                V2DashboardPreviewHost(theme: theme, richHistory: false)
                    .previewDisplayName("\(theme.displayName) Dashboard Empty SE")
                    .previewDevice("iPhone SE (3rd generation)")
                V2DashboardPreviewHost(theme: theme, richHistory: true)
                    .previewDisplayName("\(theme.displayName) Dashboard Rich Pro Max")
                    .previewDevice("iPhone 17 Pro Max")
            }
        }
    }
}

private struct V2DashboardPreviewHost: View {
    let theme: SpotterThemeOption
    let richHistory: Bool

    @StateObject private var accountContext = AccountContext()
    @StateObject private var appDependencies = AppDependencies.local()
    @StateObject private var onboardingStore: OnboardingStore
    @StateObject private var calibrationStore = CalibrationStore()
    @StateObject private var historyStore: WorkoutHistoryStore
    @StateObject private var trophyStore = TrophyStore()
    @StateObject private var themeStore: ThemeStore
    @StateObject private var insightStore = InsightStore()
    @StateObject private var backendStatusStore = BackendStatusStore()
    @StateObject private var featureFlagService = RemoteFeatureFlagService.local(defaults: FeatureFlags(designSystemV2Enabled: true))

    init(theme: SpotterThemeOption, richHistory: Bool) {
        self.theme = theme
        self.richHistory = richHistory
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("V2DashboardPreview-\(UUID().uuidString)", isDirectory: true)
        _onboardingStore = StateObject(
            wrappedValue: OnboardingStore(fileURL: directory.appendingPathComponent("UserProfile.json"))
        )
        _historyStore = StateObject(
            wrappedValue: WorkoutHistoryStore(fileURL: directory.appendingPathComponent("WorkoutHistory.json"))
        )
        _themeStore = StateObject(
            wrappedValue: ThemeStore(fileURL: directory.appendingPathComponent("Theme.json"), defaultTheme: theme)
        )
    }

    var body: some View {
        V2DashboardView()
            .environmentObject(accountContext)
            .environmentObject(appDependencies)
            .environmentObject(onboardingStore)
            .environmentObject(calibrationStore)
            .environmentObject(historyStore)
            .environmentObject(trophyStore)
            .environmentObject(themeStore)
            .environmentObject(insightStore)
            .environmentObject(backendStatusStore)
            .environmentObject(featureFlagService)
            .task {
                if onboardingStore.profile == nil {
                    _ = await onboardingStore.saveProfile(Self.profile(theme: theme))
                }
                if richHistory, historyStore.summaries.isEmpty {
                    _ = await historyStore.addSummary(Self.summary(daysAgo: 0, reps: 36, form: 94))
                    _ = await historyStore.addSummary(Self.summary(daysAgo: 1, reps: 28, form: 89))
                    _ = await historyStore.addSummary(Self.summary(daysAgo: 3, reps: 22, form: 84))
                }
            }
    }

    private static func profile(theme: SpotterThemeOption) -> UserProfile {
        let now = Date()
        return UserProfile(
            id: UUID(),
            displayName: "Satvik Bansal",
            genderIdentity: .male,
            age: 30,
            height: 178,
            heightUnit: .metric,
            weight: 84,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .intermediate,
            equipment: [.bodyweight, .dumbbells, .mat, .wall],
            preferredCoach: .bennett,
            selectedTheme: theme,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func summary(daysAgo: Int, reps: Int, form: Double) -> WorkoutSessionSummary {
        let endedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return WorkoutSessionSummary(
            mode: .plannedWorkout,
            title: "Full Body Engine",
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-1_800),
            endedAt: endedAt,
            durationSeconds: 1_800,
            totalReps: reps,
            totalHoldSeconds: 45,
            averageFormScore: form,
            completionPercent: 1,
            exerciseSummaries: [
                ExerciseSetSummary(
                    exerciseType: .squat,
                    achievedReps: reps,
                    achievedHoldSeconds: 0,
                    averageFormScore: form
                )
            ],
            topCue: nil,
            effortSummary: "Preview session.",
            totalGoodFormReps: reps,
            totalExcellentFormReps: Int(Double(reps) * 0.5)
        )
    }
}
#endif
