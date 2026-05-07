import Foundation

nonisolated struct InsightRanker {
    func rank(
        _ candidates: [InsightCandidate],
        surface: InsightSurface,
        profile: UserProfile,
        recentlyShownDedupeKeys: Set<String> = [],
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) -> [InsightCandidate] {
        candidates
            .filter { $0.surfaces.contains(surface) }
            .sorted { lhs, rhs in
                let left = score(
                    lhs,
                    surface: surface,
                    profile: profile,
                    recentlyShownDedupeKeys: recentlyShownDedupeKeys,
                    engagementRecords: engagementRecords,
                    now: now
                )
                let right = score(
                    rhs,
                    surface: surface,
                    profile: profile,
                    recentlyShownDedupeKeys: recentlyShownDedupeKeys,
                    engagementRecords: engagementRecords,
                    now: now
                )
                if left == right {
                    if lhs.confidence == rhs.confidence {
                        return lhs.candidateHeadline < rhs.candidateHeadline
                    }
                    return lhs.confidence > rhs.confidence
                }
                return left > right
            }
    }

    func score(
        _ candidate: InsightCandidate,
        surface: InsightSurface,
        profile: UserProfile,
        recentlyShownDedupeKeys: Set<String> = [],
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) -> Double {
        var value = candidate.rawScore
        value += candidate.confidence * 18
        value += specificityScore(candidate)
        value += actionabilityScore(candidate.candidateAction)
        value += emotionalScore(candidate.emotionalIntent)
        value += severityScore(candidate.severity)
        value += surfaceScore(candidate, surface: surface)
        value += goalAlignmentScore(relatedGoal: candidate.relatedGoal, profile: profile)
        value += goalSignalScore(candidate, profile: profile)
        value += engagementScore(
            for: candidate.dedupeKey,
            engagementRecords: engagementRecords,
            now: now
        )

        if candidate.evidence.count >= 2 {
            value += min(Double(candidate.evidence.count), 4)
        }
        if recentlyShownDedupeKeys.contains(candidate.dedupeKey) {
            value -= 36
        }

        return value
    }

    func score(
        _ insight: AIInsight,
        surface: InsightSurface,
        profile: UserProfile,
        recentlyShownDedupeKeys: Set<String> = [],
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) -> Double {
        var value = insight.userValueScore
        value += goalAlignmentScore(relatedGoal: insight.relatedGoal, profile: profile)
        value += goalInsightScore(insight, profile: profile)
        value += engagementScore(
            for: insight.dedupeKey,
            engagementRecords: engagementRecords,
            now: now
        )
        if recentlyShownDedupeKeys.contains(insight.dedupeKey) {
            value -= 36
        }
        return value
    }

    func userValueScore(
        for candidate: InsightCandidate,
        surface: InsightSurface,
        profile: UserProfile,
        recentlyShownDedupeKeys: Set<String> = [],
        engagementRecords: [String: InsightEngagementRecord] = [:],
        now: Date = Date()
    ) -> Double {
        min(max(score(
            candidate,
            surface: surface,
            profile: profile,
            recentlyShownDedupeKeys: recentlyShownDedupeKeys,
            engagementRecords: engagementRecords,
            now: now
        ), 0), 150)
    }
}

