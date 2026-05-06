import XCTest
@testable import VirtualTrainer

final class InsightEngineTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    func testLowPushupFormAfterRepEightCreatesSpecificCorrectionInsight() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let summary = makeSummary(
            idSuffix: "9001",
            endedAt: now,
            exerciseType: .pushup,
            scores: [92, 91, 90, 89, 88, 86, 84, 70, 68],
            cueMessages: ["Keep your shoulders stacked"]
        )
        let insights = workoutInsights(summary: summary, history: [summary], now: now)

        let insight = try XCTUnwrap(insights.first { $0.type == .formCorrection })
        XCTAssertEqual(insight.relatedExerciseType, .pushup)
        XCTAssertEqual(insight.recommendedAction, .useEasierVariant)
        XCTAssertTrue(insight.message.localizedCaseInsensitiveContains("push"))
        XCTAssertTrue(insight.message.contains("rep 8"))
    }

    func testSquatFormImprovementAfterRepFourCreatesGrowthInsight() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let quality = SetQualitySummary(
            totalScoredReps: 7,
            goodFormReps: 3,
            excellentFormReps: 1,
            minFormScore: 68,
            maxFormScore: 92,
            averageFormScore: 82,
            firstHalfAverageFormScore: 70,
            secondHalfAverageFormScore: 90,
            breakdownRepIndex: nil,
            improvementRepIndex: 4,
            highSeverityCueCount: 0,
            mostRepeatedCue: nil,
            qualityTrend: .improved
        )
        let summary = makeSummary(
            idSuffix: "9002",
            endedAt: now,
            exerciseType: .squat,
            scores: [68, 70, 72, 86, 88, 90, 92],
            qualityOverride: quality
        )

        let insight = try XCTUnwrap(
            workoutInsights(summary: summary, history: [summary], now: now)
                .first { $0.type == .growthCelebration }
        )

        XCTAssertEqual(insight.relatedExerciseType, .squat)
        XCTAssertTrue(insight.message.contains("rep 4"))
        XCTAssertTrue(insight.message.contains("control stabilized"))
    }

    func testRepeatedCueAcrossWorkoutsCreatesFocusedCueInsight() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(
                idSuffix: "9003",
                endedAt: now,
                exerciseType: .lunge,
                scores: [86, 82, 76, 72],
                cueMessages: ["Keep your front knee steady"]
            ),
            makeSummary(
                idSuffix: "9004",
                endedAt: date(year: 2026, month: 5, day: 5, hour: 12),
                exerciseType: .lunge,
                scores: [84, 80, 74, 70],
                cueMessages: ["Keep your front knee steady"]
            )
        ]

        let insights = profileInsights(history: history, now: now)
        let insight = try XCTUnwrap(insights.first { $0.recommendedAction == .focusCue })

        XCTAssertEqual(insight.relatedExerciseType, .lunge)
        XCTAssertTrue(insight.message.contains("Keep your front knee steady"))
        XCTAssertGreaterThanOrEqual(insight.evidence.count, 2)
    }

    func testHighCompletionAndHighFormCreatesSafeProgressionInsight() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let summary = makeSummary(
            idSuffix: "9005",
            endedAt: now,
            exerciseType: .squat,
            averageFormScore: 92,
            completionPercent: 1
        )

        let insight = try XCTUnwrap(
            workoutInsights(summary: summary, history: [summary], now: now)
                .first { $0.recommendedAction == .increaseTarget }
        )

        XCTAssertEqual(insight.type, .planAdjustment)
        XCTAssertTrue(insight.message.contains("quality"))
    }

    func testRepeatedRestExtensionsCreateFatigueVolumeCautionInsight() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let summary = makeSummary(
            idSuffix: "9006",
            endedAt: now,
            exerciseType: .pushup,
            sets: [
                makeSetSummary(exerciseType: .pushup, setIndex: 0, scores: [84, 82, 80], restExtended: true),
                makeSetSummary(exerciseType: .pushup, setIndex: 1, scores: [82, 78, 76], restExtended: true)
            ]
        )

        let insight = try XCTUnwrap(
            workoutInsights(summary: summary, history: [summary], now: now)
                .first { $0.type == .recovery }
        )

        XCTAssertEqual(insight.recommendedAction, .increaseRest)
        XCTAssertEqual(insight.severity, .caution)
    }

    func testStreakNearMilestoneCreatesConsistencyInsight() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "9007", endedAt: now),
            makeSummary(idSuffix: "9008", endedAt: date(year: 2026, month: 5, day: 5, hour: 12))
        ]

        let insight = try XCTUnwrap(dashboardInsights(history: history, now: now).first { $0.type == .consistency })

        XCTAssertEqual(insight.recommendedAction, .protectStreakWithSmartStart)
        XCTAssertTrue(insight.message.contains("2 days") || insight.shortMessage.contains("2 days"))
    }

    func testTrophyNearUnlockCreatesTrophyProgressInsight() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [makeSummary(idSuffix: "9009", endedAt: now, reps: 20)]
        let trophies = trophySnapshot(
            now: now,
            customProgress: [
                TrophyDefinitionCatalog.ID.oneKClub: 850
            ]
        )

        let insight = try XCTUnwrap(dashboardInsights(history: history, trophies: trophies, now: now).first { $0.type == .trophyProgress })

        XCTAssertEqual(insight.recommendedAction, .celebrate)
        XCTAssertTrue(insight.message.contains("1K Club") || insight.headline.contains("1K Club"))
    }

    func testEmptyHistoryProducesNoFakeTrendClaims() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let profile = makeProfile()
        let trophies = emptyTrophySnapshot(now: now)
        let trendEngine = TrendEngine(calendar: calendar)
        let snapshot = trendEngine.buildSnapshot(
            history: [],
            profile: profile,
            trophies: trophies,
            now: now
        )
        let signals = SignalExtractor(trendEngine: trendEngine).extractSignals(
            snapshot: snapshot,
            history: [],
            profile: profile,
            trophies: trophies
        )
        let engine = InsightEngine()

        XCTAssertTrue(engine.generateDashboardInsights(profile: profile, trendSnapshot: snapshot, signals: signals, trophies: trophies).isEmpty)
        XCTAssertTrue(engine.generateProfileInsights(profile: profile, trendSnapshot: snapshot, signals: signals, trophies: trophies).isEmpty)
        XCTAssertTrue(engine.generateDayOverDayInsights(trendSnapshot: snapshot, signals: signals, profile: profile).isEmpty)
    }

    func testEveryGeneratedInsightHasEvidence() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "9010", endedAt: now, exerciseType: .pushup, scores: [90, 88, 86, 70], cueMessages: ["Stack shoulders"]),
            makeSummary(idSuffix: "9011", endedAt: date(year: 2026, month: 5, day: 5, hour: 12), exerciseType: .squat, averageFormScore: 92)
        ]
        let insights = dashboardInsights(history: history, now: now) + profileInsights(history: history, now: now)

        XCTAssertFalse(insights.isEmpty)
        XCTAssertTrue(insights.allSatisfy { !$0.evidence.isEmpty })
    }

    func testEveryGeneratedInsightHasRecommendedAction() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let summary = makeSummary(idSuffix: "9012", endedAt: now, exerciseType: .squat, scores: [70, 72, 88, 90])
        let insights = workoutInsights(summary: summary, history: [summary], now: now)

        XCTAssertFalse(insights.isEmpty)
        XCTAssertTrue(insights.allSatisfy { $0.recommendedAction != .noActionNeeded })
    }

    func testRankerChoosesSpecificActionableInsightOverGenericPraise() {
        let evidence = InsightEvidence(
            metric: "formDropOff",
            value: "after rep 8",
            comparison: "90% to 70%",
            workoutId: UUID(uuidString: "00000000-0000-0000-0000-000000009099"),
            exerciseType: .pushup,
            setIndex: 0,
            repIndex: 8,
            confidence: 0.9
        )
        let generic = InsightCandidate(
            type: .growthCelebration,
            candidateHeadline: "Great work today",
            candidateAction: .celebrate,
            evidence: [evidence],
            rawScore: 80,
            confidence: 0.8,
            surfaces: [.workoutSummary],
            severity: .positive,
            emotionalIntent: .buildConfidence,
            createdAt: Date(),
            dedupeKey: "generic"
        )
        let specific = InsightCandidate(
            type: .formCorrection,
            candidateHeadline: "Push-Up form needs protection",
            candidateAction: .useEasierVariant,
            evidence: [evidence],
            rawScore: 70,
            confidence: 0.9,
            surfaces: [.workoutSummary],
            severity: .caution,
            emotionalIntent: .preventOverreach,
            relatedExerciseType: .pushup,
            createdAt: Date(),
            dedupeKey: "specific",
            context: ["exercise": "Push-Up", "breakdownRep": "8", "cue": "Stack shoulders"]
        )

        XCTAssertEqual(InsightRanker().rank([generic, specific], surface: .workoutSummary).first?.dedupeKey, "specific")
    }

    @MainActor
    func testDedupingPreventsSameInsightFromRepeatingEveryLaunch() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let store = InsightStore(fileURL: temporaryInsightURL())
        let insight = makeStoredInsight(now: now)

        let first = store.selectInsights([insight], for: .profile, limit: 1, now: now)
        let second = store.selectInsights([insight], for: .profile, limit: 1, now: now.addingTimeInterval(60))
        let afterCooldown = store.selectInsights([insight], for: .profile, limit: 1, now: now.addingTimeInterval(24 * 60 * 60))

        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(afterCooldown.count, 1)
    }

    func testHeartRateBPMCopyIsNotGeneratedWithoutHeartRateData() {
        let insight = unsafeNarrativeInsight(value: "160 BPM heart rate spike")

        assertNoUnsupportedPhysiologyCopy(in: insight)
    }

    func testWeightLossAndCalorieClaimsAreNotGeneratedWithoutSupportedData() {
        let insight = unsafeNarrativeInsight(value: "500 calories for weight loss")

        assertNoUnsupportedPhysiologyCopy(in: insight)
    }

    func testLimitationAwareProfileProducesConservativeSafetyInsight() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let profile = makeProfile(limitations: [.shoulderSensitive])
        let plan = WorkoutPlanV2(
            title: "Supported Strength",
            subtitle: "Low impact",
            goal: "Build clean strength.",
            estimatedMinutes: 7,
            difficulty: .beginner,
            coach: .good,
            blocks: [
                WorkoutBlock(
                    title: "Main",
                    type: .main,
                    exercises: [
                        PlannedExercise(
                            exerciseType: .squat,
                            sets: [PlannedSet(setIndex: 1, target: .reps(8))],
                            restSeconds: 60,
                            coachingFocus: "Controlled depth.",
                            cameraPosition: .front,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: now,
            planReason: "Local test plan.",
            source: .generatedLocal
        )
        let trophies = emptyTrophySnapshot(now: now)
        let snapshot = TrendEngine(calendar: calendar).buildSnapshot(
            history: [],
            profile: profile,
            trophies: trophies,
            now: now
        )

        let insight = try XCTUnwrap(
            InsightEngine().generatePlanInsights(
                profile: profile,
                plan: plan,
                trendSnapshot: snapshot,
                signals: [],
                trophyProgress: trophies
            ).first { $0.type == .safety }
        )

        XCTAssertEqual(insight.recommendedAction, .continuePlan)
        XCTAssertTrue(insight.message.contains("Shoulder sensitive"))
    }

    func testDashboardInsightIsShort() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "9013", endedAt: now),
            makeSummary(idSuffix: "9014", endedAt: date(year: 2026, month: 5, day: 5, hour: 12))
        ]

        let insight = try XCTUnwrap(dashboardInsights(history: history, now: now).first)

        XCTAssertLessThanOrEqual(insight.message.count, 140)
        XCTAssertLessThanOrEqual(insight.shortMessage.count, 140)
    }

    func testWorkoutSummaryInsightIsSpecific() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let summary = makeSummary(
            idSuffix: "9015",
            endedAt: now,
            exerciseType: .pushup,
            scores: [92, 90, 88, 86, 70],
            cueMessages: ["Stack shoulders"]
        )

        let insight = try XCTUnwrap(workoutInsights(summary: summary, history: [summary], now: now).first)

        XCTAssertTrue(insight.message.localizedCaseInsensitiveContains("push"))
        XCTAssertTrue(insight.message.contains("rep"))
    }

    func testProfileInsightConnectsMultipleSessions() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "9016", endedAt: date(year: 2026, month: 5, day: 1, hour: 12), exerciseType: .pushup, averageFormScore: 68),
            makeSummary(idSuffix: "9017", endedAt: date(year: 2026, month: 5, day: 2, hour: 12), exerciseType: .pushup, averageFormScore: 72),
            makeSummary(idSuffix: "9018", endedAt: date(year: 2026, month: 5, day: 5, hour: 12), exerciseType: .pushup, averageFormScore: 86),
            makeSummary(idSuffix: "9019", endedAt: now, exerciseType: .pushup, averageFormScore: 92)
        ]

        let insight = try XCTUnwrap(profileInsights(history: history, now: now).first { $0.type == .growthCelebration })
        let workoutIds = Set(insight.evidence.compactMap(\.workoutId))

        XCTAssertEqual(insight.relatedExerciseType, .pushup)
        XCTAssertGreaterThanOrEqual(workoutIds.count, 2)
    }

    func testFatigueInsightDoesNotPretendRestWasExtended() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let profile = makeProfile()
        let signal = UserTrainingSignal(
            type: .fatigue,
            goal: profile.primaryGoal,
            title: "Recent late-session strain signals are higher",
            value: "effort proxy present",
            comparisonValue: "Face-effort proxy only",
            confidence: .medium,
            evidenceRefs: [
                TrainingEvidenceRef(
                    summaryId: UUID(uuidString: "00000000-0000-0000-0000-000000009400"),
                    date: now,
                    label: "Recent strain"
                )
            ],
            createdAt: now
        )

        let insight = try XCTUnwrap(
            InsightEngine().generateDashboardInsights(
                profile: profile,
                trendSnapshot: makeTrendSnapshot(now: now, totalWorkouts: 3),
                signals: [signal],
                trophies: emptyTrophySnapshot(now: now)
            ).first { $0.type == .recovery }
        )

        XCTAssertFalse(insight.message.localizedCaseInsensitiveContains("rest extended"))
        XCTAssertTrue(insight.message.localizedCaseInsensitiveContains("strain"))
    }

    func testHoldProgressionInsightDoesNotRecommendAddingReps() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let summary = WorkoutSessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000009401") ?? UUID(),
            mode: .plannedWorkout,
            planId: UUID(uuidString: "00000000-0000-0000-0000-000000009300"),
            title: "Plank Session",
            goal: "Build clean strength.",
            coach: .good,
            startedAt: now.addingTimeInterval(-300),
            endedAt: now,
            durationSeconds: 300,
            totalReps: 0,
            totalHoldSeconds: 45,
            averageFormScore: 92,
            completionPercent: 1,
            exerciseSummaries: [
                ExerciseSetSummary(
                    exerciseType: .plank,
                    setIndex: 0,
                    target: .hold(seconds: 45),
                    achievedReps: 0,
                    achievedHoldSeconds: 45,
                    averageFormScore: 92,
                    completionSource: .targetMet,
                    completedAt: now,
                    durationSeconds: 45
                )
            ],
            topCue: nil,
            effortSummary: "No face-effort signal was captured for this session.",
            workoutOutcome: .completed,
            structuredEffortSummary: nil,
            createdAt: now
        )

        let insight = try XCTUnwrap(
            workoutInsights(summary: summary, history: [summary], now: now)
                .first { $0.recommendedAction == .increaseTarget }
        )

        XCTAssertTrue(insight.message.localizedCaseInsensitiveContains("seconds") || insight.message.localizedCaseInsensitiveContains("hold"))
        XCTAssertFalse(insight.message.localizedCaseInsensitiveContains("one rep"))
    }

    func testPlanPreviewFiltersExerciseSpecificSignalsOutsideTodaysPlan() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let profile = makeProfile()
        let offPlanSignal = UserTrainingSignal(
            type: .restBehavior,
            exerciseType: .pushup,
            movementPattern: .push,
            goal: profile.primaryGoal,
            title: "Rest was extended around Push Ups",
            value: "3 extended rests",
            confidence: .high,
            evidenceRefs: [
                TrainingEvidenceRef(
                    summaryId: UUID(uuidString: "00000000-0000-0000-0000-000000009402"),
                    exerciseType: .pushup,
                    setIndex: 0,
                    date: now,
                    label: "Push Up set"
                )
            ],
            createdAt: now
        )

        let insights = InsightEngine().generatePlanInsights(
            profile: profile,
            plan: makePlan(),
            trendSnapshot: makeTrendSnapshot(now: now, totalWorkouts: 3, currentStreak: 1),
            signals: [offPlanSignal],
            trophyProgress: emptyTrophySnapshot(now: now)
        )

        XCTAssertFalse(insights.contains { $0.relatedExerciseType == .pushup })
    }

    @MainActor
    func testPersistedDuplicateDeliveryRecordsMergeSurfaceCooldowns() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let url = temporaryInsightURL()
        let insight = makeStoredInsight(now: now)
        let profileRecord = InsightDeliveryRecord(
            dedupeKey: insight.dedupeKey,
            presentedAt: now.addingTimeInterval(-60),
            surface: .profile
        )
        let newerDashboardRecord = InsightDeliveryRecord(
            dedupeKey: insight.dedupeKey,
            presentedAt: now.addingTimeInterval(-30),
            surface: .dashboard
        )
        let snapshot = PersistedInsightStoreSnapshot(
            sourcePolicyVersion: AIInsight.currentSourcePolicyVersion,
            savedAt: now,
            recentInsights: [insight],
            deliveryRecords: [profileRecord, newerDashboardRecord]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: [.atomic])

        let store = InsightStore(fileURL: url)

        XCTAssertTrue(
            store.selectInsights([insight], for: .profile, limit: 1, now: now).isEmpty
        )
    }
}

