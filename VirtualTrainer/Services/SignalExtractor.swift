import Foundation

nonisolated struct SignalExtractor {
    private let trendEngine: TrendEngine

    init(trendEngine: TrendEngine = TrendEngine()) {
        self.trendEngine = trendEngine
    }

    func extractSignals(
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        profile: UserProfile,
        trophies: TrophyProgressSnapshot,
        context: SignalGenerationContext? = nil
    ) -> [UserTrainingSignal] {
        guard snapshot.totalWorkouts > 0 else { return [] }
        let generationContext = context ?? SignalGenerationContext(
            historySessionCount: max(snapshot.totalWorkouts, history.count)
        )

        let sortedHistory = history.sorted {
            if $0.endedAt == $1.endedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.endedAt > $1.endedAt
        }

        var signals: [UserTrainingSignal] = []
        appendBootstrapSignals(
            to: &signals,
            snapshot: snapshot,
            history: sortedHistory,
            profile: profile,
            context: generationContext
        )
        appendConsistencySignals(
            to: &signals,
            snapshot: snapshot,
            history: sortedHistory,
            profile: profile
        )
        appendFormTrendSignals(
            to: &signals,
            snapshot: snapshot,
            history: sortedHistory,
            profile: profile,
            context: generationContext
        )
        appendVolumeSignals(
            to: &signals,
            history: sortedHistory,
            profile: profile,
            createdAt: snapshot.generatedAt,
            context: generationContext
        )
        appendRepeatedCueSignal(
            to: &signals,
            snapshot: snapshot,
            history: sortedHistory,
            profile: profile
        )
        appendExerciseSpecificSignals(
            to: &signals,
            snapshot: snapshot,
            history: sortedHistory,
            profile: profile
        )
        appendTrophySignals(
            to: &signals,
            snapshot: snapshot,
            trophies: trophies,
            profile: profile
        )
        appendCameraFrictionSignal(
            to: &signals,
            snapshot: snapshot,
            history: sortedHistory,
            profile: profile,
            context: generationContext
        )
        appendFatigueSignal(
            to: &signals,
            snapshot: snapshot,
            history: sortedHistory,
            profile: profile
        )
        appendDerivedCoachingSignals(
            to: &signals,
            snapshot: snapshot,
            history: sortedHistory,
            profile: profile
        )

        return deduplicated(signals).sorted(by: signalSort)
    }
}

