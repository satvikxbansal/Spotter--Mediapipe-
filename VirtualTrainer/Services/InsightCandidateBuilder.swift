import Foundation

nonisolated struct InsightCandidateBuilder {
    func buildPlanCandidates(
        profile: UserProfile,
        plan: WorkoutPlanV2,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophyProgress: TrophyProgressSnapshot
    ) -> [InsightCandidate] {
        var candidates: [InsightCandidate] = []
        let planExercises = Set(plan.blocks.flatMap(\.exercises).map(\.exerciseType))
        let createdAt = trendSnapshot.generatedAt

        appendLimitationAwarePlanCandidate(
            to: &candidates,
            profile: profile,
            plan: plan,
            createdAt: createdAt
        )
        appendSmartStartCandidate(
            to: &candidates,
            profile: profile,
            plan: plan,
            trendSnapshot: trendSnapshot,
            createdAt: createdAt
        )

        for signal in signals {
            switch signal.type {
            case .fatigue, .cameraFriction, .movementBalance, .sessionFit:
                if let candidate = trendCandidate(
                    from: signal,
                    surfaces: [.workoutPreview],
                    createdAt: createdAt,
                    planExercises: planExercises,
                    planTitle: plan.title
                ) {
                    candidates.append(candidate)
                }
            case .restBehavior, .skippedExercise, .planFit, .qualityCapacity, .targetFit, .cueCluster, .restResponse, .progressionReadiness, .exerciseReacquisition, .exercisePreference, .qualityPR:
                guard planContainsSignalExercise(signal, planExercises: planExercises) else {
                    continue
                }
                if let candidate = trendCandidate(
                    from: signal,
                    surfaces: [.workoutPreview],
                    createdAt: createdAt,
                    planExercises: planExercises,
                    planTitle: plan.title
                ) {
                    candidates.append(candidate)
                }
            case .formImprovement, .exerciseMastery, .formDropOff, .exerciseStruggle, .repeatedCue:
                guard planContainsSignalExercise(signal, planExercises: planExercises) else {
                    continue
                }
                if let candidate = trendCandidate(
                    from: signal,
                    surfaces: [.workoutPreview],
                    createdAt: createdAt,
                    planExercises: planExercises,
                    planTitle: plan.title
                ) {
                    candidates.append(candidate)
                }
            case .repCleanlinessIntro, .repeatExerciseProgress:
                guard planContainsSignalExercise(signal, planExercises: planExercises) else {
                    continue
                }
                if let candidate = trendCandidate(
                    from: signal,
                    surfaces: [.workoutPreview],
                    createdAt: createdAt,
                    planExercises: planExercises,
                    planTitle: plan.title
                ) {
                    candidates.append(candidate)
                }
            case .firstSession, .setupQuality, .personalBaseline:
                if let candidate = trendCandidate(
                    from: signal,
                    surfaces: [.workoutPreview],
                    createdAt: createdAt,
                    planExercises: planExercises,
                    planTitle: plan.title
                ) {
                    candidates.append(candidate)
                }
            case .consistency, .completion, .trophyProximity, .volumeIncrease:
                if let candidate = trendCandidate(
                    from: signal,
                    surfaces: [.workoutPreview],
                    createdAt: createdAt,
                    planExercises: planExercises,
                    planTitle: plan.title
                ) {
                    candidates.append(candidate)
                }
            case .volumeDrop:
                continue
            }
        }

        if let trophyCandidate = trophyCandidate(
            from: trophyProgress,
            profile: profile,
            surfaces: [.workoutPreview],
            createdAt: createdAt
        ) {
            candidates.append(trophyCandidate)
        }

        return cappedBootstrapCandidates(evidenceBacked(candidates), surface: .workoutPreview)
    }

    func buildWorkoutCandidates(
        summary: WorkoutSessionSummary,
        plan: WorkoutPlanV2?,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal]
    ) -> [InsightCandidate] {
        var candidates: [InsightCandidate] = []
        appendWorkoutFormBreakdowns(to: &candidates, summary: summary)
        appendWorkoutFormGrowth(to: &candidates, summary: summary)
        appendRepeatedCueCandidate(to: &candidates, summary: summary)
        appendCompletionQualityCandidate(to: &candidates, summary: summary, plan: plan)
        appendRestAndSkippedCandidates(to: &candidates, summary: summary)

        for signal in signals where signal.type == .trophyProximity {
            if let candidate = trendCandidate(
                from: signal,
                surfaces: [.workoutSummary],
                createdAt: trendSnapshot.generatedAt,
                planExercises: nil,
                planTitle: plan?.title
            ) {
                candidates.append(candidate)
            }
        }

        return evidenceBacked(candidates)
    }

    func buildDayOverDayCandidates(
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        profile: UserProfile
    ) -> [InsightCandidate] {
        guard trendSnapshot.totalWorkouts > 0 else { return [] }
        return cappedBootstrapCandidates(evidenceBacked(
            signals.compactMap {
                trendCandidate(
                    from: $0,
                    surfaces: [.dashboard, .profile],
                    createdAt: trendSnapshot.generatedAt,
                    planExercises: nil,
                    planTitle: nil
                )
            }
        ), surface: .profile)
    }

    func buildDashboardCandidates(
        profile: UserProfile,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophies: TrophyProgressSnapshot
    ) -> [InsightCandidate] {
        guard trendSnapshot.totalWorkouts > 0 else { return [] }
        var candidates = signals.compactMap {
            trendCandidate(
                from: $0,
                surfaces: [.dashboard],
                createdAt: trendSnapshot.generatedAt,
                planExercises: nil,
                planTitle: nil
            )
        }

        if let trophy = trophyCandidate(
            from: trophies,
            profile: profile,
            surfaces: [.dashboard],
            createdAt: trendSnapshot.generatedAt
        ) {
            candidates.append(trophy)
        }

        return cappedBootstrapCandidates(evidenceBacked(candidates), surface: .dashboard)
    }

    func buildProfileCandidates(
        profile: UserProfile,
        trendSnapshot: UserTrainingTrendSnapshot,
        signals: [UserTrainingSignal],
        trophies: TrophyProgressSnapshot
    ) -> [InsightCandidate] {
        guard trendSnapshot.totalWorkouts > 0 else { return [] }
        var candidates = signals.compactMap {
            trendCandidate(
                from: $0,
                surfaces: [.profile],
                createdAt: trendSnapshot.generatedAt,
                planExercises: nil,
                planTitle: nil
            )
        }

        if let trophy = trophyCandidate(
            from: trophies,
            profile: profile,
            surfaces: [.profile],
            createdAt: trendSnapshot.generatedAt
        ) {
            candidates.append(trophy)
        }

        return cappedBootstrapCandidates(evidenceBacked(candidates), surface: .profile)
    }
}