private extension InsightEngineTests {
    func workoutInsights(
        summary: WorkoutSessionSummary,
        history: [WorkoutSessionSummary],
        now: Date
    ) -> [AIInsight] {
        let profile = makeProfile()
        let trophies = emptyTrophySnapshot(now: now)
        let trendEngine = TrendEngine(calendar: calendar)
        let snapshot = trendEngine.buildSnapshot(
            history: history,
            profile: profile,
            trophies: trophies,
            now: now
        )
        let signals = SignalExtractor(trendEngine: trendEngine).extractSignals(
            snapshot: snapshot,
            history: history,
            profile: profile,
            trophies: trophies
        )
        return InsightEngine().generateWorkoutInsights(
            summary: summary,
            plan: makePlan(),
            trendSnapshot: snapshot,
            signals: signals
        )
    }

    func dashboardInsights(
        history: [WorkoutSessionSummary],
        trophies: TrophyProgressSnapshot? = nil,
        now: Date
    ) -> [AIInsight] {
        let profile = makeProfile()
        let resolvedTrophies = trophies ?? emptyTrophySnapshot(now: now)
        let trendEngine = TrendEngine(calendar: calendar)
        let snapshot = trendEngine.buildSnapshot(
            history: history,
            profile: profile,
            trophies: resolvedTrophies,
            now: now
        )
        let signals = SignalExtractor(trendEngine: trendEngine).extractSignals(
            snapshot: snapshot,
            history: history,
            profile: profile,
            trophies: resolvedTrophies
        )
        return InsightEngine().generateDashboardInsights(
            profile: profile,
            trendSnapshot: snapshot,
            signals: signals,
            trophies: resolvedTrophies
        )
    }

