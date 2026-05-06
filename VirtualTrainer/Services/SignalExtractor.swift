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
        trophies: TrophyProgressSnapshot
    ) -> [UserTrainingSignal] {
        guard snapshot.totalWorkouts > 0 else { return [] }

        let sortedHistory = history.sorted {
            if $0.endedAt == $1.endedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.endedAt > $1.endedAt
        }

        var signals: [UserTrainingSignal] = []
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
            profile: profile
        )
        appendVolumeSignals(
            to: &signals,
            history: sortedHistory,
            profile: profile,
            createdAt: snapshot.generatedAt
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
            profile: profile
        )
        appendFatigueSignal(
            to: &signals,
            snapshot: snapshot,
            history: sortedHistory,
            profile: profile
        )

        return deduplicated(signals).sorted(by: signalSort)
    }
}

nonisolated private extension SignalExtractor {
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
        profile: UserProfile
    ) {
        let comparison = trendEngine.threeWorkoutComparison(history: history, metric: .formScore)
        guard let delta = comparison.delta,
              let latest = comparison.latestValue,
              let previous = comparison.comparisonValue
        else { return }

        if snapshot.overallFormTrend == .improving {
            signals.append(
                UserTrainingSignal(
                    type: .formImprovement,
                    goal: profile.primaryGoal,
                    title: "Average form improved over recent workouts",
                    value: formatPercent(latest),
                    comparisonValue: formatPercent(previous),
                    delta: delta,
                    confidence: abs(delta) >= 8 ? .high : .medium,
                    evidenceRefs: latestSessionRefs(history, limit: 6),
                    createdAt: snapshot.generatedAt
                )
            )
        } else if snapshot.overallFormTrend == .declining {
            signals.append(
                UserTrainingSignal(
                    type: .formDropOff,
                    goal: profile.primaryGoal,
                    title: "Average form is lower than the previous comparable block",
                    value: formatPercent(latest),
                    comparisonValue: formatPercent(previous),
                    delta: delta,
                    confidence: abs(delta) >= 8 ? .high : .medium,
                    evidenceRefs: latestSessionRefs(history, limit: 6),
                    createdAt: snapshot.generatedAt
                )
            )
        }
    }

    func appendVolumeSignals(
        to signals: inout [UserTrainingSignal],
        history: [WorkoutSessionSummary],
        profile: UserProfile,
        createdAt: Date
    ) {
        let comparison = trendEngine.threeWorkoutComparison(history: history, metric: .volumeUnits)
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
                confidence: abs(delta) >= 18 ? .high : .medium,
                evidenceRefs: latestSessionRefs(history, limit: 6),
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
        let evidence = cueEvidenceRefs(cue, history: history, limit: 4)
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
                    title: "\(skippedTrend.exerciseType.displayName) was skipped more than once",
                    value: "\(skippedTrend.skippedSetCount) skipped sets",
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
        profile: UserProfile
    ) {
        guard snapshot.cameraFrictionCount >= 2 else { return }
        let evidence = cameraFrictionEvidenceRefs(history: history, limit: 4)
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
        limit: Int
    ) -> [TrainingEvidenceRef] {
        var refs: [TrainingEvidenceRef] = []
        for summary in history {
            for setSummary in summary.exerciseSummaries {
                for event in setSummary.cueEvents where event.cueMessage == cue {
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
                for event in setSummary.repQualityEvents where event.cueMessageNearRep == cue {
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

    func cameraFrictionEvidenceRefs(
        history: [WorkoutSessionSummary],
        limit: Int
    ) -> [TrainingEvidenceRef] {
        var refs: [TrainingEvidenceRef] = []
        for summary in history {
            for setSummary in summary.exerciseSummaries {
                for event in setSummary.cueEvents where TrendEngine.isCameraFrictionCue(event.cueMessage) {
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
                          TrendEngine.isCameraFrictionCue(cue)
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
            parts.append("\(trend.skippedSetCount) skipped set\(trend.skippedSetCount == 1 ? "" : "s")")
        }
        if trend.restExtendedSetCount > 0 {
            parts.append("\(trend.restExtendedSetCount) extended rest\(trend.restExtendedSetCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "repeated friction" : parts.joined(separator: ", ")
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
}
