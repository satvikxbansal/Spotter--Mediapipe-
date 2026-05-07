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

    func testWorkoutRepeatedCueCandidateNormalizesCueVariants() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let summary = makeSummary(
            idSuffix: "9061",
            endedAt: now,
            exerciseType: .pushup,
            averageFormScore: 84,
            scores: [],
            cueMessages: [
                "Keep your wrists neutral.",
                "  keep   your wrists neutral!  "
            ]
        )

        let insight = try XCTUnwrap(
            workoutInsights(summary: summary, history: [summary], now: now)
                .first { insight in
                    insight.evidence.contains { $0.metric == "repeatedCue" }
                }
        )

        XCTAssertEqual(insight.relatedExerciseType, .pushup)
        XCTAssertEqual(insight.recommendedAction, .focusCue)
        XCTAssertEqual(Set(insight.evidence.map { CueNormalizer.normalize($0.value) }), ["wrists neutral"])
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

    func testDerivedSignalsProtectCleanCapacityTargetFitProgressionAndQualityPR() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let latest = makeSummary(
            idSuffix: "9040",
            endedAt: now,
            exerciseType: .squat,
            sets: [
                makeSetSummary(
                    exerciseType: .pushup,
                    setIndex: 0,
                    scores: [92, 90, 88, 84, 76, 70, 68, 65],
                    cueMessages: ["Stack shoulders"]
                ),
                makeSetSummary(
                    exerciseType: .squat,
                    setIndex: 1,
                    scores: [95, 94, 94, 93, 94, 95, 94, 94]
                )
            ]
        )
        let history = [
            latest,
            makeSummary(
                idSuffix: "9041",
                endedAt: date(year: 2026, month: 5, day: 5, hour: 12),
                exerciseType: .pushup,
                scores: [91, 90, 88, 82, 74, 70, 68, 66],
                cueMessages: ["Stack shoulders"]
            ),
            makeSummary(
                idSuffix: "9042",
                endedAt: date(year: 2026, month: 5, day: 4, hour: 12),
                exerciseType: .squat,
                scores: [90, 89, 90, 88, 89, 90, 88, 89]
            )
        ]

        let signals = trainingSignals(history: history, now: now)

        assertSignal(.qualityCapacity, existsIn: signals)
        assertSignal(.targetFit, existsIn: signals)
        assertSignal(.progressionReadiness, existsIn: signals)
        assertSignal(.qualityPR, existsIn: signals)
        assertNoUnsupportedPhysiologyCopy(in: signals)
    }

    func testDerivedSignalsDetectBalanceCueClustersRestResponseAndSessionFit() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(
                idSuffix: "9043",
                endedAt: now,
                exerciseType: .pushup,
                sets: [
                    makeSetSummary(exerciseType: .pushup, setIndex: 0, scores: [80, 78, 76], restExtended: true),
                    makeSetSummary(exerciseType: .pushup, setIndex: 1, scores: [88, 89, 90])
                ]
            ),
            makeSummary(
                idSuffix: "9044",
                endedAt: date(year: 2026, month: 5, day: 5, hour: 12),
                exerciseType: .lunge,
                scores: [86, 82, 76, 72],
                cueMessages: ["Keep your front knee steady"]
            ),
            makeSummary(
                idSuffix: "9045",
                endedAt: date(year: 2026, month: 5, day: 4, hour: 12),
                exerciseType: .squat,
                scores: [88, 84, 78, 74],
                cueMessages: ["Knee is drifting inward"]
            ),
            makeSummary(
                idSuffix: "9046",
                endedAt: date(year: 2026, month: 5, day: 3, hour: 12),
                exerciseType: .squat,
                averageFormScore: 90,
                durationSeconds: 480
            ),
            makeSummary(
                idSuffix: "9047",
                endedAt: date(year: 2026, month: 5, day: 2, hour: 12),
                exerciseType: .squat,
                averageFormScore: 88,
                durationSeconds: 540
            ),
            makeSummary(
                idSuffix: "9048",
                endedAt: date(year: 2026, month: 5, day: 1, hour: 12),
                exerciseType: .squat,
                averageFormScore: 86,
                durationSeconds: 600
            )
        ]

        let signals = trainingSignals(history: history, now: now)

        assertSignal(.movementBalance, existsIn: signals)
        assertSignal(.cueCluster, existsIn: signals)
        assertSignal(.restResponse, existsIn: signals)
        assertSignal(.sessionFit, existsIn: signals)
        assertNoUnsupportedPhysiologyCopy(in: signals)
    }

    func testDerivedSignalsDetectReacquisitionAndRepeatedExerciseFriction() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(
                idSuffix: "9049",
                endedAt: now,
                exerciseType: .deadlift,
                averageFormScore: 86
            ),
            makeSummary(
                idSuffix: "9050",
                endedAt: date(year: 2026, month: 5, day: 5, hour: 12),
                exerciseType: .pushup,
                scores: [92, 86, 74, 70],
                cueMessages: ["Move further from the camera"]
            ),
            makeSummary(
                idSuffix: "9051",
                endedAt: date(year: 2026, month: 5, day: 4, hour: 12),
                exerciseType: .pushup,
                scores: [80, 78, 74, 70],
                restExtended: true
            ),
            makeSummary(
                idSuffix: "9052",
                endedAt: date(year: 2026, month: 4, day: 15, hour: 12),
                exerciseType: .deadlift,
                averageFormScore: 88
            )
        ]

        let signals = trainingSignals(history: history, now: now)

        assertSignal(.exerciseReacquisition, existsIn: signals)
        assertSignal(.exercisePreference, existsIn: signals)
        assertNoUnsupportedPhysiologyCopy(in: signals)
    }

    func testDerivedSignalsDoNotInferTargetFitOrQualityPRWithoutQualityEvidence() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let unscoredTargetMet = makeSummary(
            idSuffix: "9053",
            endedAt: now,
            exerciseType: .squat,
            averageFormScore: nil
        )
        let noPriorQualityHistory = [
            makeSummary(
                idSuffix: "9054",
                endedAt: now,
                exerciseType: .pushup,
                scores: [95, 94, 93, 94]
            ),
            makeSummary(
                idSuffix: "9055",
                endedAt: date(year: 2026, month: 5, day: 5, hour: 12),
                exerciseType: .pushup,
                averageFormScore: nil
            )
        ]

        let unscoredSignals = trainingSignals(history: [unscoredTargetMet], now: now)
        let noPriorQualitySignals = trainingSignals(history: noPriorQualityHistory, now: now)

        XCTAssertNil(unscoredSignals.first { $0.type == .targetFit })
        XCTAssertNil(noPriorQualitySignals.first { $0.type == .qualityPR })
    }

    func testBootstrapFirstSessionSignalsAndDashboardInsight() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(
                idSuffix: "9062",
                endedAt: now,
                exerciseType: .squat,
                scores: [90, 70, 85, 80]
            )
        ]

        let signals = trainingSignals(history: history, now: now)

        for type in [TrainingSignalType.firstSession, .setupQuality, .repCleanlinessIntro, .personalBaseline] {
            let signal = try XCTUnwrap(signals.first { $0.type == type })
            XCTAssertEqual(signal.confidence, .medium)
            XCTAssertFalse(signal.evidenceRefs.isEmpty)
        }

        let repCleanliness = try XCTUnwrap(signals.first { $0.type == .repCleanlinessIntro })
        XCTAssertEqual(repCleanliness.value, "75% good-form reps")

        let dashboard = dashboardInsights(history: history, now: now)
        XCTAssertFalse(
            dashboard.isEmpty,
            "Signals: \(signals.map { $0.type.rawValue }.sorted().joined(separator: ", "))"
        )
        XCTAssertTrue(
            dashboard.flatMap(\.evidence).contains { evidence in
                [
                    TrainingSignalType.setupQuality.rawValue,
                    TrainingSignalType.repCleanlinessIntro.rawValue,
                    TrainingSignalType.firstSession.rawValue,
                    TrainingSignalType.personalBaseline.rawValue
                ].contains(evidence.metric)
            },
            "Dashboard metrics: \(dashboard.flatMap(\.evidence).map(\.metric).joined(separator: ", ")); headlines: \(dashboard.map(\.headline).joined(separator: " | "))"
        )
    }

    func testBootstrapSecondSessionRepeatedExerciseProgress() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(
                idSuffix: "9063",
                endedAt: now,
                exerciseType: .squat,
                scores: [88, 87, 86, 85]
            ),
            makeSummary(
                idSuffix: "9064",
                endedAt: date(year: 2026, month: 5, day: 5, hour: 12),
                exerciseType: .squat,
                scores: [78, 79, 80, 81]
            )
        ]

        let signals = trainingSignals(history: history, now: now)
        let signal = try XCTUnwrap(signals.first { $0.type == .repeatExerciseProgress })

        XCTAssertEqual(signal.exerciseType, .squat)
        XCTAssertEqual(signal.confidence, .medium)
        XCTAssertEqual(signal.value, "set 1 87%")
        XCTAssertEqual(signal.comparisonValue, "previous set 1 80%")
        XCTAssertEqual(signal.evidenceRefs.count, 2)
    }

    func testWarmupThirdSessionUsesLatestWorkoutTrendWindow() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "9065", endedAt: now, exerciseType: .squat, reps: 22, averageFormScore: 91),
            makeSummary(idSuffix: "9066", endedAt: date(year: 2026, month: 5, day: 5, hour: 12), exerciseType: .squat, reps: 10, averageFormScore: 80),
            makeSummary(idSuffix: "9067", endedAt: date(year: 2026, month: 5, day: 4, hour: 12), exerciseType: .squat, reps: 9, averageFormScore: 72)
        ]

        let signals = trainingSignals(history: history, now: now)
        let formSignal = try XCTUnwrap(signals.first { $0.type == .formImprovement && $0.exerciseType == nil })
        let volumeSignal = try XCTUnwrap(signals.first { $0.type == .volumeIncrease })

        XCTAssertEqual(formSignal.confidence, .medium)
        XCTAssertEqual(formSignal.evidenceRefs.count, 2)
        XCTAssertEqual(formSignal.value, "91%")
        XCTAssertEqual(formSignal.comparisonValue, "80%")
        XCTAssertEqual(volumeSignal.confidence, .medium)
        XCTAssertEqual(volumeSignal.evidenceRefs.count, 2)
    }

    func testWarmupFifthSessionUsesLatestWorkoutDropSignals() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "9068", endedAt: now, exerciseType: .squat, reps: 5, averageFormScore: 70),
            makeSummary(idSuffix: "9069", endedAt: date(year: 2026, month: 5, day: 5, hour: 12), exerciseType: .squat, reps: 18, averageFormScore: 86),
            makeSummary(idSuffix: "9070", endedAt: date(year: 2026, month: 5, day: 4, hour: 12), exerciseType: .squat, reps: 16, averageFormScore: 84),
            makeSummary(idSuffix: "9071", endedAt: date(year: 2026, month: 5, day: 3, hour: 12), exerciseType: .squat, reps: 14, averageFormScore: 82),
            makeSummary(idSuffix: "9072", endedAt: date(year: 2026, month: 5, day: 2, hour: 12), exerciseType: .squat, reps: 12, averageFormScore: 80)
        ]

        let signals = trainingSignals(history: history, now: now)
        let formSignal = try XCTUnwrap(signals.first { $0.type == .formDropOff && $0.exerciseType == nil })
        let volumeSignal = try XCTUnwrap(signals.first { $0.type == .volumeDrop })

        XCTAssertEqual(formSignal.confidence, .medium)
        XCTAssertEqual(formSignal.evidenceRefs.count, 2)
        XCTAssertEqual(formSignal.value, "70%")
        XCTAssertEqual(formSignal.comparisonValue, "86%")
        XCTAssertEqual(volumeSignal.confidence, .medium)
        XCTAssertEqual(volumeSignal.evidenceRefs.count, 2)
        assertSignal(.personalBaseline, existsIn: signals)
    }

    func testSixSessionsUseStandardThreeWorkoutTrendWindow() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "9073", endedAt: now, exerciseType: .squat, reps: 18, averageFormScore: 92),
            makeSummary(idSuffix: "9074", endedAt: date(year: 2026, month: 5, day: 5, hour: 12), exerciseType: .squat, reps: 18, averageFormScore: 90),
            makeSummary(idSuffix: "9075", endedAt: date(year: 2026, month: 5, day: 4, hour: 12), exerciseType: .squat, reps: 18, averageFormScore: 91),
            makeSummary(idSuffix: "9076", endedAt: date(year: 2026, month: 5, day: 3, hour: 12), exerciseType: .squat, reps: 10, averageFormScore: 74),
            makeSummary(idSuffix: "9077", endedAt: date(year: 2026, month: 5, day: 2, hour: 12), exerciseType: .squat, reps: 10, averageFormScore: 76),
            makeSummary(idSuffix: "9078", endedAt: date(year: 2026, month: 5, day: 1, hour: 12), exerciseType: .squat, reps: 10, averageFormScore: 75)
        ]

        let signals = trainingSignals(history: history, now: now)
        let formSignal = try XCTUnwrap(signals.first { $0.type == .formImprovement && $0.exerciseType == nil })

        XCTAssertEqual(formSignal.confidence, .high)
        XCTAssertEqual(formSignal.evidenceRefs.count, 6)
        XCTAssertNil(signals.first { $0.type == .firstSession })
        XCTAssertNil(signals.first { $0.type == .repeatExerciseProgress })
        assertSignal(.personalBaseline, existsIn: signals)
    }

    func testBlockedProgressionReadinessDoesNotMapToIncreaseTarget() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(
                idSuffix: "9056",
                endedAt: now,
                exerciseType: .squat,
                scores: [86, 84, 83, 82],
                restExtended: true
            ),
            makeSummary(
                idSuffix: "9057",
                endedAt: date(year: 2026, month: 5, day: 5, hour: 12),
                exerciseType: .squat,
                scores: [88, 86, 85, 84]
            )
        ]
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
        let signal = try XCTUnwrap(signals.first { $0.type == .progressionReadiness })

        XCTAssertEqual(signal.value, "not ready to progress")

        let candidate = try XCTUnwrap(
            InsightCandidateBuilder()
                .buildProfileCandidates(profile: profile, trendSnapshot: snapshot, signals: signals, trophies: trophies)
                .first { $0.context["signalType"] == TrainingSignalType.progressionReadiness.rawValue }
        )

        XCTAssertEqual(candidate.candidateAction, .repeatTarget)
    }

    func testRestResponseIgnoresAlreadyCleanSetsAfterExtendedRest() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(
                idSuffix: "9058",
                endedAt: now,
                exerciseType: .pushup,
                sets: [
                    makeSetSummary(exerciseType: .pushup, setIndex: 0, scores: [92, 92, 92], restExtended: true),
                    makeSetSummary(exerciseType: .pushup, setIndex: 1, scores: [89, 89, 89])
                ]
            )
        ]

        let signals = trainingSignals(history: history, now: now)

        XCTAssertNil(signals.first { $0.type == .restResponse })
    }

    func testEarlyRestSkipDoesNotBecomeTargetTooAggressive() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(
                idSuffix: "9059",
                endedAt: now,
                exerciseType: .squat,
                scores: [91, 90, 90, 89],
                skipped: true
            )
        ]

        let signals = trainingSignals(history: history, now: now)

        XCTAssertNil(signals.first { $0.type == .targetFit && $0.value == "too aggressive" })
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

        XCTAssertEqual(
            InsightRanker().rank(
                [generic, specific],
                surface: .workoutSummary,
                profile: makeProfile()
            ).first?.dedupeKey,
            "specific"
        )
    }

    func testRankerAppliesEngagementSignals() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let neutral = makeRankerCandidate(dedupeKey: "neutral")
        let opened = makeRankerCandidate(dedupeKey: "opened")
        let helpful = makeRankerCandidate(dedupeKey: "helpful")
        let notHelpful = makeRankerCandidate(dedupeKey: "not-helpful")
        let dismissed = makeRankerCandidate(dedupeKey: "dismissed")
        let staleDismissed = makeRankerCandidate(dedupeKey: "stale-dismissed")

        var openedRecord = InsightEngagementRecord(dedupeKey: opened.dedupeKey)
        openedRecord.record(.opened, at: now)
        var helpfulRecord = InsightEngagementRecord(dedupeKey: helpful.dedupeKey)
        helpfulRecord.record(.helpful, at: now)
        var notHelpfulRecord = InsightEngagementRecord(dedupeKey: notHelpful.dedupeKey)
        notHelpfulRecord.record(.notHelpful, at: now)
        var dismissedRecord = InsightEngagementRecord(dedupeKey: dismissed.dedupeKey)
        dismissedRecord.record(.dismissed, at: now.addingTimeInterval(-6 * 24 * 60 * 60))
        var staleDismissedRecord = InsightEngagementRecord(dedupeKey: staleDismissed.dedupeKey)
        staleDismissedRecord.record(.dismissed, at: now.addingTimeInterval(-8 * 24 * 60 * 60))

        let records = [
            openedRecord.dedupeKey: openedRecord,
            helpfulRecord.dedupeKey: helpfulRecord,
            notHelpfulRecord.dedupeKey: notHelpfulRecord,
            dismissedRecord.dedupeKey: dismissedRecord,
            staleDismissedRecord.dedupeKey: staleDismissedRecord
        ]
        let ranker = InsightRanker()
        let profile = makeProfile()
        let baseline = ranker.score(neutral, surface: .profile, profile: profile, engagementRecords: records, now: now)

        XCTAssertEqual(
            ranker.score(opened, surface: .profile, profile: profile, engagementRecords: records, now: now) - baseline,
            2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ranker.score(helpful, surface: .profile, profile: profile, engagementRecords: records, now: now) - baseline,
            6,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ranker.score(notHelpful, surface: .profile, profile: profile, engagementRecords: records, now: now) - baseline,
            -12,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ranker.score(dismissed, surface: .profile, profile: profile, engagementRecords: records, now: now) - baseline,
            -20,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ranker.score(staleDismissed, surface: .profile, profile: profile, engagementRecords: records, now: now) - baseline,
            0,
            accuracy: 0.001
        )
    }

    @MainActor
    func testImpressionPreventsSameInsightFromRepeatingEveryLaunch() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let store = InsightStore(fileURL: temporaryInsightURL())
        let insight = makeStoredInsight(now: now)

        let profile = makeProfile()
        let first = store.selectInsights([insight], for: .profile, profile: profile, limit: 1, now: now)
        let presented = try XCTUnwrap(first.first)
        store.recordImpression(presented, on: .profile, now: now)
        let second = store.selectInsights([insight], for: .profile, profile: profile, limit: 1, now: now.addingTimeInterval(60))
        let afterCooldown = store.selectInsights([insight], for: .profile, profile: profile, limit: 1, now: now.addingTimeInterval(24 * 60 * 60))

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

    func testLLMRewriteAppliesSanitizedHeadlineWhenFeatureFlagIsOn() async throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let summary = makeSummary(
            idSuffix: "9090",
            endedAt: now,
            exerciseType: .pushup,
            scores: [92, 91, 90, 89, 88, 86, 84, 70, 68],
            cueMessages: ["Keep your shoulders stacked"]
        )
        let profile = makeProfile()
        let trophies = emptyTrophySnapshot(now: now)
        let trendEngine = TrendEngine(calendar: calendar)
        let snapshot = trendEngine.buildSnapshot(
            history: [summary],
            profile: profile,
            trophies: trophies,
            now: now
        )
        let signals = SignalExtractor(trendEngine: trendEngine).extractSignals(
            snapshot: snapshot,
            history: [summary],
            profile: profile,
            trophies: trophies
        )
        let engine = InsightEngine(
            featureFlags: FeatureFlags(enabled: [.coachInsightLLMRewrite]),
            insightRewriter: StubInsightRewriter { context in
                RewriteResult(
                    headline: "\(context.exerciseDisplayName ?? "Push Ups"): use easier variant after rep 8"
                )
            }
        )

        let insights = await engine.generateWorkoutInsights(
            profile: profile,
            summary: summary,
            plan: makePlan(),
            trendSnapshot: snapshot,
            signals: signals
        )

        let insight = try XCTUnwrap(insights.first { $0.type == .formCorrection })
        XCTAssertEqual(insight.headline, "Push Ups: use easier variant after rep 8")
        XCTAssertTrue(insight.message.contains("rep 8"))
    }

    func testLLMRewriteNoopPathIsByteIdenticalToDeterministicOutput() async throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let summary = makeSummary(
            idSuffix: "9091",
            endedAt: now,
            exerciseType: .pushup,
            scores: [92, 91, 90, 89, 88, 86, 84, 70, 68],
            cueMessages: ["Keep your shoulders stacked"]
        )
        let profile = makeProfile()
        let trophies = emptyTrophySnapshot(now: now)
        let trendEngine = TrendEngine(calendar: calendar)
        let snapshot = trendEngine.buildSnapshot(
            history: [summary],
            profile: profile,
            trophies: trophies,
            now: now
        )
        let signals = SignalExtractor(trendEngine: trendEngine).extractSignals(
            snapshot: snapshot,
            history: [summary],
            profile: profile,
            trophies: trophies
        )
        let noopRewriteEngine = InsightEngine(
            featureFlags: .default,
            insightRewriter: StubInsightRewriter { context in
                RewriteResult(
                    headline: "\(context.exerciseDisplayName ?? "Push Ups"): use easier variant after rep 8"
                )
            }
        )

        let deterministic = workoutInsights(summary: summary, history: [summary], now: now)
        let noopRewrite = await noopRewriteEngine.generateWorkoutInsights(
            profile: profile,
            summary: summary,
            plan: makePlan(),
            trendSnapshot: snapshot,
            signals: signals
        )

        XCTAssertEqual(try encodedJSON(deterministic), try encodedJSON(noopRewrite))
    }

    func testLLMRewriteRejectsRewriteMissingEvidenceAnchor() async throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let summary = makeSummary(
            idSuffix: "9092",
            endedAt: now,
            exerciseType: .pushup,
            scores: [92, 91, 90, 89, 88, 86, 84, 70, 68],
            cueMessages: ["Keep your shoulders stacked"]
        )
        let profile = makeProfile()
        let trophies = emptyTrophySnapshot(now: now)
        let trendEngine = TrendEngine(calendar: calendar)
        let snapshot = trendEngine.buildSnapshot(
            history: [summary],
            profile: profile,
            trophies: trophies,
            now: now
        )
        let signals = SignalExtractor(trendEngine: trendEngine).extractSignals(
            snapshot: snapshot,
            history: [summary],
            profile: profile,
            trophies: trophies
        )
        let deterministic = workoutInsights(summary: summary, history: [summary], now: now)
        let engine = InsightEngine(
            featureFlags: FeatureFlags(enabled: [.coachInsightLLMRewrite]),
            insightRewriter: StubInsightRewriter { _ in
                RewriteResult(
                    headline: "Push Ups: use easier variant today",
                    message: "Push Ups should use an easier variant today.",
                    shortMessage: "Push Ups: use easier variant."
                )
            }
        )

        let rewritten = await engine.generateWorkoutInsights(
            profile: profile,
            summary: summary,
            plan: makePlan(),
            trendSnapshot: snapshot,
            signals: signals
        )

        XCTAssertEqual(
            rewritten.first { $0.type == .formCorrection }?.headline,
            deterministic.first { $0.type == .formCorrection }?.headline
        )
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
            store.selectInsights([insight], for: .profile, profile: makeProfile(), limit: 1, now: now).isEmpty
        )
    }
}