nonisolated private extension InsightCandidateBuilder {
    func appendWorkoutFormBreakdowns(
        to candidates: inout [InsightCandidate],
        summary: WorkoutSessionSummary
    ) {
        for set in summary.exerciseSummaries {
            guard let quality = set.qualitySummary else { continue }
            let breakdownRep = quality.breakdownRepIndex
                ?? warningRepIndex(in: set)
                ?? lowScoreRepIndex(in: set)
            let hasDrop = quality.qualityTrend == .faded || breakdownRep != nil || quality.highSeverityCueCount >= 2
            guard hasDrop else { continue }

            let exercise = set.exerciseType
            let cue = quality.mostRepeatedCue ?? set.worstCue ?? set.cueEvents.first?.cueMessage
            let evidence = [
                InsightEvidence(
                    metric: "formDropOff",
                    value: breakdownRep.map { "after rep \($0)" } ?? "\(quality.highSeverityCueCount) warning cues",
                    comparison: formHalfComparison(quality),
                    workoutId: summary.id,
                    exerciseType: exercise,
                    setIndex: set.setIndex,
                    repIndex: breakdownRep,
                    confidence: quality.highSeverityCueCount >= 2 ? 0.92 : 0.84
                )
            ]

            let action = easierVariantAction(for: exercise)
            candidates.append(
                InsightCandidate(
                    type: .formCorrection,
                    candidateHeadline: "\(exercise.displayName) form needs protection",
                    candidateAction: action,
                    evidence: evidence,
                    rawScore: action == .useEasierVariant ? 98 : 92,
                    confidence: quality.highSeverityCueCount >= 2 ? 0.92 : 0.84,
                    surfaces: [.workoutSummary, .profile],
                    severity: quality.highSeverityCueCount >= 2 ? .important : .caution,
                    emotionalIntent: .preventOverreach,
                    relatedExerciseType: exercise,
                    relatedGoal: goal(from: summary.goal),
                    createdAt: summary.createdAt,
                    expiresAt: daysAfter(summary.createdAt, 10),
                    dedupeKey: [
                        "workout",
                        summary.id.uuidString,
                        "form-drop",
                        exercise.rawValue,
                        set.setIndex.map(String.init) ?? "set",
                        breakdownRep.map(String.init) ?? "cue"
                    ].joined(separator: "|"),
                    context: [
                        "exercise": exercise.displayName,
                        "breakdownRep": breakdownRep.map(String.init) ?? "",
                        "cue": cue ?? "",
                        "setText": setDisplayText(set.setIndex),
                        "goal": goalText(summary.goal)
                    ]
                )
            )
        }
    }

    func appendWorkoutFormGrowth(
        to candidates: inout [InsightCandidate],
        summary: WorkoutSessionSummary
    ) {
        for set in summary.exerciseSummaries {
            guard let quality = set.qualitySummary,
                  quality.qualityTrend == .improved,
                  let improvementRep = quality.improvementRepIndex
            else { continue }

            let exercise = set.exerciseType
            let safeProgression = (summary.completionPercent ?? 1) >= 0.95 &&
                (quality.averageFormScore ?? set.averageFormScore ?? 0) >= 84 &&
                quality.highSeverityCueCount == 0
            let evidence = [
                InsightEvidence(
                    metric: "formImprovement",
                    value: "improved after rep \(improvementRep)",
                    comparison: formHalfComparison(quality),
                    workoutId: summary.id,
                    exerciseType: exercise,
                    setIndex: set.setIndex,
                    repIndex: improvementRep,
                    confidence: safeProgression ? 0.9 : 0.82
                )
            ]

            candidates.append(
                InsightCandidate(
                    type: .growthCelebration,
                    candidateHeadline: "\(exercise.displayName) control improved",
                    candidateAction: safeProgression ? .increaseTarget : .continuePlan,
                    evidence: evidence,
                    rawScore: safeProgression ? 91 : 86,
                    confidence: safeProgression ? 0.9 : 0.82,
                    surfaces: [.workoutSummary, .profile],
                    severity: .positive,
                    emotionalIntent: .celebrateGrowth,
                    relatedExerciseType: exercise,
                    relatedGoal: goal(from: summary.goal),
                    createdAt: summary.createdAt,
                    expiresAt: daysAfter(summary.createdAt, 10),
                    dedupeKey: [
                        "workout",
                        summary.id.uuidString,
                        "form-growth",
                        exercise.rawValue,
                        set.setIndex.map(String.init) ?? "set",
                        String(improvementRep)
                    ].joined(separator: "|"),
                    context: [
                        "exercise": exercise.displayName,
                        "improvementRep": String(improvementRep),
                        "setText": setDisplayText(set.setIndex),
                        "goal": goalText(summary.goal)
                    ]
                )
            )
        }
    }

    func appendRepeatedCueCandidate(
        to candidates: inout [InsightCandidate],
        summary: WorkoutSessionSummary
    ) {
        let cueEvents = summary.exerciseSummaries.flatMap { set in
            set.cueEvents.map { (set.exerciseType, $0.cueMessage, $0.setIndex ?? set.setIndex, $0.repIndex) } +
                set.repQualityEvents.compactMap { event in
                    event.cueMessageNearRep.map { (set.exerciseType, $0, event.setIndex ?? set.setIndex, event.repIndex) }
                }
        }
        let grouped = Dictionary(grouping: cueEvents) { item in
            normalizedCue(item.1)
        }
        guard let repeated = grouped
            .filter({ !$0.key.isEmpty && $0.value.count >= 2 })
            .sorted(by: { lhs, rhs in
                if lhs.value.count == rhs.value.count {
                    return lhs.key < rhs.key
                }
                return lhs.value.count > rhs.value.count
            })
            .first
        else { return }

        let first = repeated.value[0]
        let cue = first.1
        let exercise = mostCommonExercise(in: repeated.value.map(\.0)) ?? first.0
        let evidence = repeated.value.prefix(4).map { item in
            InsightEvidence(
                metric: "repeatedCue",
                value: cue,
                comparison: "\(repeated.value.count) cue events",
                workoutId: summary.id,
                exerciseType: item.0,
                setIndex: item.2,
                repIndex: item.3,
                confidence: repeated.value.count >= 3 ? 0.9 : 0.8
            )
        }

        candidates.append(
            InsightCandidate(
                type: .formCorrection,
                candidateHeadline: "One cue kept showing up",
                candidateAction: .focusCue,
                evidence: evidence,
                rawScore: 88,
                confidence: repeated.value.count >= 3 ? 0.9 : 0.8,
                surfaces: [.workoutSummary, .profile],
                severity: .caution,
                emotionalIntent: .giveToughLove,
                relatedExerciseType: exercise,
                relatedGoal: goal(from: summary.goal),
                createdAt: summary.createdAt,
                expiresAt: daysAfter(summary.createdAt, 10),
                dedupeKey: [
                    "workout",
                    summary.id.uuidString,
                    "cue",
                    normalizedCue(cue)
                ].joined(separator: "|"),
                context: [
                    "exercise": exercise.displayName,
                    "cue": cue,
                    "count": String(repeated.value.count),
                    "goal": goalText(summary.goal)
                ]
            )
        )
    }

    func appendCompletionQualityCandidate(
        to candidates: inout [InsightCandidate],
        summary: WorkoutSessionSummary,
        plan: WorkoutPlanV2?
    ) {
        guard let completion = summary.completionPercent,
              completion >= 0.95,
              let averageForm = summary.averageFormScore,
              averageForm >= 85,
              summary.totalHighSeverityCues == 0,
              summary.totalReps + summary.totalHoldSeconds > 0
        else { return }

        let exercise = summary.primaryExerciseType
        let evidence = [
            InsightEvidence(
                metric: "completionQuality",
                value: "\(Int((completion * 100).rounded()))% complete",
                comparison: "\(Int(averageForm.rounded()))% average form",
                workoutId: summary.id,
                exerciseType: exercise,
                confidence: averageForm >= 90 ? 0.92 : 0.86
            )
        ]

        candidates.append(
            InsightCandidate(
                type: .planAdjustment,
                candidateHeadline: "Quality cleared the progression bar",
                candidateAction: .increaseTarget,
                evidence: evidence,
                rawScore: 80,
                confidence: averageForm >= 90 ? 0.92 : 0.86,
                surfaces: [.workoutSummary, .workoutPreview],
                severity: .positive,
                emotionalIntent: .buildConfidence,
                relatedExerciseType: exercise,
                relatedGoal: goal(from: summary.goal),
                createdAt: summary.createdAt,
                expiresAt: daysAfter(summary.createdAt, 7),
                dedupeKey: [
                    "workout",
                    summary.id.uuidString,
                    "completion-quality",
                    exercise?.rawValue ?? plan?.id.uuidString ?? "plan"
                ].joined(separator: "|"),
                context: [
                    "exercise": exercise?.displayName ?? summary.title,
                    "completion": "\(Int((completion * 100).rounded()))%",
                    "form": "\(Int(averageForm.rounded()))%",
                    "targetUnit": progressionUnit(for: summary),
                    "goal": goalText(summary.goal)
                ]
            )
        )
    }

    func appendRestAndSkippedCandidates(
        to candidates: inout [InsightCandidate],
        summary: WorkoutSessionSummary
    ) {
        let restExtended = summary.exerciseSummaries.filter(\.restExtended)
        if restExtended.count >= 2 {
            let exercise = mostCommonExercise(in: restExtended.map(\.exerciseType)) ?? restExtended[0].exerciseType
            let evidence = restExtended.prefix(4).map {
                InsightEvidence(
                    metric: "restExtensions",
                    value: "\(restExtended.count) extended rests",
                    comparison: nil,
                    workoutId: summary.id,
                    exerciseType: $0.exerciseType,
                    setIndex: $0.setIndex,
                    confidence: restExtended.count >= 3 ? 0.9 : 0.82
                )
            }
            candidates.append(
                InsightCandidate(
                    type: .recovery,
                    candidateHeadline: "Rest needs more room",
                    candidateAction: .increaseRest,
                    evidence: evidence,
                    rawScore: 89,
                    confidence: restExtended.count >= 3 ? 0.9 : 0.82,
                    surfaces: [.workoutSummary, .workoutPreview, .dashboard],
                    severity: .caution,
                    emotionalIntent: .preventOverreach,
                    relatedExerciseType: exercise,
                    relatedGoal: goal(from: summary.goal),
                    createdAt: summary.createdAt,
                    expiresAt: daysAfter(summary.createdAt, 7),
                    dedupeKey: [
                        "workout",
                        summary.id.uuidString,
                        "rest",
                        exercise.rawValue
                    ].joined(separator: "|"),
                    context: [
                        "exercise": exercise.displayName,
                        "count": String(restExtended.count),
                        "goal": goalText(summary.goal)
                    ]
                )
            )
        }

        let restSkipped = summary.exerciseSummaries.filter(\.skipped)
        guard !restSkipped.isEmpty else { return }
        let exercise = mostCommonExercise(in: restSkipped.map(\.exerciseType)) ?? restSkipped[0].exerciseType
        let evidence = restSkipped.prefix(4).map {
            InsightEvidence(
                metric: "restSkipped",
                value: "\(restSkipped.count) early rest skip\(restSkipped.count == 1 ? "" : "s")",
                comparison: summary.completionPercent.map { "\(Int(($0 * 100).rounded()))% completion" },
                workoutId: summary.id,
                exerciseType: $0.exerciseType,
                setIndex: $0.setIndex,
                confidence: restSkipped.count >= 2 ? 0.88 : 0.74
            )
        }

        candidates.append(
            InsightCandidate(
                type: .recovery,
                candidateHeadline: "\(exercise.displayName) rest timing should adjust",
                candidateAction: .reduceRest,
                evidence: evidence,
                rawScore: restSkipped.count >= 2 ? 84 : 72,
                confidence: restSkipped.count >= 2 ? 0.88 : 0.74,
                surfaces: [.workoutSummary, .workoutPreview],
                severity: .neutral,
                emotionalIntent: .explainPlan,
                relatedExerciseType: exercise,
                relatedGoal: goal(from: summary.goal),
                createdAt: summary.createdAt,
                expiresAt: daysAfter(summary.createdAt, 7),
                dedupeKey: [
                    "workout",
                    summary.id.uuidString,
                    "skipped",
                    exercise.rawValue
                ].joined(separator: "|"),
                context: [
                    "exercise": exercise.displayName,
                    "count": String(restSkipped.count),
                    "restSkipped": "true",
                    "goal": goalText(summary.goal)
                ]
            )
        )
    }

    func appendLimitationAwarePlanCandidate(
        to candidates: inout [InsightCandidate],
        profile: UserProfile,
        plan: WorkoutPlanV2,
        createdAt: Date
    ) {
        guard !profile.limitations.isEmpty else { return }
        let limitationTags = Set(profile.limitations.map(limitationTag))
        let planExercises = plan.blocks.flatMap(\.exercises)
        let conflicts = planExercises.compactMap { exercise -> (PlannedExercise, Set<ContraindicationTag>)? in
            guard let metadata = ExerciseMetadataCatalog.metadata(for: exercise.exerciseType) else { return nil }
            let overlap = metadata.contraindicationTags.intersection(limitationTags)
            return overlap.isEmpty ? nil : (exercise, overlap)
        }

        if let conflict = conflicts.first {
            let exercise = conflict.0.exerciseType
            let labels = conflict.1.map(\.rawValue).sorted().joined(separator: ", ")
            candidates.append(
                InsightCandidate(
                    type: .safety,
                    candidateHeadline: "\(exercise.displayName) needs a safer option",
                    candidateAction: .swapExerciseLater,
                    evidence: [
                        InsightEvidence(
                            metric: "profileLimitationConflict",
                            value: labels,
                            comparison: profile.limitations.map(\.displayName).sorted().joined(separator: ", "),
                            exerciseType: exercise,
                            confidence: 0.92
                        )
                    ],
                    rawScore: 99,
                    confidence: 0.92,
                    surfaces: [.workoutPreview, .dashboard],
                    severity: .important,
                    emotionalIntent: .preventOverreach,
                    relatedExerciseType: exercise,
                    relatedGoal: profile.primaryGoal,
                    createdAt: createdAt,
                    expiresAt: daysAfter(createdAt, 3),
                    dedupeKey: [
                        "plan",
                        plan.id.uuidString,
                        "limitation-conflict",
                        exercise.rawValue
                    ].joined(separator: "|"),
                    context: [
                        "exercise": exercise.displayName,
                        "limitations": profile.limitations.map(\.displayName).sorted().joined(separator: ", "),
                        "goal": profile.primaryGoal.displayName
                    ]
                )
            )
            return
        }

        let supportiveMoves = planExercises.filter { exercise in
            guard let metadata = ExerciseMetadataCatalog.metadata(for: exercise.exerciseType) else { return false }
            return metadata.planTags.contains(.lowImpact) ||
                !metadata.requiredEquipment.isDisjoint(with: [.chair, .wall, .mat, .bench])
        }
        guard !supportiveMoves.isEmpty else { return }
        let firstExercise = supportiveMoves.first?.exerciseType
        candidates.append(
            InsightCandidate(
                type: .safety,
                candidateHeadline: "Today respects your saved limits",
                candidateAction: .continuePlan,
                evidence: [
                    InsightEvidence(
                        metric: "profileLimitations",
                        value: profile.limitations.map(\.displayName).sorted().joined(separator: ", "),
                        comparison: "\(supportiveMoves.count) conservative plan move\(supportiveMoves.count == 1 ? "" : "s")",
                        exerciseType: firstExercise,
                        confidence: 0.76
                    )
                ],
                rawScore: 76,
                confidence: 0.76,
                surfaces: [.workoutPreview],
                severity: .neutral,
                emotionalIntent: .explainPlan,
                relatedExerciseType: firstExercise,
                relatedGoal: profile.primaryGoal,
                createdAt: createdAt,
                expiresAt: daysAfter(createdAt, 2),
                dedupeKey: [
                    "plan",
                    plan.id.uuidString,
                    "limitation-aware",
                    profile.limitations.map(\.rawValue).sorted().joined(separator: ",")
                ].joined(separator: "|"),
                context: [
                    "exercise": firstExercise?.displayName ?? plan.title,
                    "limitations": profile.limitations.map(\.displayName).sorted().joined(separator: ", "),
                    "goal": profile.primaryGoal.displayName
                ]
            )
        )
    }

    func appendSmartStartCandidate(
        to candidates: inout [InsightCandidate],
        profile: UserProfile,
        plan: WorkoutPlanV2,
        trendSnapshot: UserTrainingTrendSnapshot,
        createdAt: Date
    ) {
        guard trendSnapshot.totalWorkouts > 0,
              plan.estimatedMinutes <= 7,
              trendSnapshot.currentStreak == 0
        else { return }

        candidates.append(
            InsightCandidate(
                type: .planSpecific,
                candidateHeadline: "Smart Start protects the restart",
                candidateAction: .protectStreakWithSmartStart,
                evidence: [
                    InsightEvidence(
                        metric: "currentStreak",
                        value: "0 days",
                        comparison: "\(trendSnapshot.totalWorkouts) prior workout\(trendSnapshot.totalWorkouts == 1 ? "" : "s")",
                        confidence: 0.78
                    )
                ],
                rawScore: 82,
                confidence: 0.78,
                surfaces: [.workoutPreview, .dashboard],
                severity: .neutral,
                emotionalIntent: .reinforceConsistency,
                relatedExerciseType: plan.blocks.flatMap(\.exercises).first?.exerciseType,
                relatedGoal: profile.primaryGoal,
                createdAt: createdAt,
                expiresAt: daysAfter(createdAt, 1),
                dedupeKey: [
                    "plan",
                    plan.id.uuidString,
                    "smart-start-restart"
                ].joined(separator: "|"),
                context: [
                    "goal": profile.primaryGoal.displayName,
                    "planTitle": plan.title
                ]
            )
        )
    }

    func trendCandidate(
        from signal: UserTrainingSignal,
        surfaces: [InsightSurface],
        createdAt: Date,
        planExercises: Set<ExerciseType>?,
        planTitle: String?
    ) -> InsightCandidate? {
        let evidence = evidence(from: signal)
        guard !evidence.isEmpty else { return nil }

        let mapped = mappedInsight(for: signal)
        let exercise = signal.exerciseType
        let cue = signal.type == .repeatedCue ? signal.value : signal.comparisonValue
        let dedupeParts = [
            "signal",
            signal.type.rawValue,
            exercise?.rawValue ?? signal.movementPattern?.rawValue ?? "general",
            normalizedCue(signal.type == .repeatedCue ? signal.value : signal.title),
            signal.goal?.rawValue ?? "goal"
        ]

        return InsightCandidate(
            sourceSignalIds: [signal.id],
            type: mapped.type,
            candidateHeadline: mapped.headline,
            candidateAction: mapped.action,
            evidence: evidence,
            rawScore: mapped.rawScore,
            confidence: confidenceValue(signal.confidence),
            surfaces: surfaces,
            severity: mapped.severity,
            emotionalIntent: mapped.intent,
            relatedExerciseType: exercise,
            relatedGoal: signal.goal,
            createdAt: createdAt,
            expiresAt: daysAfter(createdAt, mapped.expirationDays),
            dedupeKey: dedupeParts.joined(separator: "|"),
            context: [
                "exercise": exercise?.displayName ?? "",
                "cue": cue ?? "",
                "value": signal.value,
                "comparison": signal.comparisonValue ?? "",
                "delta": signal.delta.map(formatSignedNumber) ?? "",
                "goal": signal.goal?.displayName ?? "",
                "planTitle": planTitle ?? "",
                "signalType": signal.type.rawValue,
                "status": status(for: signal),
                "movementPattern": signal.movementPattern.map(movementPatternLabel) ?? "",
                "planContainsExercise": exercise.map { planExercises?.contains($0) == true ? "true" : "false" } ?? "false"
            ]
        )
    }

    func trophyCandidate(
        from trophies: TrophyProgressSnapshot,
        profile: UserProfile,
        surfaces: [InsightSurface],
        createdAt: Date
    ) -> InsightCandidate? {
        guard let progress = trophies.nearestInProgress,
              progress.confidence != .unavailable,
              progress.progressFraction >= 0.8,
              let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId)
        else { return nil }

        let remaining = max(progress.targetValue - progress.currentValue, 0)
        return InsightCandidate(
            type: .trophyProgress,
            candidateHeadline: "\(definition.title) is within reach",
            candidateAction: .celebrate,
            evidence: [
                InsightEvidence(
                    metric: "trophyProgress",
                    value: "\(formatNumber(progress.currentValue))/\(formatNumber(progress.targetValue)) \(definition.unit)",
                    comparison: "\(formatNumber(remaining)) \(definition.unit) remaining",
                    confidence: progress.confidence == .exact ? 0.88 : 0.72
                )
            ],
            rawScore: progress.progressFraction >= 0.9 ? 100 : (progress.progressFraction >= 0.85 ? 95 : 88),
            confidence: progress.confidence == .exact ? 0.88 : 0.72,
            surfaces: surfaces,
            severity: .positive,
            emotionalIntent: .unlockMotivation,
            relatedGoal: profile.primaryGoal,
            createdAt: createdAt,
            expiresAt: daysAfter(createdAt, 5),
            dedupeKey: [
                "trophy",
                progress.trophyId,
                "\(Int(progress.currentValue.rounded()))"
            ].joined(separator: "|"),
            context: [
                "trophy": definition.title,
                "remaining": formatNumber(remaining),
                "unit": definition.unit,
                "goal": profile.primaryGoal.displayName
            ]
        )
    }

    func mappedInsight(
        for signal: UserTrainingSignal
    ) -> (
        type: InsightType,
        headline: String,
        action: InsightAction,
        severity: InsightSeverity,
        intent: InsightEmotionalIntent,
        rawScore: Double,
        expirationDays: Int
    ) {
        switch signal.type {
        case .consistency:
            return (.consistency, "Your streak has momentum", .protectStreakWithSmartStart, .positive, .reinforceConsistency, 78, 2)
        case .completion:
            return (.consistency, "Your weekly target is on track", .continuePlan, .positive, .reinforceConsistency, 74, 2)
        case .formImprovement:
            return (.growthCelebration, signal.exerciseType.map { "\($0.displayName) is getting cleaner" } ?? "Form is trending cleaner", .continuePlan, .positive, .celebrateGrowth, 86, 5)
        case .exerciseMastery:
            return (.growthCelebration, signal.exerciseType.map { "\($0.displayName) is a strong movement" } ?? "A movement is looking strong", .increaseTarget, .positive, .buildConfidence, 84, 5)
        case .formDropOff:
            return (.formCorrection, "Recent form needs a tighter target", .focusCue, .caution, .preventOverreach, 88, 5)
        case .exerciseStruggle:
            return (.formCorrection, signal.exerciseType.map { "\($0.displayName) needs a cleaner setup" } ?? "One movement needs a cleaner setup", .focusCue, .caution, .giveToughLove, 90, 5)
        case .volumeIncrease:
            return (.dayOverDayTrend, "Volume is moving up", .continuePlan, .positive, .buildConfidence, 76, 4)
        case .volumeDrop:
            return (.dayOverDayTrend, "Volume dipped recently", .repeatTarget, .neutral, .explainPlan, 70, 3)
        case .fatigue:
            return (.recovery, "Quality needs protection today", .decreaseTarget, .caution, .preventOverreach, 91, 3)
        case .restBehavior:
            return (.recovery, signal.exerciseType.map { "Rest is rising around \($0.displayName)" } ?? "Rest is rising", .increaseRest, .caution, .preventOverreach, 89, 4)
        case .skippedExercise:
            return (.recovery, signal.exerciseType.map { "Rest timing is being skipped around \($0.displayName)" } ?? "Rest timing is being skipped", .reduceRest, .neutral, .explainPlan, 78, 4)
        case .repeatedCue:
            return (.formCorrection, "One cue is becoming the priority", .focusCue, .caution, .giveToughLove, 87, 5)
        case .planFit:
            return (.safety, signal.exerciseType.map { "\($0.displayName) overlaps with a saved limit" } ?? "Plan fit needs caution", .useEasierVariant, .important, .preventOverreach, 96, 4)
        case .trophyProximity:
            return (.trophyProgress, signal.title, .celebrate, .positive, .unlockMotivation, 79, 5)
        case .cameraFriction:
            return (.planSpecific, "Camera setup is the first win", .focusCue, .neutral, .explainPlan, 73, 2)
        case .qualityCapacity:
            return (.planAdjustment, signal.exerciseType.map { "\($0.displayName) has a clean target estimate" } ?? "Clean target is clearer", .repeatTarget, .caution, .preventOverreach, 92, 5)
        case .targetFit:
            switch status(for: signal) {
            case "ready":
                return (.planAdjustment, signal.exerciseType.map { "\($0.displayName) earned a small progression" } ?? "Target earned a small progression", .increaseTarget, .positive, .buildConfidence, 88, 3)
            case "matched":
                return (.planSpecific, signal.exerciseType.map { "\($0.displayName) target fits today" } ?? "Target fits today", .continuePlan, .positive, .explainPlan, 76, 2)
            default:
                return (.planAdjustment, signal.exerciseType.map { "\($0.displayName) target is too hot" } ?? "Target should pull back", .decreaseTarget, .caution, .preventOverreach, 94, 3)
            }
        case .movementBalance:
            return (.planAdjustment, "Training balance needs a missing pattern", .swapExerciseLater, .neutral, .explainPlan, 78, 5)
        case .cueCluster:
            return (.formCorrection, "One cue family is becoming the priority", .focusCue, .caution, .giveToughLove, 89, 5)
        case .restResponse:
            if status(for: signal) == "restHelped" {
                return (.recovery, signal.exerciseType.map { "Rest is helping \($0.displayName)" } ?? "Rest is helping quality", .increaseRest, .neutral, .explainPlan, 86, 3)
            }
            return (.planAdjustment, signal.exerciseType.map { "Rest did not fix \($0.displayName)" } ?? "Rest did not restore quality", .decreaseTarget, .caution, .preventOverreach, 91, 3)
        case .progressionReadiness:
            if status(for: signal) == "ready" {
                return (.planAdjustment, signal.exerciseType.map { "\($0.displayName) passed the progression gate" } ?? "Progression gate is clear", .increaseTarget, .positive, .buildConfidence, 90, 3)
            }
            return (.planAdjustment, signal.exerciseType.map { "\($0.displayName) should wait before progressing" } ?? "Progression should wait", .repeatTarget, .caution, .preventOverreach, 88, 3)
        case .sessionFit:
            return (.consistency, "Short sessions are working", .protectStreakWithSmartStart, .positive, .reinforceConsistency, 82, 4)
        case .exerciseReacquisition:
            return (.planAdjustment, signal.exerciseType.map { "\($0.displayName) needs a re-entry target" } ?? "Re-entry target should stay conservative", .repeatTarget, .neutral, .explainPlan, 82, 4)
        case .exercisePreference:
            return (.planAdjustment, signal.exerciseType.map { "\($0.displayName) needs an easier fit" } ?? "One movement needs an easier fit", .useEasierVariant, .caution, .preventOverreach, 93, 4)
        case .qualityPR:
            return (.growthCelebration, signal.exerciseType.map { "\($0.displayName) hit a quality PR" } ?? "Quality hit a new high", .celebrate, .positive, .celebrateGrowth, 84, 5)
        case .firstSession:
            return (.consistency, "First session is logged", .continuePlan, .positive, .reinforceConsistency, 72, 3)
        case .setupQuality:
            if status(for: signal) == "setupNeedsAttention" {
                return (.planSpecific, "Camera setup is the first fix", .focusCue, .neutral, .explainPlan, 80, 2)
            }
            return (.planSpecific, "Camera setup is starting clean", .continuePlan, .positive, .buildConfidence, 74, 2)
        case .repCleanlinessIntro:
            return (.growthCelebration, signal.exerciseType.map { "\($0.displayName) has a clean-rep baseline" } ?? "Clean reps have a first baseline", .continuePlan, .positive, .buildConfidence, 79, 3)
        case .repeatExerciseProgress:
            if status(for: signal) == "declining" {
                return (.formCorrection, signal.exerciseType.map { "\($0.displayName) needs the same first-set focus" } ?? "Repeated movement needs focus", .focusCue, .caution, .preventOverreach, 83, 3)
            }
            return (.growthCelebration, signal.exerciseType.map { "\($0.displayName) has repeat-session evidence" } ?? "A repeated movement has evidence", .continuePlan, .positive, .buildConfidence, 81, 3)
        case .personalBaseline:
            return (.dayOverDayTrend, signal.exerciseType.map { "\($0.displayName) baseline is forming" } ?? "Personal baseline is forming", .continuePlan, .neutral, .explainPlan, 68, 4)
        }
    }

    func status(for signal: UserTrainingSignal) -> String {
        switch signal.type {
        case .targetFit:
            if signal.value == "ready to progress" { return "ready" }
            if signal.value == "well matched" { return "matched" }
            if signal.value == "too aggressive" { return "tooAggressive" }
        case .restResponse:
            if signal.value.contains("rest helped") { return "restHelped" }
            if signal.value.contains("did not restore") { return "restDidNotRestore" }
        case .progressionReadiness:
            if signal.value == "ready to progress" { return "ready" }
            if signal.value == "not ready to progress" { return "blocked" }
        case .setupQuality:
            return (signal.delta ?? 0) > 0 ? "setupNeedsAttention" : "setupClean"
        case .repeatExerciseProgress:
            if (signal.delta ?? 0) <= -2 { return "declining" }
            if (signal.delta ?? 0) >= 2 { return "improving" }
            return "steady"
        default:
            break
        }

        let text = "\(signal.title) \(signal.value) \(signal.comparisonValue ?? "")".lowercased()
        if text.contains("not ready") || text.contains("should wait") {
            return "blocked"
        }
        if text.contains("ready to progress") || text.contains("earned") || text.contains("passed") {
            return "ready"
        }
        if text.contains("well matched") || text.contains("fits today") {
            return "matched"
        }
        if text.contains("too aggressive") || text.contains("too hot") {
            return "tooAggressive"
        }
        if text.contains("did not restore") {
            return "restDidNotRestore"
        }
        if text.contains("rest helped") {
            return "restHelped"
        }
        return ""
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

    func evidence(from signal: UserTrainingSignal) -> [InsightEvidence] {
        let confidence = confidenceValue(signal.confidence)
        if signal.evidenceRefs.isEmpty {
            return []
        }

        return signal.evidenceRefs.map { ref in
            InsightEvidence(
                metric: signal.type.rawValue,
                value: signal.value,
                comparison: signal.comparisonValue,
                workoutId: ref.summaryId,
                exerciseType: ref.exerciseType ?? signal.exerciseType,
                setIndex: ref.setIndex,
                repIndex: ref.repIndex,
                signalId: signal.id,
                confidence: confidence
            )
        }
    }

    func evidenceBacked(_ candidates: [InsightCandidate]) -> [InsightCandidate] {
        candidates.filter { !$0.evidence.isEmpty && $0.candidateAction != .noActionNeeded }
    }

    func cappedBootstrapCandidates(
        _ candidates: [InsightCandidate],
        surface: InsightSurface
    ) -> [InsightCandidate] {
        let bootstrapCandidates = candidates.filter {
            $0.surfaces.contains(surface) && isBootstrapCandidate($0)
        }
        guard bootstrapCandidates.count > 2 else { return candidates }

        let allowed = Set(
            bootstrapCandidates
                .sorted {
                    if $0.rawScore == $1.rawScore {
                        return $0.candidateHeadline < $1.candidateHeadline
                    }
                    return $0.rawScore > $1.rawScore
                }
                .prefix(2)
                .map(\.id)
        )

        return candidates.filter { candidate in
            !candidate.surfaces.contains(surface) ||
                !isBootstrapCandidate(candidate) ||
                allowed.contains(candidate.id)
        }
    }

    func isBootstrapCandidate(_ candidate: InsightCandidate) -> Bool {
        guard let rawValue = candidate.context["signalType"],
              let signalType = TrainingSignalType(rawValue: rawValue)
        else { return false }

        return bootstrapSignalTypes.contains(signalType)
    }

    var bootstrapSignalTypes: Set<TrainingSignalType> {
        [
            .firstSession,
            .setupQuality,
            .repCleanlinessIntro,
            .repeatExerciseProgress,
            .personalBaseline
        ]
    }

    func planContainsSignalExercise(
        _ signal: UserTrainingSignal,
        planExercises: Set<ExerciseType>
    ) -> Bool {
        guard let exercise = signal.exerciseType else { return true }
        return planExercises.contains(exercise)
    }

    func warningRepIndex(in set: ExerciseSetSummary) -> Int? {
        set.cueEvents
            .filter { $0.severity >= .warning }
            .compactMap(\.repIndex)
            .min()
    }

    func lowScoreRepIndex(in set: ExerciseSetSummary) -> Int? {
        set.repQualityEvents
            .filter { ($0.formScore ?? 100) < 75 }
            .map(\.repIndex)
            .min()
    }

    func easierVariantAction(for exercise: ExerciseType) -> InsightAction {
        switch exercise {
        case .pushup, .tricepDip, .mountainClimber, .plank, .sidePlank:
            return .useEasierVariant
        default:
            return .focusCue
        }
    }

    func formHalfComparison(_ quality: SetQualitySummary) -> String? {
        guard let first = quality.firstHalfAverageFormScore,
              let second = quality.secondHalfAverageFormScore
        else { return nil }

        return "\(Int(first.rounded()))% to \(Int(second.rounded()))%"
    }

    func setDisplayText(_ setIndex: Int?) -> String {
        guard let setIndex else { return "the set" }
        return "set \(setIndex + 1)"
    }

    func progressionUnit(for summary: WorkoutSessionSummary) -> String {
        if summary.totalHoldSeconds > 0 && summary.totalReps == 0 {
            return "hold"
        }
        if summary.exerciseSummaries.allSatisfy({ setSummary in
            if case .some(.hold) = setSummary.target {
                return true
            }
            return false
        }) {
            return "hold"
        }
        if summary.exerciseSummaries.contains(where: { setSummary in
            if case .some(.timed) = setSummary.target {
                return true
            }
            if case .some(.amrap) = setSummary.target {
                return true
            }
            return false
        }) {
            return "timed"
        }
        return "reps"
    }

    func goal(from text: String?) -> FitnessGoal? {
        guard let text else { return nil }
        let normalized = text.lowercased()
        if normalized.contains("strength") || normalized.contains("muscle") || normalized.contains("power") {
            return .strength
        }
        if normalized.contains("performance") || normalized.contains("stamina") || normalized.contains("athletic") {
            return .performance
        }
        if normalized.contains("longevity") || normalized.contains("mobility") || normalized.contains("health") {
            return .longevity
        }
        return nil
    }

    func goalText(_ goalDescription: String?) -> String {
        goal(from: goalDescription)?.displayName ?? goalDescription ?? "training"
    }

    func confidenceValue(_ confidence: SignalConfidence) -> Double {
        switch confidence {
        case .high:
            return 0.9
        case .medium:
            return 0.72
        case .low:
            return 0.52
        }
    }

    func daysAfter(_ date: Date, _ days: Int) -> Date? {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: date)
    }

    func normalizedCue(_ cue: String) -> String {
        CueNormalizer.normalize(cue)
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
        case .balanceSensitive, .highImpactSensitive:
            return .highImpact
        }
    }

    func formatSignedNumber(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(formatNumber(value))"
    }

    func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}