    func profileInsights(
        history: [WorkoutSessionSummary],
        now: Date
    ) -> [AIInsight] {
        let profile = makeProfile()
        let trophies = emptyTrophySnapshot(now: now)
        let trendEngine = TrendEngine(calendar: calendar)
        let snapshot = trendEngine.buildSnapshot(
            history: history,
            profile: profile,
            trophies: trophies,
            now: now
        )
        let signals = SignalExtractor(trendEngine: trendEngine).extractSignals(
            snapshot: snapshot,
            history: history,
            profile: profile,
            trophies: trophies
        )
        return InsightEngine().generateProfileInsights(
            profile: profile,
            trendSnapshot: snapshot,
            signals: signals,
            trophies: trophies
        )
    }

    func unsafeNarrativeInsight(value: String) -> AIInsight {
        let evidence = InsightEvidence(
            metric: "unsupported",
            value: value,
            confidence: 0.8
        )
        let candidate = InsightCandidate(
            type: .dayOverDayTrend,
            candidateHeadline: "Unsupported physiology",
            candidateAction: .continuePlan,
            evidence: [evidence],
            rawScore: 80,
            confidence: 0.8,
            surfaces: [.dashboard],
            severity: .neutral,
            emotionalIntent: .explainPlan,
            createdAt: Date(),
            dedupeKey: "unsafe",
            context: ["value": value]
        )

        return InsightNarrativeBuilder().buildInsight(
            from: candidate,
            userValueScore: 80,
            surface: .dashboard
        )
    }

