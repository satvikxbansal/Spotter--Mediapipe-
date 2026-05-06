import Foundation

nonisolated struct InsightEngine {
    private let candidateBuilder: InsightCandidateBuilder
    private let ranker: InsightRanker
    private let narrativeBuilder: InsightNarrativeBuilder

    init(
        candidateBuilder: InsightCandidateBuilder = InsightCandidateBuilder(),
        ranker: InsightRanker = InsightRanker(),
        narrativeBuilder: InsightNarrativeBuilder = InsightNarrativeBuilder()
    ) {
        self.candidateBuilder = candidateBuilder
        self.ranker = ranker
        self.narrativeBuilder = narrativeBuilder
    }

    func generatePlanInsights(
        profile: UserProfile,
        plan: WorkoutPlanV2,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophyProgress: TrophyProgressSnapshot
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
            limit: 3,
            createdAt: trendSnapshot.generatedAt
        )
    }

    func generateWorkoutInsights(
        summary: WorkoutSessionSummary,
        plan: WorkoutPlanV2?,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal]
    ) -> [AIInsight] {
        insights(
            from: candidateBuilder.buildWorkoutCandidates(
                summary: summary,
                plan: plan,
                trendSnapshot: trendSnapshot,
                signals: signals
            ),
            surface: .workoutSummary,
            limit: 3,
            createdAt: summary.createdAt
        )
    }

    func generateDayOverDayInsights(
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        profile: UserProfile
    ) -> [AIInsight] {
        insights(
            from: candidateBuilder.buildDayOverDayCandidates(
                trendSnapshot: trendSnapshot,
                signals: signals,
                profile: profile
            ),
            surface: .profile,
            limit: 3,
            createdAt: trendSnapshot.generatedAt
        )
    }

    func generateDashboardInsights(
        profile: UserProfile,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophies: TrophyProgressSnapshot
    ) -> [AIInsight] {
        insights(
            from: candidateBuilder.buildDashboardCandidates(
                profile: profile,
                trendSnapshot: trendSnapshot,
                signals: signals,
                trophies: trophies
            ),
            surface: .dashboard,
            limit: 2,
            createdAt: trendSnapshot.generatedAt
        )
    }

    func generateProfileInsights(
        profile: UserProfile,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophies: TrophyProgressSnapshot
    ) -> [AIInsight] {
        insights(
            from: candidateBuilder.buildProfileCandidates(
                profile: profile,
                trendSnapshot: trendSnapshot,
                signals: signals,
                trophies: trophies
            ),
            surface: .profile,
            limit: 4,
            createdAt: trendSnapshot.generatedAt
        )
    }
}

nonisolated private extension InsightEngine {
    func insights(
        from candidates: [InsightCandidate],
        surface: InsightSurface,
        limit: Int,
        createdAt: Date
    ) -> [AIInsight] {
        let deduped = dedupe(candidates, surface: surface)
        return ranker.rank(deduped, surface: surface)
            .prefix(max(limit, 0))
            .map { candidate in
                narrativeBuilder.buildInsight(
                    from: candidate,
                    userValueScore: ranker.userValueScore(for: candidate, surface: surface),
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
        surface: InsightSurface
    ) -> [InsightCandidate] {
        var byKey: [String: InsightCandidate] = [:]
        for candidate in candidates {
            guard !candidate.evidence.isEmpty else { continue }
            if let existing = byKey[candidate.dedupeKey] {
                let existingScore = ranker.score(existing, surface: surface)
                let newScore = ranker.score(candidate, surface: surface)
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
