import Foundation

nonisolated struct InsightEngine {
    private let candidateBuilder: InsightCandidateBuilder
    private let ranker: InsightRanker
    private let narrativeBuilder: InsightNarrativeBuilder
    private let insightRewriter: any InsightRewriter
    private let rewriteValidator: RewriteValidator

    init(
        candidateBuilder: InsightCandidateBuilder = InsightCandidateBuilder(),
        ranker: InsightRanker = InsightRanker(),
        narrativeBuilder: InsightNarrativeBuilder = InsightNarrativeBuilder(),
        featureFlags: FeatureFlags = .default,
        insightRewriter: (any InsightRewriter)? = nil,
        rewriteValidator: RewriteValidator = RewriteValidator()
    ) {
        self.candidateBuilder = candidateBuilder
        self.ranker = ranker
        self.narrativeBuilder = narrativeBuilder
        self.insightRewriter = featureFlags.isEnabled(.coachInsightLLMRewrite)
            ? (insightRewriter ?? NoopInsightRewriter())
            : NoopInsightRewriter()
        self.rewriteValidator = rewriteValidator
    }

    func generatePlanInsights(
        profile: UserProfile,
        plan: WorkoutPlanV2,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophyProgress: TrophyProgressSnapshot,
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) -> [AIInsight] {
        deterministicPlanInsights(
            profile: profile,
            plan: plan,
            trendSnapshot: trendSnapshot,
            signals: signals,
            trophyProgress: trophyProgress,
            engagementRecords: engagementRecords,
            now: now
        )
    }

    func generatePlanInsights(
        profile: UserProfile,
        plan: WorkoutPlanV2,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophyProgress: TrophyProgressSnapshot,
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) async -> [AIInsight] {
        await rewriteIfNeeded(
            deterministicPlanInsights(
                profile: profile,
                plan: plan,
                trendSnapshot: trendSnapshot,
                signals: signals,
                trophyProgress: trophyProgress,
                engagementRecords: engagementRecords,
                now: now
            ),
            profile: profile,
            coachPersonality: plan.coach
        )
    }

    private func deterministicPlanInsights(
        profile: UserProfile,
        plan: WorkoutPlanV2,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophyProgress: TrophyProgressSnapshot,
        engagementRecords: [String: InsightEngagementRecord],
        now: Date
    ) -> [AIInsight] {
        insights(
            from: candidateBuilder.buildPlanCandidates(
                profile: profile,
                plan: plan,
                trendSnapshot: trendSnapshot,
                signals: signals,
                trophyProgress: trophyProgress
            ),
            surface: .workoutPreview,
            profile: profile,
            limit: 3,
            createdAt: trendSnapshot.generatedAt,
            engagementRecords: engagementRecords,
            now: now
        )
    }

    func generateWorkoutInsights(
        profile: UserProfile,
        summary: WorkoutSessionSummary,
        plan: WorkoutPlanV2?,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) -> [AIInsight] {
        deterministicWorkoutInsights(
            profile: profile,
            summary: summary,
            plan: plan,
            trendSnapshot: trendSnapshot,
            signals: signals,
            engagementRecords: engagementRecords,
            now: now
        )
    }

    func generateWorkoutInsights(
        profile: UserProfile,
        summary: WorkoutSessionSummary,
        plan: WorkoutPlanV2?,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) async -> [AIInsight] {
        await rewriteIfNeeded(
            deterministicWorkoutInsights(
                profile: profile,
                summary: summary,
                plan: plan,
                trendSnapshot: trendSnapshot,
                signals: signals,
                engagementRecords: engagementRecords,
                now: now
            ),
            profile: profile,
            coachPersonality: plan?.coach ?? summary.coach
        )
    }

    private func deterministicWorkoutInsights(
        profile: UserProfile,
        summary: WorkoutSessionSummary,
        plan: WorkoutPlanV2?,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        engagementRecords: [String: InsightEngagementRecord],
        now: Date
    ) -> [AIInsight] {
        insights(
            from: candidateBuilder.buildWorkoutCandidates(
                summary: summary,
                plan: plan,
                trendSnapshot: trendSnapshot,
                signals: signals
            ),
            surface: .workoutSummary,
            profile: profile,
            limit: 3,
            createdAt: summary.createdAt,
            engagementRecords: engagementRecords,
            now: now
        )
    }

    func generateDayOverDayInsights(
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        profile: UserProfile,
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) -> [AIInsight] {
        deterministicDayOverDayInsights(
            trendSnapshot: trendSnapshot,
            signals: signals,
            profile: profile,
            engagementRecords: engagementRecords,
            now: now
        )
    }

    func generateDayOverDayInsights(
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        profile: UserProfile,
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) async -> [AIInsight] {
        await rewriteIfNeeded(
            deterministicDayOverDayInsights(
                trendSnapshot: trendSnapshot,
                signals: signals,
                profile: profile,
                engagementRecords: engagementRecords,
                now: now
            ),
            profile: profile,
            coachPersonality: profile.preferredCoach.coachPersonality
        )
    }

    private func deterministicDayOverDayInsights(
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        profile: UserProfile,
        engagementRecords: [String: InsightEngagementRecord],
        now: Date
    ) -> [AIInsight] {
        insights(
            from: candidateBuilder.buildDayOverDayCandidates(
                trendSnapshot: trendSnapshot,
                signals: signals,
                profile: profile
            ),
            surface: .profile,
            profile: profile,
            limit: 3,
            createdAt: trendSnapshot.generatedAt,
            engagementRecords: engagementRecords,
            now: now
        )
    }

    func generateDashboardInsights(
        profile: UserProfile,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophies: TrophyProgressSnapshot,
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) -> [AIInsight] {
        deterministicDashboardInsights(
            profile: profile,
            trendSnapshot: trendSnapshot,
            signals: signals,
            trophies: trophies,
            engagementRecords: engagementRecords,
            now: now
        )
    }

    func generateDashboardInsights(
        profile: UserProfile,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophies: TrophyProgressSnapshot,
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) async -> [AIInsight] {
        await rewriteIfNeeded(
            deterministicDashboardInsights(
                profile: profile,
                trendSnapshot: trendSnapshot,
                signals: signals,
                trophies: trophies,
                engagementRecords: engagementRecords,
                now: now
            ),
            profile: profile,
            coachPersonality: profile.preferredCoach.coachPersonality
        )
    }

    private func deterministicDashboardInsights(
        profile: UserProfile,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophies: TrophyProgressSnapshot,
        engagementRecords: [String: InsightEngagementRecord],
        now: Date
    ) -> [AIInsight] {
        insights(
            from: candidateBuilder.buildDashboardCandidates(
                profile: profile,
                trendSnapshot: trendSnapshot,
                signals: signals,
                trophies: trophies
            ),
            surface: .dashboard,
            profile: profile,
            limit: 2,
            createdAt: trendSnapshot.generatedAt,
            engagementRecords: engagementRecords,
            now: now
        )
    }

    func generateProfileInsights(
        profile: UserProfile,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophies: TrophyProgressSnapshot,
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) -> [AIInsight] {
        deterministicProfileInsights(
            profile: profile,
            trendSnapshot: trendSnapshot,
            signals: signals,
            trophies: trophies,
            engagementRecords: engagementRecords,
            now: now
        )
    }

    func generateProfileInsights(
        profile: UserProfile,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophies: TrophyProgressSnapshot,
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) async -> [AIInsight] {
        await rewriteIfNeeded(
            deterministicProfileInsights(
                profile: profile,
                trendSnapshot: trendSnapshot,
                signals: signals,
                trophies: trophies,
                engagementRecords: engagementRecords,
                now: now
            ),
            profile: profile,
            coachPersonality: profile.preferredCoach.coachPersonality
        )
    }

    private func deterministicProfileInsights(
        profile: UserProfile,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophies: TrophyProgressSnapshot,
        engagementRecords: [String: InsightEngagementRecord],
        now: Date
    ) -> [AIInsight] {
        insights(
            from: candidateBuilder.buildProfileCandidates(
                profile: profile,
                trendSnapshot: trendSnapshot,
                signals: signals,
                trophies: trophies
            ),
            surface: .profile,
            profile: profile,
            limit: 4,
            createdAt: trendSnapshot.generatedAt,
            engagementRecords: engagementRecords,
            now: now
        )
    }
}

