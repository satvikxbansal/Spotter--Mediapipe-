import Foundation

nonisolated struct InsightRanker {
    func rank(
        _ candidates: [InsightCandidate],
        surface: InsightSurface,
        recentlyShownDedupeKeys: Set<String> = []
    ) -> [InsightCandidate] {
        candidates
            .filter { $0.surfaces.contains(surface) }
            .sorted { lhs, rhs in
                let left = score(lhs, surface: surface, recentlyShownDedupeKeys: recentlyShownDedupeKeys)
                let right = score(rhs, surface: surface, recentlyShownDedupeKeys: recentlyShownDedupeKeys)
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
        recentlyShownDedupeKeys: Set<String> = []
    ) -> Double {
        var value = candidate.rawScore
        value += candidate.confidence * 18
        value += specificityScore(candidate)
        value += actionabilityScore(candidate.candidateAction)
        value += emotionalScore(candidate.emotionalIntent)
        value += severityScore(candidate.severity)
        value += surfaceScore(candidate, surface: surface)

        if candidate.relatedGoal != nil {
            value += 4
        }
        if candidate.evidence.count >= 2 {
            value += min(Double(candidate.evidence.count), 4)
        }
        if recentlyShownDedupeKeys.contains(candidate.dedupeKey) {
            value -= 36
        }

        return value
    }

    func userValueScore(
        for candidate: InsightCandidate,
        surface: InsightSurface,
        recentlyShownDedupeKeys: Set<String> = []
    ) -> Double {
        min(max(score(candidate, surface: surface, recentlyShownDedupeKeys: recentlyShownDedupeKeys), 0), 150)
    }
}

nonisolated private extension InsightRanker {
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