nonisolated private extension SignalExtractor {
    struct SignalSetObservation {
        let summary: WorkoutSessionSummary
        let setSummary: ExerciseSetSummary
        let exerciseType: ExerciseType
        let setIndex: Int?
        let endedAt: Date
        let achievedUnits: Int
        let targetUnits: Int?
        let unitLabel: String
        let averageFormScore: Double?
        let scoredRepCount: Int
        let qualityTrend: SetQualityTrend
        let highSeverityCueCount: Int
        let breakdownRepIndex: Int?
        let excellentFormReps: Int
        let restExtended: Bool
        let skipped: Bool
        let cueMessages: [String]
        let cameraFrictionCueCount: Int

        var hasScoredQuality: Bool {
            averageFormScore != nil || setSummary.qualitySummary != nil || !setSummary.repQualityEvents.isEmpty
        }

        var targetRatio: Double? {
            guard let targetUnits, targetUnits > 0 else { return nil }
            return Double(achievedUnits) / Double(targetUnits)
        }

        var hasFormFriction: Bool {
            highSeverityCueCount > 0 || breakdownRepIndex != nil || qualityTrend == .faded || (averageFormScore ?? 100) < 78
        }
    }

    struct RestResponseObservation {
        let before: SignalSetObservation
        let after: SignalSetObservation
        let delta: Double
    }

    struct CueClusterBucket {
        let key: String
        let label: String
        let cueMessages: [String]
        let observations: [SignalSetObservation]
    }

    func appendBootstrapSignals(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        profile: UserProfile,
        context: SignalGenerationContext
    ) {
        guard context.historySessionCount > 0,
              !history.isEmpty
        else { return }

        let observations = setObservations(from: history)

        if context.historySessionCount == 1 {
            appendFirstSessionSignal(to: &signals, snapshot: snapshot, history: history, profile: profile)
            appendSetupQualitySignal(to: &signals, snapshot: snapshot, history: history, observations: observations, profile: profile)
            appendRepCleanlinessIntroSignal(to: &signals, snapshot: snapshot, observations: observations, profile: profile)
        }

        if context.historySessionCount == 2 {
            appendRepeatExerciseProgressSignal(to: &signals, snapshot: snapshot, history: history, profile: profile)
        }

        appendPersonalBaselineSignal(to: &signals, snapshot: snapshot, observations: observations, profile: profile)
    }

    func appendFirstSessionSignal(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        profile: UserProfile
    ) {
        signals.append(
            UserTrainingSignal(
                type: .firstSession,
                goal: profile.primaryGoal,
                title: "First session is logged",
                value: "1 workout completed",
                comparisonValue: "first baseline started",
                delta: 1,
                confidence: .medium,
                evidenceRefs: latestSessionRefs(history, limit: 1),
                createdAt: snapshot.generatedAt
            )
        )
    }

    func appendSetupQualitySignal(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        observations: [SignalSetObservation],
        profile: UserProfile
    ) {
        guard let latestSummary = history.first else { return }
        let latestObservations = observations.filter { $0.summary.id == latestSummary.id }
        let setupCueCount = latestObservations.reduce(0) { $0 + $1.cameraFrictionCueCount }
        let cueEvidence = cameraFrictionEvidenceRefs(
            history: [latestSummary],
            limit: 2,
            policy: trendEngine.recentSetupPolicy,
            now: snapshot.generatedAt
        )
        let evidence = cueEvidence.isEmpty ? latestSessionRefs([latestSummary], limit: 1) : cueEvidence

        signals.append(
            UserTrainingSignal(
                type: .setupQuality,
                goal: profile.primaryGoal,
                title: setupCueCount > 0 ? "Camera setup has an early fix" : "Camera setup stayed clear",
                value: setupCueCount > 0 ? "\(setupCueCount) setup cue\(setupCueCount == 1 ? "" : "s")" : "no setup cues",
                comparisonValue: setupCueCount > 0 ? "frame first, reps second" : "body stayed visible enough to score",
                delta: Double(setupCueCount),
                confidence: .medium,
                evidenceRefs: evidence,
                createdAt: snapshot.generatedAt
            )
        )
    }

    func appendRepCleanlinessIntroSignal(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        observations: [SignalSetObservation],
        profile: UserProfile
    ) {
        guard let latestSummary = observations.first?.summary,
              let firstSet = firstSetObservation(in: latestSummary, observations: observations),
              let quality = firstSet.setSummary.qualitySummary,
              quality.totalScoredReps > 0
        else { return }

        let percent = (Double(quality.goodFormReps) / Double(quality.totalScoredReps)) * 100
        signals.append(
            UserTrainingSignal(
                type: .repCleanlinessIntro,
                exerciseType: firstSet.exerciseType,
                movementPattern: metadata(for: firstSet.exerciseType)?.movementPattern,
                goal: profile.primaryGoal,
                title: "\(firstSet.exerciseType.displayName) first set has a clean-rep baseline",
                value: "\(Int(percent.rounded()))% good-form reps",
                comparisonValue: "\(quality.goodFormReps)/\(quality.totalScoredReps) scored reps",
                delta: percent,
                confidence: .medium,
                evidenceRefs: evidenceRefs(from: [firstSet], limit: 1),
                createdAt: snapshot.generatedAt
            )
        )
    }

    func appendRepeatExerciseProgressSignal(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        profile: UserProfile
    ) {
        guard history.count >= 2 else { return }
        let observations = setObservations(from: Array(history.prefix(2)))
        let latestSummary = history[0]
        let previousSummary = history[1]
        let latestByExercise = firstSetObservationsByExercise(in: latestSummary, observations: observations)
        let previousByExercise = firstSetObservationsByExercise(in: previousSummary, observations: observations)
        let repeatedExercises = Set(latestByExercise.keys).intersection(previousByExercise.keys)

        let candidates = repeatedExercises.compactMap { exercise -> (exercise: ExerciseType, latest: SignalSetObservation, previous: SignalSetObservation, delta: Double)? in
            guard let latest = latestByExercise[exercise],
                  let previous = previousByExercise[exercise],
                  let latestScore = latest.averageFormScore,
                  let previousScore = previous.averageFormScore
            else { return nil }

            return (exercise, latest, previous, latestScore - previousScore)
        }
        .sorted {
            if abs($0.delta) == abs($1.delta) {
                return $0.exercise.rawValue < $1.exercise.rawValue
            }
            return abs($0.delta) > abs($1.delta)
        }

        guard let candidate = candidates.first,
              let latestScore = candidate.latest.averageFormScore,
              let previousScore = candidate.previous.averageFormScore
        else { return }

        signals.append(
            UserTrainingSignal(
                type: .repeatExerciseProgress,
                exerciseType: candidate.exercise,
                movementPattern: metadata(for: candidate.exercise)?.movementPattern,
                goal: profile.primaryGoal,
                title: repeatExerciseTitle(for: candidate.exercise, delta: candidate.delta),
                value: "set 1 \(formatPercent(latestScore))",
                comparisonValue: "previous set 1 \(formatPercent(previousScore))",
                delta: candidate.delta,
                confidence: .medium,
                evidenceRefs: evidenceRefs(from: [candidate.latest, candidate.previous], limit: 2),
                createdAt: snapshot.generatedAt
            )
        )
    }

    func appendPersonalBaselineSignal(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        observations: [SignalSetObservation],
        profile: UserProfile
    ) {
        let scored = observations.filter { $0.averageFormScore != nil }
        let candidates = Dictionary(grouping: scored, by: \.exerciseType)
            .compactMap { exercise, values -> (exercise: ExerciseType, median: Double, sessionCount: Int, units: Int, refs: [TrainingEvidenceRef])? in
                let scores = values.compactMap(\.averageFormScore)
                guard let medianScore = median(scores) else { return nil }
                let sessionCount = Set(values.map { $0.summary.id }).count
                let units = values.reduce(0) { $0 + $1.achievedUnits }
                return (
                    exercise,
                    medianScore,
                    sessionCount,
                    units,
                    evidenceRefs(from: Array(values.prefix(3)), limit: 3)
                )
            }
            .sorted { lhs, rhs in
                if lhs.sessionCount == rhs.sessionCount {
                    if lhs.units == rhs.units {
                        return lhs.exercise.rawValue < rhs.exercise.rawValue
                    }
                    return lhs.units > rhs.units
                }
                return lhs.sessionCount > rhs.sessionCount
            }

        guard let candidate = candidates.first,
              !candidate.refs.isEmpty
        else { return }

        signals.append(
            UserTrainingSignal(
                type: .personalBaseline,
                exerciseType: candidate.exercise,
                movementPattern: metadata(for: candidate.exercise)?.movementPattern,
                goal: profile.primaryGoal,
                title: "\(candidate.exercise.displayName) baseline is forming",
                value: "\(formatPercent(candidate.median)) median form",
                comparisonValue: "\(candidate.sessionCount) session\(candidate.sessionCount == 1 ? "" : "s") so far",
                delta: candidate.median,
                confidence: .medium,
                evidenceRefs: candidate.refs,
                createdAt: snapshot.generatedAt
            )
        )
    }

    func appendConsistencySignals(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        profile: UserProfile
    ) {
        if snapshot.currentStreak > 0 {
            let nextMilestone = [3, 7, 14, 30].first { $0 > snapshot.currentStreak }
            let isClose = nextMilestone.map { $0 - snapshot.currentStreak <= 1 } ?? false
            signals.append(
                UserTrainingSignal(
                    type: .consistency,
                    goal: profile.primaryGoal,
                    title: isClose ? "Streak is close to a milestone" : "Active training streak",
                    value: "\(snapshot.currentStreak) day\(snapshot.currentStreak == 1 ? "" : "s")",
                    comparisonValue: nextMilestone.map { "\($0) days" },
                    delta: nextMilestone.map { Double($0 - snapshot.currentStreak) },
                    confidence: isClose ? .high : .medium,
                    evidenceRefs: latestSessionRefs(history, limit: min(snapshot.currentStreak, 3)),
                    createdAt: snapshot.generatedAt
                )
            )
        }

        if snapshot.weeklyConsistencyStatus == .aligned ||
            snapshot.weeklyConsistencyStatus == .aboveTarget {
            let targetDays = max(profile.workoutDaysPerWeek ?? UserProfile.defaultWorkoutDaysPerWeek, 1)
            signals.append(
                UserTrainingSignal(
                    type: .completion,
                    goal: profile.primaryGoal,
                    title: "Weekly training target is on track",
                    value: "\(snapshot.workoutDaysThisWeek) \(dayLabel(snapshot.workoutDaysThisWeek)) this week",
                    comparisonValue: "\(targetDays) \(dayLabel(targetDays)) target",
                    delta: Double(snapshot.workoutDaysThisWeek - targetDays),
                    confidence: .high,
                    evidenceRefs: latestSessionRefs(history, limit: 3),
                    createdAt: snapshot.generatedAt
                )
            )
        }
    }

    func appendFormTrendSignals(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        profile: UserProfile,
        context: SignalGenerationContext
    ) {
        let useWarmupComparison = context.historySessionCount >= 3 && context.historySessionCount < 6
        let comparison = useWarmupComparison
            ? trendEngine.latestWorkoutComparison(history: history, metric: .formScore)
            : trendEngine.threeWorkoutComparison(history: history, metric: .formScore)
        guard let delta = comparison.delta,
              let latest = comparison.latestValue,
              let previous = comparison.comparisonValue
        else { return }

        let direction = useWarmupComparison
            ? trendDirection(delta: delta, meaningfulThreshold: 5, positive: .improving, negative: .declining)
            : snapshot.overallFormTrend
        let confidence: SignalConfidence = useWarmupComparison ? .medium : (abs(delta) >= 8 ? .high : .medium)
        let evidenceLimit = useWarmupComparison ? 2 : 6

        if direction == .improving {
            signals.append(
                UserTrainingSignal(
                    type: .formImprovement,
                    goal: profile.primaryGoal,
                    title: "Average form improved over recent workouts",
                    value: formatPercent(latest),
                    comparisonValue: formatPercent(previous),
                    delta: delta,
                    confidence: confidence,
                    evidenceRefs: latestSessionRefs(history, limit: evidenceLimit),
                    createdAt: snapshot.generatedAt
                )
            )
        } else if direction == .declining {
            signals.append(
                UserTrainingSignal(
                    type: .formDropOff,
                    goal: profile.primaryGoal,
                    title: "Average form is lower than the previous comparable block",
                    value: formatPercent(latest),
                    comparisonValue: formatPercent(previous),
                    delta: delta,
                    confidence: confidence,
                    evidenceRefs: latestSessionRefs(history, limit: evidenceLimit),
                    createdAt: snapshot.generatedAt
                )
            )
        }
    }

    func appendVolumeSignals(
        to signals: inout [UserTrainingSignal],
        history: [WorkoutSessionSummary],
        profile: UserProfile,
        createdAt: Date,
        context: SignalGenerationContext
    ) {
        let useWarmupComparison = context.historySessionCount >= 3 && context.historySessionCount < 6
        let comparison = useWarmupComparison
            ? trendEngine.latestWorkoutComparison(history: history, metric: .volumeUnits)
            : trendEngine.threeWorkoutComparison(history: history, metric: .volumeUnits)
        guard let delta = comparison.delta,
              let latest = comparison.latestValue,
              let previous = comparison.comparisonValue,
              abs(delta) >= 8
        else { return }

        signals.append(
            UserTrainingSignal(
                type: delta > 0 ? .volumeIncrease : .volumeDrop,
                goal: profile.primaryGoal,
                title: delta > 0 ? "Recent workout volume increased" : "Recent workout volume decreased",
                value: formatNumber(latest),
                comparisonValue: formatNumber(previous),
                delta: delta,
                confidence: useWarmupComparison ? .medium : (abs(delta) >= 18 ? .high : .medium),
                evidenceRefs: latestSessionRefs(history, limit: useWarmupComparison ? 2 : 6),
                createdAt: createdAt
            )
        )
    }

    func appendRepeatedCueSignal(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        profile: UserProfile
    ) {
        guard let cue = snapshot.mostRepeatedCue else { return }
        let evidence = cueEvidenceRefs(
            cue,
            history: history,
            limit: 4,
            policy: trendEngine.recentCuePolicy,
            now: snapshot.generatedAt
        )
        guard evidence.count >= 2 else { return }
        let sessionCount = Set(evidence.compactMap(\.summaryId)).count

        signals.append(
            UserTrainingSignal(
                type: .repeatedCue,
                goal: profile.primaryGoal,
                title: "Same form cue is repeating",
                value: cue,
                comparisonValue: "\(evidence.count) cue events",
                delta: Double(evidence.count),
                confidence: sessionCount >= 2 && evidence.count >= 3 ? .high : .medium,
                evidenceRefs: evidence,
                createdAt: snapshot.generatedAt
            )
        )
    }

    func appendExerciseSpecificSignals(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        profile: UserProfile
    ) {
        if let exercise = snapshot.improvingExercise,
           let trend = snapshot.exerciseTrends.first(where: { $0.exerciseType == exercise }),
           let delta = trend.recentFormDelta {
            signals.append(
                UserTrainingSignal(
                    type: .formImprovement,
                    exerciseType: exercise,
                    movementPattern: metadata(for: exercise)?.movementPattern,
                    goal: profile.primaryGoal,
                    title: "\(exercise.displayName) form is improving",
                    value: formatDelta(delta, suffix: " pts"),
                    comparisonValue: trend.averageFormScore.map(formatPercent),
                    delta: delta,
                    confidence: delta >= 8 ? .high : .medium,
                    evidenceRefs: exerciseEvidenceRefs(exercise, history: history, limit: 4),
                    createdAt: snapshot.generatedAt
                )
            )
        }

        if let exercise = snapshot.strongestExercise,
           let trend = snapshot.exerciseTrends.first(where: { $0.exerciseType == exercise }),
           trend.sessions >= 2,
           (trend.averageFormScore ?? 0) >= 85,
           trend.highSeverityCueCount <= 1 {
            signals.append(
                UserTrainingSignal(
                    type: .exerciseMastery,
                    exerciseType: exercise,
                    movementPattern: metadata(for: exercise)?.movementPattern,
                    goal: profile.primaryGoal,
                    title: "\(exercise.displayName) is a strong movement",
                    value: trend.averageFormScore.map(formatPercent) ?? "\(trend.totalReps) reps",
                    comparisonValue: "\(trend.sessions) sessions",
                    delta: trend.recentFormDelta,
                    confidence: (trend.averageFormScore ?? 0) >= 90 ? .high : .medium,
                    evidenceRefs: exerciseEvidenceRefs(exercise, history: history, limit: 4),
                    createdAt: snapshot.generatedAt
                )
            )
        }

        if let exercise = snapshot.strugglingExercise,
           let trend = snapshot.exerciseTrends.first(where: { $0.exerciseType == exercise }) {
            let confidence: SignalConfidence = trend.formDropOffSetCount >= 2 ||
                trend.highSeverityCueCount >= 3 ||
                (trend.recentFormDelta ?? 0) <= -8 ? .high : .medium
            signals.append(
                UserTrainingSignal(
                    type: .exerciseStruggle,
                    exerciseType: exercise,
                    movementPattern: metadata(for: exercise)?.movementPattern,
                    goal: profile.primaryGoal,
                    title: "\(exercise.displayName) has repeated friction",
                    value: struggleValue(for: trend),
                    comparisonValue: trend.mostCommonCue,
                    delta: trend.recentFormDelta,
                    confidence: confidence,
                    evidenceRefs: exerciseEvidenceRefs(exercise, history: history, limit: 4),
                    createdAt: snapshot.generatedAt
                )
            )

            appendPlanFitSignal(
                to: &signals,
                exercise: exercise,
                trend: trend,
                history: history,
                profile: profile,
                createdAt: snapshot.generatedAt
            )
        }

        if let restTrend = snapshot.exerciseTrends
            .filter({ $0.restExtendedSetCount >= 2 })
            .sorted(by: { $0.restExtendedSetCount > $1.restExtendedSetCount })
            .first {
            signals.append(
                UserTrainingSignal(
                    type: .restBehavior,
                    exerciseType: restTrend.exerciseType,
                    movementPattern: metadata(for: restTrend.exerciseType)?.movementPattern,
                    goal: profile.primaryGoal,
                    title: "Rest was extended around \(restTrend.exerciseType.displayName)",
                    value: "\(restTrend.restExtendedSetCount) extended rests",
                    comparisonValue: nil,
                    delta: Double(restTrend.restExtendedSetCount),
                    confidence: restTrend.restExtendedSetCount >= 3 ? .high : .medium,
                    evidenceRefs: exerciseEvidenceRefs(restTrend.exerciseType, history: history, limit: 4),
                    createdAt: snapshot.generatedAt
                )
            )
        }

        if let skippedTrend = snapshot.exerciseTrends
            .filter({ $0.skippedSetCount >= 2 })
            .sorted(by: { $0.skippedSetCount > $1.skippedSetCount })
            .first {
            signals.append(
                UserTrainingSignal(
                    type: .skippedExercise,
                    exerciseType: skippedTrend.exerciseType,
                    movementPattern: metadata(for: skippedTrend.exerciseType)?.movementPattern,
                    goal: profile.primaryGoal,
                    title: "Rest was skipped early around \(skippedTrend.exerciseType.displayName)",
                    value: "\(skippedTrend.skippedSetCount) early rest skip\(skippedTrend.skippedSetCount == 1 ? "" : "s")",
                    comparisonValue: nil,
                    delta: Double(skippedTrend.skippedSetCount),
                    confidence: skippedTrend.skippedSetCount >= 3 ? .high : .medium,
                    evidenceRefs: exerciseEvidenceRefs(skippedTrend.exerciseType, history: history, limit: 4),
                    createdAt: snapshot.generatedAt
                )
            )
        }
    }

    func appendPlanFitSignal(
        to signals: inout [UserTrainingSignal],
        exercise: ExerciseType,
        trend: ExerciseTrendSummary,
        history: [WorkoutSessionSummary],
        profile: UserProfile,
        createdAt: Date
    ) {
        guard !profile.limitations.isEmpty,
              let metadata = metadata(for: exercise)
        else { return }

        let limitationTags = Set(profile.limitations.map(limitationTag))
        let conflicts = metadata.contraindicationTags.intersection(limitationTags)
        guard !conflicts.isEmpty else { return }

        signals.append(
            UserTrainingSignal(
                type: .planFit,
                exerciseType: exercise,
                movementPattern: metadata.movementPattern,
                goal: profile.primaryGoal,
                title: "\(exercise.displayName) overlaps with a saved limitation",
                value: conflicts.map(\.rawValue).sorted().joined(separator: ", "),
                comparisonValue: trend.mostCommonCue,
                delta: trend.recentFormDelta,
                confidence: trend.highSeverityCueCount >= 2 || trend.formDropOffSetCount >= 1 ? .high : .medium,
                evidenceRefs: exerciseEvidenceRefs(exercise, history: history, limit: 4),
                createdAt: createdAt
            )
        )
    }

    func appendTrophySignals(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        trophies: TrophyProgressSnapshot,
        profile: UserProfile
    ) {
        let trophyIDs = Set(trophies.inProgress.map(\.trophyId))
        for nearMiss in snapshot.trophyNearMisses where trophyIDs.contains(nearMiss.trophyId) {
            signals.append(
                UserTrainingSignal(
                    type: .trophyProximity,
                    goal: profile.primaryGoal,
                    title: "\(nearMiss.title) trophy is within reach",
                    value: "\(formatNumber(nearMiss.currentValue))/\(formatNumber(nearMiss.targetValue)) \(nearMiss.unit)",
                    comparisonValue: "\(formatNumber(nearMiss.remainingValue)) \(nearMiss.unit) remaining",
                    delta: nearMiss.remainingValue,
                    confidence: nearMiss.progressFraction >= 0.85 ? .high : .medium,
                    evidenceRefs: [
                        TrainingEvidenceRef(
                            label: "Trophy progress \(nearMiss.trophyId)"
                        )
                    ],
                    createdAt: snapshot.generatedAt
                )
            )
        }
    }

    func appendCameraFrictionSignal(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        profile: UserProfile,
        context: SignalGenerationContext
    ) {
        guard context.historySessionCount != 1 else { return }
        guard snapshot.cameraFrictionCount >= 2 else { return }
        let evidence = cameraFrictionEvidenceRefs(
            history: history,
            limit: 4,
            policy: trendEngine.recentSetupPolicy,
            now: snapshot.generatedAt
        )
        let sessionCount = Set(evidence.compactMap(\.summaryId)).count
        signals.append(
            UserTrainingSignal(
                type: .cameraFriction,
                goal: profile.primaryGoal,
                title: "Camera visibility cues repeated",
                value: "\(snapshot.cameraFrictionCount) camera or visibility cues",
                comparisonValue: "\(sessionCount) session\(sessionCount == 1 ? "" : "s")",
                delta: Double(snapshot.cameraFrictionCount),
                confidence: snapshot.cameraFrictionCount >= 4 || sessionCount >= 2 ? .high : .medium,
                evidenceRefs: evidence,
                createdAt: snapshot.generatedAt
            )
        )
    }

    func appendFatigueSignal(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        profile: UserProfile
    ) {
        guard snapshot.fatigueTrend == .elevated ||
            snapshot.fatigueTrend == .increasing
        else { return }

        let recentEffort = history.prefix(3)
            .compactMap { $0.structuredEffortSummary?.peakEffort }
        let value = recentEffort.max().map { formatPercent($0 * 100) } ?? "effort proxy present"

        signals.append(
            UserTrainingSignal(
                type: .fatigue,
                goal: profile.primaryGoal,
                title: "Recent late-session strain signals are higher",
                value: value,
                comparisonValue: "Face-effort proxy only",
                delta: nil,
                confidence: snapshot.fatigueTrend == .elevated ? .high : .medium,
                evidenceRefs: latestSessionRefs(history, limit: 3),
                createdAt: snapshot.generatedAt
            )
        )
    }

    func appendDerivedCoachingSignals(
        to signals: inout [UserTrainingSignal],
        snapshot: UserTrainingTrendSnapshot,
        history: [WorkoutSessionSummary],
        profile: UserProfile
    ) {
        let observations = setObservations(from: history)
        guard !observations.isEmpty else { return }

        appendQualityCapacitySignal(to: &signals, observations: observations, createdAt: snapshot.generatedAt, profile: profile)
        appendTargetFitSignal(to: &signals, observations: observations, history: history, createdAt: snapshot.generatedAt, profile: profile)
        appendMovementBalanceSignal(to: &signals, observations: observations, history: history, createdAt: snapshot.generatedAt, profile: profile)
        appendCueClusterSignal(to: &signals, observations: observations, history: history, createdAt: snapshot.generatedAt, profile: profile)
        appendRestResponseSignal(to: &signals, observations: observations, createdAt: snapshot.generatedAt, profile: profile)
        appendProgressionReadinessSignal(to: &signals, observations: observations, createdAt: snapshot.generatedAt, profile: profile)
        appendSessionFitSignal(to: &signals, history: history, createdAt: snapshot.generatedAt, profile: profile)
        appendExerciseReacquisitionSignal(to: &signals, observations: observations, createdAt: snapshot.generatedAt, profile: profile)
        appendExercisePreferenceSignal(to: &signals, observations: observations, createdAt: snapshot.generatedAt, profile: profile)
        appendQualityPRSignal(to: &signals, observations: observations, createdAt: snapshot.generatedAt, profile: profile)
    }

    func appendQualityCapacitySignal(
        to signals: inout [UserTrainingSignal],
        observations: [SignalSetObservation],
        createdAt: Date,
        profile: UserProfile
    ) {
        let candidates = Dictionary(grouping: observations.filter { $0.achievedUnits > 0 && $0.hasScoredQuality }, by: \.exerciseType)
            .compactMap { exercise, values -> (exercise: ExerciseType, cleanTarget: Int, dropTarget: Int?, unit: String, confidence: SignalConfidence, refs: [TrainingEvidenceRef], frictionCount: Int)? in
                let recent = Array(values.prefix(4))
                let cleanTargets = recent.compactMap(cleanTargetEstimate)
                let frictionCount = recent.filter { observation in
                    guard let clean = cleanTargetEstimate(observation) else { return false }
                    return clean < observation.achievedUnits || observation.hasFormFriction
                }.count
                guard cleanTargets.count >= 2, frictionCount > 0 else { return nil }
                let cleanTarget = max(cleanTargets.min() ?? 0, 1)
                let dropTarget = recent.compactMap(\.breakdownRepIndex).min()
                let unit = recent.first?.unitLabel ?? "reps"
                return (
                    exercise,
                    cleanTarget,
                    dropTarget,
                    unit,
                    frictionCount >= 2 ? .high : .medium,
                    evidenceRefs(from: recent, limit: 3),
                    frictionCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.frictionCount > rhs.frictionCount
                }
                return confidenceRank(lhs.confidence) < confidenceRank(rhs.confidence)
            }

        guard let candidate = candidates.first else { return }
        signals.append(
            UserTrainingSignal(
                type: .qualityCapacity,
                exerciseType: candidate.exercise,
                movementPattern: metadata(for: candidate.exercise)?.movementPattern,
                goal: profile.primaryGoal,
                title: "\(candidate.exercise.displayName) has a current clean target",
                value: "\(candidate.cleanTarget) clean \(candidate.unit)",
                comparisonValue: candidate.dropTarget.map { "form drop-off near rep \($0)" },
                delta: Double(candidate.cleanTarget),
                confidence: candidate.confidence,
                evidenceRefs: candidate.refs,
                createdAt: createdAt
            )
        )
    }

    func appendTargetFitSignal(
        to signals: inout [UserTrainingSignal],
        observations: [SignalSetObservation],
        history: [WorkoutSessionSummary],
        createdAt: Date,
        profile: UserProfile
    ) {
        guard let latestSummary = history.first else { return }
        let latest = observations.filter { $0.summary.id == latestSummary.id && $0.targetUnits != nil }
        guard !latest.isEmpty else { return }

        let candidates = latest.compactMap { observation -> (observation: SignalSetObservation, status: String, priority: Int, confidence: SignalConfidence)? in
            let targetRatio = observation.targetRatio ?? 1
            let form = observation.averageFormScore
            let hasReliableQuality = hasReliableQualitySample(observation)
            let frictionScore = (observation.restExtended ? 1 : 0) +
                (observation.qualityTrend == .faded ? 2 : 0) +
                min(observation.highSeverityCueCount, 3)

            if targetRatio < 0.95 ||
                observation.qualityTrend == .faded ||
                observation.highSeverityCueCount >= 2 ||
                (hasReliableQuality && (form.map { $0 < 78 } ?? false)) {
                return (observation, "too aggressive", 3, frictionScore >= 3 ? .high : .medium)
            }
            if let form,
               hasReliableQuality,
               targetRatio >= 1,
               form >= 88,
               observation.highSeverityCueCount == 0,
               observation.qualityTrend != .faded,
               !observation.restExtended {
                return (observation, "ready to progress", 2, form >= 92 ? .high : .medium)
            }
            if let form,
               hasReliableQuality,
               targetRatio >= 0.95,
               form >= 82,
               observation.highSeverityCueCount <= 1 {
                return (observation, "well matched", 1, .medium)
            }
            return nil
        }
        .sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return (lhs.observation.averageFormScore ?? 0) < (rhs.observation.averageFormScore ?? 0)
            }
            return lhs.priority > rhs.priority
        }

        guard let candidate = candidates.first else { return }
        let observation = candidate.observation
        let comparison = [
            observation.targetRatio.map { "\(Int((min($0, 1) * 100).rounded()))% target" },
            observation.averageFormScore.map(formatPercent)
        ]
        .compactMap { $0 }
        .joined(separator: " / ")

        signals.append(
            UserTrainingSignal(
                type: .targetFit,
                exerciseType: observation.exerciseType,
                movementPattern: metadata(for: observation.exerciseType)?.movementPattern,
                goal: profile.primaryGoal,
                title: "\(observation.exerciseType.displayName) target is \(candidate.status)",
                value: candidate.status,
                comparisonValue: comparison.isEmpty ? nil : comparison,
                delta: candidate.status == "ready to progress" ? 1 : (candidate.status == "too aggressive" ? -1 : 0),
                confidence: candidate.confidence,
                evidenceRefs: evidenceRefs(from: [observation], limit: 1),
                createdAt: createdAt
            )
        )
    }

    func appendMovementBalanceSignal(
        to signals: inout [UserTrainingSignal],
        observations: [SignalSetObservation],
        history: [WorkoutSessionSummary],
        createdAt: Date,
        profile: UserProfile
    ) {
        let recentSummaryIDs = Set(history.prefix(7).map(\.id))
        let recent = observations.filter { recentSummaryIDs.contains($0.summary.id) }
        guard recent.count >= 4,
              Set(recent.map(\.summary.id)).count >= 2
        else { return }

        let counts = recent.reduce(into: [MovementPattern: Int]()) { result, observation in
            guard let pattern = metadata(for: observation.exerciseType)?.movementPattern else { return }
            result[pattern, default: 0] += 1
        }
        let dominantSessionCount = dominantPatternSessionCount(in: recent, pattern: counts.sorted(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key.rawValue < rhs.key.rawValue }
            return lhs.value > rhs.value
        }).first?.key)
        guard let dominant = counts.sorted(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key.rawValue < rhs.key.rawValue }
            return lhs.value > rhs.value
        }).first,
            dominant.value >= 3,
            dominantSessionCount >= 2,
            Double(dominant.value) / Double(recent.count) >= 0.45,
            let missingPattern = underrepresentedPattern(after: dominant.key, counts: counts)
        else { return }

        signals.append(
            UserTrainingSignal(
                type: .movementBalance,
                movementPattern: missingPattern,
                goal: profile.primaryGoal,
                title: "\(movementPatternLabel(missingPattern)) is underrepresented recently",
                value: "\(movementPatternLabel(dominant.key))-heavy recent training",
                comparisonValue: "little \(movementPatternLabel(missingPattern)) work",
                delta: Double(dominant.value),
                confidence: dominant.value >= 5 ? .high : .medium,
                evidenceRefs: latestSessionRefs(history, limit: min(4, history.count)),
                createdAt: createdAt
            )
        )
    }

    func appendCueClusterSignal(
        to signals: inout [UserTrainingSignal],
        observations: [SignalSetObservation],
        history: [WorkoutSessionSummary],
        createdAt: Date,
        profile: UserProfile
    ) {
        let recentSummaryIDs = Set(trendEngine.recentCuePolicy.filteredSessions(history, now: createdAt).map(\.id))
        let recentObservations = observations.filter { recentSummaryIDs.contains($0.summary.id) }
        let buckets = cueClusterBuckets(from: recentObservations)
            .filter { bucket in
                let sessionCount = Set(bucket.observations.map { $0.summary.id }).count
                return Set(bucket.cueMessages.map(normalizedCueText)).count >= 2 &&
                    bucket.observations.count >= 2 &&
                    sessionCount >= 2
            }
            .sorted { lhs, rhs in
                if lhs.observations.count == rhs.observations.count {
                    return lhs.label < rhs.label
                }
                return lhs.observations.count > rhs.observations.count
            }

        guard let bucket = buckets.first else { return }
        let evidence = clusterCueEvidenceRefs(
            bucket.key,
            history: history,
            limit: 4,
            policy: trendEngine.recentCuePolicy,
            now: createdAt
        )
        guard evidence.count >= 2 else { return }

        let exercise = mostCommonExercise(in: bucket.observations.map(\.exerciseType))
        let sessionCount = Set(evidence.compactMap(\.summaryId)).count
        signals.append(
            UserTrainingSignal(
                type: .cueCluster,
                exerciseType: exercise,
                movementPattern: exercise.flatMap { metadata(for: $0)?.movementPattern },
                goal: profile.primaryGoal,
                title: "\(bucket.label) cues are clustering",
                value: bucket.label,
                comparisonValue: "\(evidence.count) related cue events",
                delta: Double(evidence.count),
                confidence: sessionCount >= 2 || evidence.count >= 3 ? .high : .medium,
                evidenceRefs: evidence,
                createdAt: createdAt
            )
        )
    }

    func appendRestResponseSignal(
        to signals: inout [UserTrainingSignal],
        observations: [SignalSetObservation],
        createdAt: Date,
        profile: UserProfile
    ) {
        let responses = restResponses(from: observations)
            .compactMap { response -> (response: RestResponseObservation, beforeScore: Double, afterScore: Double, helped: Bool, magnitude: Double)? in
                guard let beforeScore = response.before.averageFormScore,
                      let afterScore = response.after.averageFormScore
                else { return nil }

                let helped = beforeScore < 85 &&
                    ((response.delta >= 5 && afterScore >= 80) || (afterScore >= 85 && response.delta >= 0))
                let didNotRestore = beforeScore < 82 && afterScore < 82 && response.delta < 5
                guard helped || didNotRestore else { return nil }

                return (response, beforeScore, afterScore, helped, abs(response.delta))
            }
            .sorted {
                if $0.response.before.endedAt == $1.response.before.endedAt {
                    return $0.magnitude > $1.magnitude
                }
                return $0.response.before.endedAt > $1.response.before.endedAt
            }

        guard let result = responses.first else { return }
        let response = result.response

        signals.append(
            UserTrainingSignal(
                type: .restResponse,
                exerciseType: response.before.exerciseType,
                movementPattern: metadata(for: response.before.exerciseType)?.movementPattern,
                goal: profile.primaryGoal,
                title: result.helped ? "Extra rest helped \(response.before.exerciseType.displayName)" : "Extra rest did not restore \(response.before.exerciseType.displayName)",
                value: result.helped ? "rest helped quality rebound" : "rest did not restore quality",
                comparisonValue: "\(formatPercent(result.beforeScore)) to \(formatPercent(result.afterScore))",
                delta: response.delta,
                confidence: abs(response.delta) >= 8 ? .high : .medium,
                evidenceRefs: evidenceRefs(from: [response.before, response.after], limit: 2),
                createdAt: createdAt
            )
        )
    }

    func appendProgressionReadinessSignal(
        to signals: inout [UserTrainingSignal],
        observations: [SignalSetObservation],
        createdAt: Date,
        profile: UserProfile
    ) {
        let candidates = Dictionary(grouping: observations.filter { $0.targetUnits != nil && $0.hasScoredQuality }, by: \.exerciseType)
            .compactMap { exercise, values -> (exercise: ExerciseType, ready: Bool, confidence: SignalConfidence, refs: [TrainingEvidenceRef], score: Double)? in
                let recent = Array(values.prefix(3))
                guard recent.count >= 2 else { return nil }
                let gatePasses = recent.prefix(2).allSatisfy { observation in
                    (observation.targetRatio ?? 0) >= 1 &&
                        hasReliableQualitySample(observation) &&
                        (observation.averageFormScore ?? 0) >= 86 &&
                        observation.highSeverityCueCount == 0 &&
                        observation.qualityTrend != .faded &&
                        !observation.restExtended
                }
                if gatePasses {
                    return (exercise, true, (recent.first?.averageFormScore ?? 0) >= 92 ? .high : .medium, evidenceRefs(from: Array(recent.prefix(2)), limit: 2), recent.compactMap(\.averageFormScore).reduce(0, +))
                }

                let looksCloseButBlocked = recent.contains { observation in
                    hasReliableQualitySample(observation) &&
                    (observation.averageFormScore ?? 0) >= 82 &&
                        (observation.restExtended || observation.qualityTrend == .faded || observation.highSeverityCueCount > 0)
                }
                guard looksCloseButBlocked else { return nil }
                let friction = recent.reduce(0) { partial, observation in
                    partial + (observation.restExtended ? 1 : 0) + (observation.qualityTrend == .faded ? 2 : 0) + min(observation.highSeverityCueCount, 2)
                }
                return (exercise, false, friction >= 3 ? .high : .medium, evidenceRefs(from: recent, limit: 3), Double(friction))
            }
            .sorted { lhs, rhs in
                if lhs.ready == rhs.ready {
                    return lhs.score > rhs.score
                }
                return lhs.ready && !rhs.ready
            }

        guard let candidate = candidates.first else { return }
        signals.append(
            UserTrainingSignal(
                type: .progressionReadiness,
                exerciseType: candidate.exercise,
                movementPattern: metadata(for: candidate.exercise)?.movementPattern,
                goal: profile.primaryGoal,
                title: candidate.ready ? "\(candidate.exercise.displayName) progression is ready" : "\(candidate.exercise.displayName) progression should wait",
                value: candidate.ready ? "ready to progress" : "not ready to progress",
                comparisonValue: candidate.ready ? "two clean recent sets" : "quality gate still active",
                delta: candidate.ready ? 1 : -1,
                confidence: candidate.confidence,
                evidenceRefs: candidate.refs,
                createdAt: createdAt
            )
        )
    }

    func appendSessionFitSignal(
        to signals: inout [UserTrainingSignal],
        history: [WorkoutSessionSummary],
        createdAt: Date,
        profile: UserProfile
    ) {
        let recent = Array(history.prefix(6))
        guard recent.count >= 3 else { return }

        let cleanShortSessions = recent.filter { summary in
            summary.durationSeconds <= 12 * 60 &&
                (summary.completionPercent ?? 1) >= 0.95 &&
                (summary.averageFormScore ?? 0) >= 84 &&
                summary.totalHighSeverityCues == 0
        }
        let longerFrictionSessions = recent.filter { summary in
            summary.durationSeconds >= 15 * 60 &&
                ((summary.completionPercent ?? 1) < 0.95 || (summary.averageFormScore ?? 100) < 80 || summary.totalHighSeverityCues > 0)
        }
        guard cleanShortSessions.count >= 2 || (cleanShortSessions.count >= 1 && longerFrictionSessions.count >= 1) else { return }

        let evidence = latestSessionRefs(cleanShortSessions + longerFrictionSessions, limit: 3)
        guard !evidence.isEmpty else { return }
        signals.append(
            UserTrainingSignal(
                type: .sessionFit,
                goal: profile.primaryGoal,
                title: "Short sessions are fitting your training",
                value: "short sessions are working",
                comparisonValue: "\(cleanShortSessions.count) clean session\(cleanShortSessions.count == 1 ? "" : "s") under 12 min",
                delta: Double(cleanShortSessions.count),
                confidence: cleanShortSessions.count >= 3 ? .high : .medium,
                evidenceRefs: evidence,
                createdAt: createdAt
            )
        )
    }

    func appendExerciseReacquisitionSignal(
        to signals: inout [UserTrainingSignal],
        observations: [SignalSetObservation],
        createdAt: Date,
        profile: UserProfile
    ) {
        guard let latestSummary = observations.first?.summary else { return }
        let latestExercises = Set(observations.filter { $0.summary.id == latestSummary.id }.map(\.exerciseType))
        let candidates = latestExercises.compactMap { exercise -> (exercise: ExerciseType, gapDays: Int, previous: SignalSetObservation, latest: SignalSetObservation)? in
            guard let latest = observations.first(where: { $0.summary.id == latestSummary.id && $0.exerciseType == exercise }),
                  let previous = observations.first(where: { $0.summary.id != latestSummary.id && $0.exerciseType == exercise })
            else { return nil }
            let gapDays = Calendar(identifier: .gregorian).dateComponents([.day], from: previous.endedAt, to: latest.endedAt).day ?? 0
            guard gapDays >= 14 else { return nil }
            return (exercise, gapDays, previous, latest)
        }
        .sorted { lhs, rhs in
            lhs.gapDays > rhs.gapDays
        }

        guard let candidate = candidates.first else { return }
        let previousTarget = cleanTargetEstimate(candidate.previous)
            .map { "\($0) clean \(candidate.previous.unitLabel)" }
        signals.append(
            UserTrainingSignal(
                type: .exerciseReacquisition,
                exerciseType: candidate.exercise,
                movementPattern: metadata(for: candidate.exercise)?.movementPattern,
                goal: profile.primaryGoal,
                title: "\(candidate.exercise.displayName) is back after a gap",
                value: "\(candidate.gapDays) days since last exposure",
                comparisonValue: previousTarget,
                delta: Double(candidate.gapDays),
                confidence: candidate.gapDays >= 21 ? .high : .medium,
                evidenceRefs: evidenceRefs(from: [candidate.latest, candidate.previous], limit: 2),
                createdAt: createdAt
            )
        )
    }

    func appendExercisePreferenceSignal(
        to signals: inout [UserTrainingSignal],
        observations: [SignalSetObservation],
        createdAt: Date,
        profile: UserProfile
    ) {
        let candidates = Dictionary(grouping: observations, by: \.exerciseType)
            .compactMap { exercise, values -> (exercise: ExerciseType, score: Int, value: String, refs: [TrainingEvidenceRef], confidence: SignalConfidence)? in
                let recent = Array(values.prefix(5))
                let sessionCount = Set(recent.map { $0.summary.id }).count
                guard sessionCount >= 2 else { return nil }
                let rest = recent.filter(\.restExtended).count
                let camera = recent.reduce(0) { $0 + $1.cameraFrictionCueCount }
                let lowForm = recent.filter { ($0.averageFormScore ?? 100) < 76 }.count
                let faded = recent.filter { $0.qualityTrend == .faded }.count
                let score = rest + min(camera, 3) + lowForm * 2 + faded * 2
                guard score >= 4 else { return nil }
                return (
                    exercise,
                    score,
                    frictionSummary(rest: rest, camera: camera, lowForm: lowForm, faded: faded),
                    evidenceRefs(from: recent, limit: 4),
                    score >= 6 ? .high : .medium
                )
            }
            .sorted { lhs, rhs in
                lhs.score > rhs.score
            }

        guard let candidate = candidates.first else { return }
        signals.append(
            UserTrainingSignal(
                type: .exercisePreference,
                exerciseType: candidate.exercise,
                movementPattern: metadata(for: candidate.exercise)?.movementPattern,
                goal: profile.primaryGoal,
                title: "\(candidate.exercise.displayName) is not fitting cleanly right now",
                value: candidate.value,
                comparisonValue: "repeated friction across sessions",
                delta: Double(candidate.score),
                confidence: candidate.confidence,
                evidenceRefs: candidate.refs,
                createdAt: createdAt
            )
        )
    }

    func appendQualityPRSignal(
        to signals: inout [UserTrainingSignal],
        observations: [SignalSetObservation],
        createdAt: Date,
        profile: UserProfile
    ) {
        guard let latestSummary = observations.first?.summary else { return }
        let latest = observations.filter { $0.summary.id == latestSummary.id && $0.averageFormScore != nil && $0.scoredRepCount >= minReliableScoredReps(for: $0) }
        let candidates = latest.compactMap { observation -> (observation: SignalSetObservation, value: String, comparison: String, delta: Double, confidence: SignalConfidence)? in
            let previous = observations.filter {
                $0.summary.id != latestSummary.id &&
                    $0.exerciseType == observation.exerciseType &&
                    $0.scoredRepCount >= minReliableScoredReps(for: $0)
            }
            guard !previous.isEmpty else { return nil }
            let latestScore = observation.averageFormScore ?? 0
            if let previousBest = previous.compactMap(\.averageFormScore).max(),
               latestScore >= 90,
               latestScore >= previousBest + 2,
               observation.highSeverityCueCount == 0 {
                return (
                    observation,
                    "best clean set \(formatPercent(latestScore))",
                    "previous best \(formatPercent(previousBest))",
                    latestScore - previousBest,
                    latestScore >= 94 ? .high : .medium
                )
            }

            let previousExcellent = previous.map(\.excellentFormReps).max() ?? 0
            let hasPreviousRepQuality = previous.contains { $0.setSummary.qualitySummary != nil || !$0.setSummary.repQualityEvents.isEmpty }
            if hasPreviousRepQuality,
               observation.excellentFormReps >= 3,
               observation.excellentFormReps > previousExcellent {
                return (
                    observation,
                    "\(observation.excellentFormReps) excellent-form reps",
                    "previous best \(previousExcellent)",
                    Double(observation.excellentFormReps - previousExcellent),
                    .medium
                )
            }
            return nil
        }
        .sorted { lhs, rhs in
            lhs.delta > rhs.delta
        }

        guard let candidate = candidates.first else { return }
        signals.append(
            UserTrainingSignal(
                type: .qualityPR,
                exerciseType: candidate.observation.exerciseType,
                movementPattern: metadata(for: candidate.observation.exerciseType)?.movementPattern,
                goal: profile.primaryGoal,
                title: "\(candidate.observation.exerciseType.displayName) hit a quality PR",
                value: candidate.value,
                comparisonValue: candidate.comparison,
                delta: candidate.delta,
                confidence: candidate.confidence,
                evidenceRefs: evidenceRefs(from: [candidate.observation], limit: 1),
                createdAt: createdAt
            )
        )
    }

    func latestSessionRefs(
        _ history: [WorkoutSessionSummary],
        limit: Int
    ) -> [TrainingEvidenceRef] {
        history.prefix(max(limit, 0)).map { summary in
            TrainingEvidenceRef(
                summaryId: summary.id,
                date: summary.endedAt,
                label: summary.title
            )
        }
    }

    func exerciseEvidenceRefs(
        _ exerciseType: ExerciseType,
        history: [WorkoutSessionSummary],
        limit: Int
    ) -> [TrainingEvidenceRef] {
        var refs: [TrainingEvidenceRef] = []
        for summary in history {
            for setSummary in summary.exerciseSummaries where setSummary.exerciseType == exerciseType {
                refs.append(
                    TrainingEvidenceRef(
                        summaryId: summary.id,
                        exerciseType: exerciseType,
                        setIndex: setSummary.setIndex,
                        date: summary.endedAt,
                        label: setSummaryLabel(setSummary, fallbackTitle: summary.title)
                    )
                )
            }
            if refs.count >= limit { break }
        }
        return Array(refs.prefix(limit))
    }

    func cueEvidenceRefs(
        _ cue: String,
        history: [WorkoutSessionSummary],
        limit: Int,
        policy: TrendWindowPolicy,
        now: Date
    ) -> [TrainingEvidenceRef] {
        let normalizedCue = CueNormalizer.normalize(cue)
        guard !normalizedCue.isEmpty else { return [] }

        var refs: [TrainingEvidenceRef] = []
        for summary in policy.filteredSessions(history, now: now) {
            for setSummary in summary.exerciseSummaries {
                for event in setSummary.cueEvents where CueNormalizer.normalize(event.cueMessage) == normalizedCue && policy.contains(event.timestamp, now: now) {
                    refs.append(
                        TrainingEvidenceRef(
                            summaryId: summary.id,
                            exerciseType: setSummary.exerciseType,
                            setIndex: event.setIndex ?? setSummary.setIndex,
                            repIndex: event.repIndex,
                            date: event.timestamp,
                            label: event.cueMessage
                        )
                    )
                }
                for event in setSummary.repQualityEvents {
                    guard let cueMessage = event.cueMessageNearRep,
                          CueNormalizer.normalize(cueMessage) == normalizedCue,
                          policy.contains(event.timestamp, now: now)
                    else { continue }

                    refs.append(
                        TrainingEvidenceRef(
                            summaryId: summary.id,
                            exerciseType: setSummary.exerciseType,
                            setIndex: event.setIndex ?? setSummary.setIndex,
                            repIndex: event.repIndex,
                            date: event.timestamp,
                            label: cueMessage
                        )
                    )
                }
            }
            if refs.count >= limit { break }
        }
        return Array(refs.prefix(limit))
    }

    func cameraFrictionEvidenceRefs(
        history: [WorkoutSessionSummary],
        limit: Int,
        policy: TrendWindowPolicy,
        now: Date
    ) -> [TrainingEvidenceRef] {
        var refs: [TrainingEvidenceRef] = []
        for summary in policy.filteredSessions(history, now: now) {
            for setSummary in summary.exerciseSummaries {
                for event in setSummary.cueEvents where TrendEngine.isCameraFrictionCue(event.cueMessage) && policy.contains(event.timestamp, now: now) {
                    refs.append(
                        TrainingEvidenceRef(
                            summaryId: summary.id,
                            exerciseType: setSummary.exerciseType,
                            setIndex: event.setIndex ?? setSummary.setIndex,
                            repIndex: event.repIndex,
                            date: event.timestamp,
                            label: event.cueMessage
                        )
                    )
                }
                for event in setSummary.repQualityEvents {
                    guard let cue = event.cueMessageNearRep,
                          TrendEngine.isCameraFrictionCue(cue),
                          policy.contains(event.timestamp, now: now)
                    else { continue }
                    refs.append(
                        TrainingEvidenceRef(
                            summaryId: summary.id,
                            exerciseType: setSummary.exerciseType,
                            setIndex: event.setIndex ?? setSummary.setIndex,
                            repIndex: event.repIndex,
                            date: event.timestamp,
                            label: cue
                        )
                    )
                }
            }
            if refs.count >= limit { break }
        }
        return Array(refs.prefix(limit))
    }

    func setObservations(from history: [WorkoutSessionSummary]) -> [SignalSetObservation] {
        history.flatMap { summary in
            summary.exerciseSummaries.map { setSummary in
                let quality = setSummary.qualitySummary
                let repScores = setSummary.repQualityEvents.compactMap(\.formScore).map(Double.init)
                let scoredRepCount = max(quality?.totalScoredReps ?? 0, repScores.count)
                let averageForm = quality?.averageFormScore
                    ?? setSummary.averageFormScore
                    ?? average(repScores)
                let cueMessages = setSummary.cueEvents.map(\.cueMessage) +
                    setSummary.repQualityEvents.compactMap(\.cueMessageNearRep)
                let units = trainingUnits(for: setSummary)

                return SignalSetObservation(
                    summary: summary,
                    setSummary: setSummary,
                    exerciseType: setSummary.exerciseType,
                    setIndex: setSummary.setIndex,
                    endedAt: summary.endedAt,
                    achievedUnits: units.achieved,
                    targetUnits: units.target,
                    unitLabel: units.unitLabel,
                    averageFormScore: averageForm,
                    scoredRepCount: scoredRepCount,
                    qualityTrend: quality?.qualityTrend ?? .unknown,
                    highSeverityCueCount: quality?.highSeverityCueCount ?? highSeverityCueCount(in: setSummary),
                    breakdownRepIndex: quality?.breakdownRepIndex,
                    excellentFormReps: quality?.excellentFormReps ?? setSummary.repQualityEvents.filter { ($0.formScore ?? -1) >= 90 }.count,
                    restExtended: setSummary.restExtended,
                    skipped: setSummary.skipped,
                    cueMessages: cueMessages,
                    cameraFrictionCueCount: cueMessages.filter(TrendEngine.isCameraFrictionCue).count
                )
            }
        }
    }

    func firstSetObservation(
        in summary: WorkoutSessionSummary,
        observations: [SignalSetObservation]
    ) -> SignalSetObservation? {
        observations
            .filter { $0.summary.id == summary.id }
            .sorted(by: setObservationOrder)
            .first
    }

    func firstSetObservationsByExercise(
        in summary: WorkoutSessionSummary,
        observations: [SignalSetObservation]
    ) -> [ExerciseType: SignalSetObservation] {
        Dictionary(grouping: observations.filter { $0.summary.id == summary.id }, by: \.exerciseType)
            .compactMapValues { values in
                values.sorted(by: setObservationOrder).first
            }
    }

    func setObservationOrder(_ lhs: SignalSetObservation, _ rhs: SignalSetObservation) -> Bool {
        let leftSet = lhs.setIndex ?? Int.max
        let rightSet = rhs.setIndex ?? Int.max
        if leftSet == rightSet {
            return lhs.exerciseType.rawValue < rhs.exerciseType.rawValue
        }
        return leftSet < rightSet
    }

    func trainingUnits(for setSummary: ExerciseSetSummary) -> (achieved: Int, target: Int?, unitLabel: String) {
        switch setSummary.target {
        case .reps(let target):
            return (setSummary.achievedReps, target, "reps")
        case .hold(let seconds):
            return (setSummary.achievedHoldSeconds, seconds, "seconds")
        case .timed(let seconds):
            return (setSummary.durationSeconds ?? setSummary.achievedHoldSeconds, seconds, "seconds")
        case .amrap:
            return (setSummary.achievedReps, nil, "reps")
        case .open, nil:
            if setSummary.achievedHoldSeconds > 0 {
                return (setSummary.achievedHoldSeconds, nil, "seconds")
            }
            return (setSummary.achievedReps, nil, "reps")
        }
    }

    func highSeverityCueCount(in setSummary: ExerciseSetSummary) -> Int {
        let cueEvents = setSummary.cueEvents.filter { $0.severity >= .warning }.count
        let repEvents = setSummary.repQualityEvents.filter {
            guard let severity = $0.cueSeverityNearRep else { return false }
            return severity >= .warning
        }.count
        return cueEvents + repEvents
    }

    func cleanTargetEstimate(_ observation: SignalSetObservation) -> Int? {
        guard observation.achievedUnits > 0 else { return nil }
        if observation.unitLabel == "reps" {
            if let breakdownRepIndex = observation.breakdownRepIndex, breakdownRepIndex > 1 {
                return max(breakdownRepIndex - 1, 1)
            }
            if observation.qualityTrend == .faded, observation.achievedUnits > 2 {
                if let averageFormScore = observation.averageFormScore,
                   averageFormScore < 78 {
                    return nil
                }
                return max(observation.achievedUnits - 1, 1)
            }
        }
        guard observation.highSeverityCueCount == 0,
              (observation.averageFormScore ?? 0) >= 85
        else { return nil }
        return observation.achievedUnits
    }

    func evidenceRefs(
        from observations: [SignalSetObservation],
        limit: Int
    ) -> [TrainingEvidenceRef] {
        observations.prefix(max(limit, 0)).map { observation in
            TrainingEvidenceRef(
                summaryId: observation.summary.id,
                exerciseType: observation.exerciseType,
                setIndex: observation.setIndex,
                date: observation.endedAt,
                label: setSummaryLabel(observation.setSummary, fallbackTitle: observation.summary.title)
            )
        }
    }

    func cueClusterBuckets(from observations: [SignalSetObservation]) -> [CueClusterBucket] {
        let items = observations.flatMap { observation in
            observation.cueMessages.compactMap { cue -> (key: String, label: String, cue: String, observation: SignalSetObservation)? in
                let cluster = cueCluster(for: cue)
                guard cluster != .other,
                      !TrendEngine.isCameraFrictionCue(cue)
                else { return nil }
                return (cluster.rawValue, cluster.label, cue, observation)
            }
        }
        let grouped = Dictionary(grouping: items, by: \.key)
        return grouped.compactMap { key, values in
            guard let label = values.first?.label else { return nil }
            return CueClusterBucket(
                key: key,
                label: label,
                cueMessages: values.map(\.cue),
                observations: values.map(\.observation)
            )
        }
    }

    func normalizedCueText(_ cue: String) -> String {
        CueNormalizer.normalize(cue)
    }

    func clusterCueEvidenceRefs(
        _ clusterKey: String,
        history: [WorkoutSessionSummary],
        limit: Int,
        policy: TrendWindowPolicy,
        now: Date
    ) -> [TrainingEvidenceRef] {
        var refs: [TrainingEvidenceRef] = []
        for summary in policy.filteredSessions(history, now: now) {
            for setSummary in summary.exerciseSummaries {
                for event in setSummary.cueEvents {
                    guard !TrendEngine.isCameraFrictionCue(event.cueMessage),
                          cueCluster(for: event.cueMessage).rawValue == clusterKey,
                          policy.contains(event.timestamp, now: now)
                    else { continue }
                    refs.append(
                        TrainingEvidenceRef(
                            summaryId: summary.id,
                            exerciseType: setSummary.exerciseType,
                            setIndex: event.setIndex ?? setSummary.setIndex,
                            repIndex: event.repIndex,
                            date: event.timestamp,
                            label: event.cueMessage
                        )
                    )
                }
                for event in setSummary.repQualityEvents {
                    guard let cue = event.cueMessageNearRep,
                          !TrendEngine.isCameraFrictionCue(cue),
                          cueCluster(for: cue).rawValue == clusterKey,
                          policy.contains(event.timestamp, now: now)
                    else { continue }
                    refs.append(
                        TrainingEvidenceRef(
                            summaryId: summary.id,
                            exerciseType: setSummary.exerciseType,
                            setIndex: event.setIndex ?? setSummary.setIndex,
                            repIndex: event.repIndex,
                            date: event.timestamp,
                            label: cue
                        )
                    )
                }
            }
            if refs.count >= limit { break }
        }
        return Array(refs.prefix(limit))
    }

    func cueCluster(for cue: String) -> CueCluster {
        CueClusterTaxonomy.cluster(for: CueNormalizer.normalize(cue))
    }

    func restResponses(from observations: [SignalSetObservation]) -> [RestResponseObservation] {
        Dictionary(grouping: observations, by: { $0.summary.id })
            .values
            .flatMap { summaryObservations -> [RestResponseObservation] in
                let ordered = summaryObservations.sorted {
                    let left = $0.setIndex ?? Int.max
                    let right = $1.setIndex ?? Int.max
                    if left == right { return $0.exerciseType.rawValue < $1.exerciseType.rawValue }
                    return left < right
                }
                var values: [RestResponseObservation] = []
                for index in ordered.indices {
                    let before = ordered[index]
                    guard before.restExtended,
                          let beforeScore = before.averageFormScore
                    else { continue }
                    let nextIndex = ordered.index(after: index)
                    guard nextIndex < ordered.endIndex else { continue }
                    let after = ordered[nextIndex]
                    guard after.exerciseType == before.exerciseType,
                          let afterScore = after.averageFormScore
                    else { continue }
                    values.append(RestResponseObservation(before: before, after: after, delta: afterScore - beforeScore))
                }
                return values
            }
    }

    func underrepresentedPattern(
        after dominantPattern: MovementPattern,
        counts: [MovementPattern: Int]
    ) -> MovementPattern? {
        let preferred: [MovementPattern]
        switch dominantPattern {
        case .squat, .lunge:
            preferred = [.hinge, .balance, .mobility]
        case .hinge:
            preferred = [.squat, .coreAntiExtension, .mobility]
        case .push:
            preferred = [.pull, .coreAntiExtension, .mobility]
        case .pull:
            preferred = [.push, .coreAntiExtension, .mobility]
        case .coreFlexion, .coreAntiExtension:
            preferred = [.coreRotation, .hinge, .mobility]
        case .coreRotation:
            preferred = [.coreAntiExtension, .balance, .mobility]
        case .cardio:
            preferred = [.mobility, .coreAntiExtension, .balance]
        case .balance, .mobility, .yogaHold, .carry:
            preferred = [.squat, .push, .hinge]
        }
        return preferred.first { (counts[$0] ?? 0) == 0 }
    }

    func movementPatternLabel(_ pattern: MovementPattern) -> String {
        switch pattern {
        case .squat:
            return "Squat"
        case .hinge:
            return "Hinge"
        case .lunge:
            return "Lunge"
        case .push:
            return "Push"
        case .pull:
            return "Pull"
        case .carry:
            return "Carry"
        case .coreFlexion:
            return "Core flexion"
        case .coreAntiExtension:
            return "Core stability"
        case .coreRotation:
            return "Core rotation"
        case .balance:
            return "Balance"
        case .mobility:
            return "Mobility"
        case .cardio:
            return "Cardio"
        case .yogaHold:
            return "Yoga hold"
        }
    }

    func frictionSummary(
        rest: Int,
        camera: Int,
        lowForm: Int,
        faded: Int
    ) -> String {
        var pieces: [String] = []
        if rest > 0 {
            pieces.append("\(rest) extended rest\(rest == 1 ? "" : "s")")
        }
        if lowForm > 0 {
            pieces.append("\(lowForm) low-form set\(lowForm == 1 ? "" : "s")")
        }
        if faded > 0 {
            pieces.append("\(faded) late form fade\(faded == 1 ? "" : "s")")
        }
        if camera > 0 {
            pieces.append("\(camera) setup cue\(camera == 1 ? "" : "s")")
        }
        return pieces.isEmpty ? "repeated friction" : pieces.joined(separator: ", ")
    }

    func dominantPatternSessionCount(
        in observations: [SignalSetObservation],
        pattern: MovementPattern?
    ) -> Int {
        guard let pattern else { return 0 }
        return Set(observations.filter { metadata(for: $0.exerciseType)?.movementPattern == pattern }.map(\.summary.id)).count
    }

    func minReliableScoredReps(for observation: SignalSetObservation) -> Int {
        guard observation.unitLabel == "reps" else { return 1 }
        return min(3, max(observation.achievedUnits, 1))
    }

    func hasReliableQualitySample(_ observation: SignalSetObservation) -> Bool {
        observation.scoredRepCount >= minReliableScoredReps(for: observation)
    }

    func mostCommonExercise(in exercises: [ExerciseType]) -> ExerciseType? {
        exercises
            .reduce(into: [ExerciseType: Int]()) { counts, exercise in
                counts[exercise, default: 0] += 1
            }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.rawValue < rhs.key.rawValue
                }
                return lhs.value > rhs.value
            }
            .first?
            .key
    }

    func setSummaryLabel(
        _ setSummary: ExerciseSetSummary,
        fallbackTitle: String
    ) -> String {
        var pieces = [setSummary.exerciseType.displayName]
        if let setIndex = setSummary.setIndex {
            pieces.append("set \(setIndex + 1)")
        }
        if let score = setSummary.averageFormScore {
            pieces.append(formatPercent(score))
        } else if setSummary.achievedReps > 0 {
            pieces.append("\(setSummary.achievedReps) reps")
        } else if setSummary.achievedHoldSeconds > 0 {
            pieces.append("\(setSummary.achievedHoldSeconds)s hold")
        }
        return pieces.isEmpty ? fallbackTitle : pieces.joined(separator: " / ")
    }

    func struggleValue(for trend: ExerciseTrendSummary) -> String {
        var parts: [String] = []
        if trend.formDropOffSetCount > 0 {
            parts.append("\(trend.formDropOffSetCount) form drop-off set\(trend.formDropOffSetCount == 1 ? "" : "s")")
        }
        if trend.highSeverityCueCount > 0 {
            parts.append("\(trend.highSeverityCueCount) warning cue\(trend.highSeverityCueCount == 1 ? "" : "s")")
        }
        if trend.skippedSetCount > 0 {
            parts.append("\(trend.skippedSetCount) early rest skip\(trend.skippedSetCount == 1 ? "" : "s")")
        }
        if trend.restExtendedSetCount > 0 {
            parts.append("\(trend.restExtendedSetCount) extended rest\(trend.restExtendedSetCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "repeated friction" : parts.joined(separator: ", ")
    }

    func repeatExerciseTitle(for exercise: ExerciseType, delta: Double) -> String {
        if delta >= 2 {
            return "\(exercise.displayName) set 1 improved on repeat"
        }
        if delta <= -2 {
            return "\(exercise.displayName) set 1 needs the same focus"
        }
        return "\(exercise.displayName) set 1 repeated near baseline"
    }

    func trendDirection(
        delta: Double,
        meaningfulThreshold: Double,
        positive: TrainingTrendDirection,
        negative: TrainingTrendDirection
    ) -> TrainingTrendDirection {
        if delta >= meaningfulThreshold { return positive }
        if delta <= -meaningfulThreshold { return negative }
        return .steady
    }

    func limitationTag(_ limitation: PhysicalLimitation) -> ContraindicationTag {
        switch limitation {
        case .kneeSensitive:
            return .kneeSensitive
        case .shoulderSensitive:
            return .shoulderSensitive
        case .wristSensitive:
            return .wristSensitive
        case .lowerBackSensitive:
            return .lowerBackSensitive
        case .balanceSensitive:
            return .highImpact
        case .highImpactSensitive:
            return .highImpact
        }
    }

    func metadata(for exerciseType: ExerciseType) -> ExercisePlanMetadata? {
        ExerciseMetadataCatalog.metadata(for: exerciseType)
    }

    func deduplicated(_ signals: [UserTrainingSignal]) -> [UserTrainingSignal] {
        var seen = Set<String>()
        var values: [UserTrainingSignal] = []
        for signal in signals where seen.insert(signal.id).inserted {
            values.append(signal)
        }
        return values
    }

    func signalSort(_ lhs: UserTrainingSignal, _ rhs: UserTrainingSignal) -> Bool {
        let lhsRank = confidenceRank(lhs.confidence)
        let rhsRank = confidenceRank(rhs.confidence)
        if lhsRank == rhsRank {
            if lhs.type.rawValue == rhs.type.rawValue {
                return lhs.title < rhs.title
            }
            return lhs.type.rawValue < rhs.type.rawValue
        }
        return lhsRank < rhsRank
    }

    func confidenceRank(_ confidence: SignalConfidence) -> Int {
        switch confidence {
        case .high:
            return 0
        case .medium:
            return 1
        case .low:
            return 2
        }
    }

    func formatPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    func formatDelta(_ value: Double, suffix: String = "") -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(formatNumber(value))\(suffix)"
    }

    func dayLabel(_ count: Int) -> String {
        count == 1 ? "day" : "days"
    }

    func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