    func assertNoUnsupportedPhysiologyCopy(in insight: AIInsight) {
        let text = "\(insight.headline) \(insight.message) \(insight.shortMessage)".lowercased()
        XCTAssertFalse(text.contains("heart rate"))
        XCTAssertFalse(text.contains("bpm"))
        XCTAssertFalse(text.contains("calorie"))
        XCTAssertFalse(text.contains("weight loss"))
        XCTAssertFalse(text.contains("fat loss"))
    }

    func makeStoredInsight(now: Date) -> AIInsight {
        AIInsight(
            type: .growthCelebration,
            headline: "Squat control improved",
            message: "Your squat control improved. Because it is backed by form evidence, keep the plan steady.",
            shortMessage: "Squat control improved. Keep the plan steady.",
            evidence: [
                InsightEvidence(
                    metric: "formImprovement",
                    value: "+8 pts",
                    workoutId: UUID(uuidString: "00000000-0000-0000-0000-000000009200"),
                    exerciseType: .squat,
                    confidence: 0.9
                )
            ],
            recommendedAction: .continuePlan,
            severity: .positive,
            emotionalIntent: .celebrateGrowth,
            userValueScore: 100,
            confidence: 0.9,
            surfaces: [.profile],
            relatedExerciseType: .squat,
            relatedGoal: .strength,
            createdAt: now,
            expiresAt: now.addingTimeInterval(7 * 24 * 60 * 60),
            dedupeKey: "test-dedupe"
        )
    }