nonisolated private extension InsightEngine {
    func rewriteIfNeeded(
        _ insights: [AIInsight],
        profile: UserProfile,
        coachPersonality: CoachPersonality?
    ) async -> [AIInsight] {
        var rewritten: [AIInsight] = []
        rewritten.reserveCapacity(insights.count)

        for insight in insights {
            rewritten.append(
                await rewriteIfValid(
                    insight,
                    profile: profile,
                    coachPersonality: coachPersonality
                )
            )
        }

        return rewritten
    }

    func rewriteIfValid(
        _ insight: AIInsight,
        profile: UserProfile,
        coachPersonality: CoachPersonality?
    ) async -> AIInsight {
        let context = insight.toLLMContext(
            profile: profile,
            coachPersonality: coachPersonality
        )

        guard let rewrite = try? await insightRewriter.rewrite(context) else {
            return insight
        }

        let sanitizedRewrite = rewriteValidator.sanitized(rewrite)
        let proposedInsight = insight.applyingRewrite(sanitizedRewrite)
        guard rewriteValidator.canAdopt(
            proposedInsight,
            replacing: insight,
            context: context
        ) else {
            return insight
        }

        return proposedInsight
    }

    func insights(
        from candidates: [InsightCandidate],
        surface: InsightSurface,
        profile: UserProfile,
        limit: Int,
        createdAt: Date,
        engagementRecords: [String: InsightEngagementRecord],
        now: Date
    ) -> [AIInsight] {
        let deduped = dedupe(
            candidates,
            surface: surface,
            profile: profile,
            engagementRecords: engagementRecords,
            now: now
        )
        return ranker.rank(
            deduped,
            surface: surface,
            profile: profile,
            engagementRecords: engagementRecords,
            now: now
        )
            .prefix(max(limit, 0))
            .map { candidate in
                narrativeBuilder.buildInsight(
                    from: candidate,
                    userValueScore: ranker.userValueScore(
                        for: candidate,
                        surface: surface,
                        profile: profile,
                        engagementRecords: engagementRecords,
                        now: now
                    ),
                    surface: surface,
                    createdAt: createdAt
                )
            }
            .filter { insight in
                !insight.evidence.isEmpty &&
                    insight.recommendedAction != .noActionNeeded &&
                    !insight.isExpired(now: createdAt)
            }
    }

    func dedupe(
        _ candidates: [InsightCandidate],
        surface: InsightSurface,
        profile: UserProfile,
        engagementRecords: [String: InsightEngagementRecord],
        now: Date
    ) -> [InsightCandidate] {
        var byKey: [String: InsightCandidate] = [:]
        for candidate in candidates {
            guard !candidate.evidence.isEmpty else { continue }
            if let existing = byKey[candidate.dedupeKey] {
                let existingScore = ranker.score(
                    existing,
                    surface: surface,
                    profile: profile,
                    engagementRecords: engagementRecords,
                    now: now
                )
                let newScore = ranker.score(
                    candidate,
                    surface: surface,
                    profile: profile,
                    engagementRecords: engagementRecords,
                    now: now
                )
                if newScore > existingScore {
                    byKey[candidate.dedupeKey] = candidate
                }
            } else {
                byKey[candidate.dedupeKey] = candidate
            }
        }
        return Array(byKey.values)
    }
}