private extension InsightEngineTests {
    struct StubInsightRewriter: InsightRewriter {
        let result: (InsightLLMContext) -> RewriteResult?

        func rewrite(_ context: InsightLLMContext) async throws -> RewriteResult? {
            result(context)
        }
    }

    func encodedJSON(_ insights: [AIInsight]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(insights)
        return String(data: data, encoding: .utf8) ?? ""
    }

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
            profile: profile,
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

    func trainingSignals(
        history: [WorkoutSessionSummary],
        trophies: TrophyProgressSnapshot? = nil,
        now: Date
    ) -> [UserTrainingSignal] {
        let profile = makeProfile()
        let resolvedTrophies = trophies ?? emptyTrophySnapshot(now: now)
        let trendEngine = TrendEngine(calendar: calendar)
        let snapshot = trendEngine.buildSnapshot(
            history: history,
            profile: profile,
            trophies: resolvedTrophies,
            now: now
        )
        return SignalExtractor(trendEngine: trendEngine).extractSignals(
            snapshot: snapshot,
            history: history,
            profile: profile,
            trophies: resolvedTrophies
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

    func assertNoUnsupportedPhysiologyCopy(in signals: [UserTrainingSignal]) {
        let text = signals.map { "\($0.title) \($0.value) \($0.comparisonValue ?? "")" }
            .joined(separator: " ")
            .lowercased()
        XCTAssertFalse(text.contains("heart rate"))
        XCTAssertFalse(text.contains("bpm"))
        XCTAssertFalse(text.contains("calorie"))
        XCTAssertFalse(text.contains("weight loss"))
        XCTAssertFalse(text.contains("fat loss"))
    }

    func assertSignal(
        _ type: TrainingSignalType,
        existsIn signals: [UserTrainingSignal],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotNil(
            signals.first { $0.type == type },
            "Expected \(type.rawValue). Got: \(signals.map { $0.type.rawValue }.sorted().joined(separator: ", "))",
            file: file,
            line: line
        )
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

    func makeRankerCandidate(dedupeKey: String) -> InsightCandidate {
        InsightCandidate(
            type: .formCorrection,
            candidateHeadline: "Cue focus",
            candidateAction: .focusCue,
            evidence: [
                InsightEvidence(
                    metric: "repeatedCue",
                    value: "Brace first",
                    exerciseType: .squat,
                    confidence: 0.9
                )
            ],
            rawScore: 80,
            confidence: 0.9,
            surfaces: [.profile],
            severity: .caution,
            emotionalIntent: .giveToughLove,
            relatedExerciseType: .squat,
            createdAt: date(year: 2026, month: 5, day: 6, hour: 12),
            dedupeKey: dedupeKey
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
        durationSeconds: Int = 600,
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
            startedAt: endedAt.addingTimeInterval(-TimeInterval(durationSeconds)),
            endedAt: endedAt,
            durationSeconds: durationSeconds,
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