    func makeProfile(
        limitations: Set<PhysicalLimitation> = [],
        workoutDaysPerWeek: Int? = 3
    ) -> UserProfile {
        let now = date(year: 2026, month: 5, day: 1, hour: 9)
        return UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000009999") ?? UUID(),
            displayName: "Test Athlete",
            genderIdentity: .preferNotToSay,
            age: 30,
            height: 170,
            heightUnit: .metric,
            weight: 70,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .beginner,
            equipment: [.bodyweight, .mat, .wall],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            limitations: limitations,
            preferredSessionLength: .fifteen,
            workoutDaysPerWeek: workoutDaysPerWeek,
            reminderPreference: .none,
            timezoneIdentifier: "UTC",
            avatarStyle: .default,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    func makePlan() -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000009300") ?? UUID(),
            title: "Test Strength",
            subtitle: "Evidence plan",
            goal: "Build clean strength.",
            estimatedMinutes: 7,
            difficulty: .beginner,
            coach: .good,
            blocks: [
                WorkoutBlock(
                    title: "Main",
                    type: .main,
                    exercises: [
                        PlannedExercise(
                            exerciseType: .squat,
                            sets: [PlannedSet(setIndex: 1, target: .reps(8))],
                            restSeconds: 60,
                            coachingFocus: "Controlled depth.",
                            cameraPosition: .front,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: date(year: 2026, month: 5, day: 6, hour: 9),
            planReason: "Test plan.",
            source: .generatedLocal
        )
    }

    func makeSummary(
        idSuffix: String,
        endedAt: Date,
        exerciseType: ExerciseType = .squat,
        reps: Int = 10,
        averageFormScore: Double? = 84,
        completionPercent: Double = 1,
        scores: [Int] = [],
        cueMessages: [String] = [],
        restExtended: Bool = false,
        skipped: Bool = false,
        sets: [ExerciseSetSummary]? = nil,
        qualityOverride: SetQualitySummary? = nil
    ) -> WorkoutSessionSummary {
        let exerciseSummaries = sets ?? [
            makeSetSummary(
                exerciseType: exerciseType,
                setIndex: 0,
                reps: scores.isEmpty ? reps : scores.count,
                averageFormScore: averageFormScore,
                scores: scores,
                cueMessages: cueMessages,
                restExtended: restExtended,
                skipped: skipped,
                qualityOverride: qualityOverride
            )
        ]
        let resolvedReps = exerciseSummaries.reduce(0) { $0 + $1.achievedReps }
        let resolvedAverage = average(exerciseSummaries.compactMap(\.averageFormScore)) ?? averageFormScore

        return WorkoutSessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000\(idSuffix)") ?? UUID(),
            mode: .plannedWorkout,
            planId: UUID(uuidString: "00000000-0000-0000-0000-000000009300"),
            title: "\(exerciseType.displayName) Session",
            goal: "Build clean strength.",
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            durationSeconds: 600,
            totalReps: resolvedReps,
            totalHoldSeconds: 0,
            averageFormScore: resolvedAverage,
            completionPercent: completionPercent,
            exerciseSummaries: exerciseSummaries,
            topCue: exerciseSummaries.flatMap(\.cueEvents).first,
            effortSummary: "No face-effort signal was captured for this session.",
            workoutOutcome: completionPercent >= 1 ? .completed : .partial,
            structuredEffortSummary: nil,
            createdAt: endedAt
        )
    }

    func makeSetSummary(
        exerciseType: ExerciseType,
        setIndex: Int,
        reps: Int? = nil,
        averageFormScore: Double? = nil,
        scores: [Int],
        cueMessages: [String] = [],
        restExtended: Bool = false,
        skipped: Bool = false,
        qualityOverride: SetQualitySummary? = nil
    ) -> ExerciseSetSummary {
        let repEvents = scores.enumerated().map { index, score in
            RepQualityEvent(
                exerciseType: exerciseType,
                setIndex: setIndex,
                repIndex: index + 1,
                timestamp: date(year: 2026, month: 5, day: 6, hour: 12).addingTimeInterval(TimeInterval(index)),
                secondsIntoSet: TimeInterval((index + 1) * 5),
                formScore: score,
                formGrade: nil,
                phase: nil,
                cueMessageNearRep: cueMessages.first,
                cueSeverityNearRep: cueMessages.isEmpty ? nil : .warning
            )
        }
        let cueEvents = cueMessages.enumerated().map { index, message in
            CueEvent(
                timestamp: date(year: 2026, month: 5, day: 6, hour: 12).addingTimeInterval(TimeInterval(index)),
                exerciseType: exerciseType,
                cueMessage: message,
                severity: .warning,
                setIndex: setIndex,
                repIndex: scores.isEmpty ? nil : min(index + 1, scores.count),
                secondsIntoSet: TimeInterval((index + 1) * 5),
                formScoreAtEvent: scores.dropFirst(index).first
            )
        }
        let quality = qualityOverride ?? (scores.isEmpty ? nil : SetQualitySummary.build(repQualityEvents: repEvents, cueEvents: cueEvents))
        let resolvedReps = reps ?? (scores.isEmpty ? 10 : scores.count)

        return ExerciseSetSummary(
            exerciseType: exerciseType,
            setIndex: setIndex,
            target: .reps(resolvedReps),
            achievedReps: resolvedReps,
            achievedHoldSeconds: 0,
            averageFormScore: quality?.averageFormScore ?? averageFormScore ?? average(scores.map(Double.init)),
            cueEvents: cueEvents,
            restExtended: restExtended,
            skipped: skipped,
            qualitySummary: quality,
            repQualityEvents: repEvents,
            completionSource: skipped ? .manual : .targetMet,
            completedAt: date(year: 2026, month: 5, day: 6, hour: 12),
            durationSeconds: 60
        )
    }

    func emptyTrophySnapshot(now: Date) -> TrophyProgressSnapshot {
        trophySnapshot(now: now, customProgress: [:])
    }

    func trophySnapshot(
        now: Date,
        customProgress: [String: Double]
    ) -> TrophyProgressSnapshot {
        TrophyProgressSnapshot(
            catalogVersion: TrophyDefinitionCatalog.version,
            generatedAt: now,
            progress: TrophyDefinitionCatalog.all.map { definition in
                let current = customProgress[definition.id] ?? 0
                let earned = current >= definition.targetValue && !definition.isComingSoon
                return TrophyProgress(
                    trophyId: definition.id,
                    currentValue: min(current, definition.targetValue),
                    targetValue: definition.targetValue,
                    earned: earned,
                    earnedAt: earned ? now : nil,
                    lastUpdatedAt: now,
                    confidence: definition.isComingSoon ? .unavailable : .exact,
                    progressLabel: earned ? "Earned" : "\(Int(current))/\(Int(definition.targetValue)) \(definition.unit)"
                )
            },
            newlyEarnedEvents: []
        )
    }

    func makeTrendSnapshot(
        now: Date,
        totalWorkouts: Int,
        currentStreak: Int = 0
    ) -> UserTrainingTrendSnapshot {
        UserTrainingTrendSnapshot(
            generatedAt: now,
            totalWorkouts: totalWorkouts,
            currentStreak: currentStreak,
            workoutsThisWeek: min(totalWorkouts, 3),
            workoutDaysThisWeek: min(totalWorkouts, 3),
            weeklyConsistencyStatus: totalWorkouts > 0 ? .building : .noHistory,
            overallFormTrend: .steady,
            volumeTrend: .steady,
            fatigueTrend: .unavailable,
            strongestExercise: nil,
            improvingExercise: nil,
            strugglingExercise: nil,
            mostRepeatedCue: nil,
            trophyNearMisses: [],
            cameraFrictionCount: 0,
            exerciseTrends: []
        )
    }

    func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        ) ?? Date(timeIntervalSince1970: 0)
    }

    func temporaryInsightURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