nonisolated private extension InsightRanker {
    func goalAlignmentScore(
        relatedGoal: FitnessGoal?,
        profile: UserProfile
    ) -> Double {
        guard let relatedGoal else { return 0 }
        return relatedGoal == profile.primaryGoal ? 10 : 3
    }

    func goalSignalScore(
        _ candidate: InsightCandidate,
        profile: UserProfile
    ) -> Double {
        let signalType = candidate.context["signalType"].flatMap(TrainingSignalType.init(rawValue:))
        switch profile.primaryGoal {
        case .strength:
            guard let signalType,
                  [.progressionReadiness, .qualityPR, .exerciseMastery].contains(signalType)
            else {
                return 0
            }
            return 6
        case .longevity:
            if candidate.type == .recovery {
                return 8
            }
            guard let signalType,
                  [.planFit, .sessionFit, .restResponse].contains(signalType)
            else {
                return 0
            }
            return 8
        case .performance:
            guard let signalType,
                  [.progressionReadiness, .qualityCapacity, .formImprovement].contains(signalType)
            else {
                return 0
            }
            return 6
        }
    }

    func goalInsightScore(
        _ insight: AIInsight,
        profile: UserProfile
    ) -> Double {
        switch profile.primaryGoal {
        case .longevity where insight.type == .recovery:
            return 8
        default:
            return 0
        }
    }

    func engagementScore(
        for dedupeKey: String,
        engagementRecords: [String: InsightEngagementRecord],
        now: Date
    ) -> Double {
        guard let record = engagementRecords[dedupeKey] else { return 0 }

        var value = 0.0
        if record.count(for: .opened) > 0 {
            value += 2
        }
        if record.count(for: .helpful) > 0 {
            value += 6
        }
        if record.count(for: .notHelpful) > 0 {
            value -= 12
        }
        if let dismissedAt = record.lastEngagedAt(for: .dismissed),
           now.timeIntervalSince(dismissedAt) < 7 * 24 * 60 * 60 {
            value -= 20
        }
        return value
    }

    func specificityScore(_ candidate: InsightCandidate) -> Double {
        var value = 0.0
        if candidate.relatedExerciseType != nil {
            value += 10
        }
        if candidate.evidence.contains(where: { $0.exerciseType != nil }) {
            value += 6
        }
        if candidate.evidence.contains(where: { $0.repIndex != nil }) {
            value += 8
        }
        if candidate.evidence.contains(where: { $0.setIndex != nil }) {
            value += 4
        }
        if candidate.evidence.contains(where: { $0.comparison != nil }) {
            value += 5
        }
        if candidate.context["cue"]?.isEmpty == false {
            value += 4
        }
        return value
    }

    func actionabilityScore(_ action: InsightAction) -> Double {
        switch action {
        case .focusCue, .useEasierVariant, .increaseRest, .decreaseTarget, .repeatTarget, .swapExerciseLater, .takeMobilityDay:
            return 14
        case .increaseTarget, .reduceRest, .useHarderVariant, .protectStreakWithSmartStart:
            return 11
        case .continuePlan:
            return 7
        case .celebrate:
            return 5
        case .noActionNeeded:
            return -20
        }
    }

    func emotionalScore(_ intent: InsightEmotionalIntent) -> Double {
        switch intent {
        case .preventOverreach, .giveToughLove:
            return 9
        case .celebrateGrowth, .buildConfidence:
            return 8
        case .reinforceConsistency, .unlockMotivation:
            return 6
        case .explainPlan:
            return 5
        }
    }

    func severityScore(_ severity: InsightSeverity) -> Double {
        switch severity {
        case .important:
            return 9
        case .caution:
            return 7
        case .positive:
            return 5
        case .neutral:
            return 2
        }
    }

    func surfaceScore(_ candidate: InsightCandidate, surface: InsightSurface) -> Double {
        switch surface {
        case .workoutSummary:
            switch candidate.type {
            case .formCorrection, .growthCelebration, .workoutSpecific, .planAdjustment, .recovery:
                return 12
            case .trophyProgress:
                return 4
            default:
                return 1
            }
        case .workoutPreview:
            switch candidate.type {
            case .planSpecific, .planAdjustment, .safety, .recovery:
                return 12
            case .growthCelebration, .formCorrection:
                return 7
            default:
                return 2
            }
        case .dashboard:
            switch candidate.type {
            case .consistency, .recovery, .safety, .dayOverDayTrend:
                return 10
            case .growthCelebration, .formCorrection, .trophyProgress:
                return 7
            default:
                return 3
            }
        case .profile:
            switch candidate.type {
            case .growthCelebration, .dayOverDayTrend, .consistency, .formCorrection:
                return 12
            case .trophyProgress, .recovery, .safety:
                return 8
            default:
                return 3
            }
        case .trophyScreen:
            return candidate.type == .trophyProgress ? 14 : 1
        }
    }
}
