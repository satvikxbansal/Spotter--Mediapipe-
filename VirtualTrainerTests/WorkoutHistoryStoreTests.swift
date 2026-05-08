import XCTest
@testable import VirtualTrainer

@MainActor
final class WorkoutHistoryStoreTests: XCTestCase {
    func testSavePlannedWorkoutSummary() throws {
        let store = WorkoutHistoryStore(fileURL: temporaryHistoryURL())
        let plan = makePlan()
        let setSummary = makeSetSummary(planId: plan.id)
        let summary = WorkoutSessionSummary.plannedWorkout(
            plan: plan,
            startedAt: Date(timeIntervalSince1970: 1_776_200_000),
            completedSets: [setSummary],
            restOutcomes: [
                setSummary.id: PlannedWorkoutRestResult(restExtended: true, skipped: false)
            ],
            completedAt: Date(timeIntervalSince1970: 1_776_200_060),
            createdAt: Date(timeIntervalSince1970: 1_776_200_061)
        )

        XCTAssertTrue(store.addSummary(summary))

        let fetched = try XCTUnwrap(store.fetchSummary(id: summary.id))
        XCTAssertEqual(fetched.mode, .plannedWorkout)
        XCTAssertEqual(fetched.planId, plan.id)
        XCTAssertEqual(fetched.title, "Phase 10 Strength")
        XCTAssertEqual(fetched.totalReps, 12)
        XCTAssertEqual(fetched.exerciseSummaries.first?.restExtended, true)
        XCTAssertEqual(fetched.completionPercent, 1)
    }

    func testSaveFreeAnalysisSummary() throws {
        let store = WorkoutHistoryStore(fileURL: temporaryHistoryURL())
        let summary = WorkoutSessionSummary.freeAnalysis(
            from: makeFreeAnalysisSummary(),
            createdAt: Date(timeIntervalSince1970: 1_776_200_120)
        )

        XCTAssertTrue(store.addSummary(summary))

        let fetched = try XCTUnwrap(store.fetchSummary(id: summary.id))
        XCTAssertEqual(fetched.mode, .freeAnalysis)
        XCTAssertNil(fetched.planId)
        XCTAssertEqual(fetched.title, ExerciseType.pushup.displayName)
        XCTAssertEqual(fetched.totalReps, 15)
        XCTAssertEqual(fetched.averageFormScore, 86)
        XCTAssertEqual(fetched.topCue?.cueMessage, "Keep your core braced")
    }

    func testFetchRecentHistorySortsNewestFirst() throws {
        let store = WorkoutHistoryStore(fileURL: temporaryHistoryURL())
        let older = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001") ?? UUID(),
            title: "Older",
            endedAt: Date(timeIntervalSince1970: 1_776_200_000)
        )
        let newest = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001002") ?? UUID(),
            title: "Newest",
            endedAt: Date(timeIntervalSince1970: 1_776_200_200)
        )
        let middle = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001003") ?? UUID(),
            title: "Middle",
            endedAt: Date(timeIntervalSince1970: 1_776_200_100)
        )

        store.addSummary(older)
        store.addSummary(newest)
        store.addSummary(middle)

        let recent = store.fetchRecentSummaries(limit: 2)

        XCTAssertEqual(recent.map(\.title), ["Newest", "Middle"])
    }

    func testSummaryCodableRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let summary = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001004") ?? UUID(),
            title: "Roundtrip",
            endedAt: Date(timeIntervalSince1970: 1_776_200_300)
        )

        let data = try encoder.encode(summary)
        let decoded = try decoder.decode(WorkoutSessionSummary.self, from: data)

        XCTAssertEqual(decoded, summary)
        XCTAssertNil(decoded.deletedAt)
    }

    func testSummaryTombstoneHelpersAndCodableRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let deletedAt = Date(timeIntervalSince1970: 1_776_201_000)
        let summary = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001008") ?? UUID(),
            title: "Deleted Roundtrip",
            endedAt: Date(timeIntervalSince1970: 1_776_200_300)
        )

        let deleted = summary.markedDeleted(at: deletedAt)
        let decoded = try decoder.decode(WorkoutSessionSummary.self, from: try encoder.encode(deleted))

        XCTAssertTrue(deleted.isDeleted)
        XCTAssertEqual(decoded.deletedAt, deletedAt)
        XCTAssertNil(decoded.restored().deletedAt)
        XCTAssertFalse(decoded.restored().isDeleted)
    }

    func testOldWorkoutSessionSummaryJSONDecodesWithEvidenceDefaults() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000001040",
          "mode": "plannedWorkout",
          "planId": "00000000-0000-0000-0000-000000001041",
          "title": "Legacy Strength",
          "goal": "Build clean strength.",
          "coach": "good",
          "startedAt": "2026-05-05T10:00:00Z",
          "endedAt": "2026-05-05T10:20:00Z",
          "durationSeconds": 1200,
          "totalReps": 12,
          "totalHoldSeconds": 0,
          "averageFormScore": 88,
          "completionPercent": 1,
          "exerciseSummaries": [
            {
              "exerciseType": "squat",
              "setIndex": 0,
              "achievedReps": 12,
              "achievedHoldSeconds": 0,
              "averageFormScore": 88,
              "cueEvents": [
                {
                  "timestamp": "2026-05-05T10:05:00Z",
                  "exerciseType": "squat",
                  "cueMessage": "Drive through the floor",
                  "severity": "info",
                  "metricKey": null
                }
              ],
              "restExtended": false,
              "skipped": false
            }
          ],
          "topCue": null,
          "effortSummary": "Peak effort reached 50%. Solid working intensity.",
          "createdAt": "2026-05-05T10:20:01Z"
        }
        """.data(using: .utf8) ?? Data()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(WorkoutSessionSummary.self, from: json)

        XCTAssertEqual(decoded.summarySchemaVersion, 1)
        XCTAssertEqual(decoded.workoutOutcome, .completed)
        XCTAssertNil(decoded.structuredEffortSummary)
        XCTAssertEqual(decoded.totalGoodFormReps, 0)
        XCTAssertEqual(decoded.totalExcellentFormReps, 0)
        XCTAssertEqual(decoded.totalHighSeverityCues, 0)
        XCTAssertTrue(decoded.exerciseSummaries.first?.repQualityEvents.isEmpty ?? false)
        XCTAssertNotNil(decoded.exerciseSummaries.first?.cueEvents.first?.id)
        XCTAssertNil(decoded.deletedAt)
    }

    func testOlderWorkoutSessionSummaryJSONDecodesWithoutCreatedAt() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000001045",
          "mode": "freeAnalysis",
          "title": "Push-Up",
          "coach": "good",
          "startedAt": "2026-05-05T10:00:00Z",
          "endedAt": "2026-05-05T10:03:00Z",
          "durationSeconds": 180,
          "totalReps": 8,
          "totalHoldSeconds": 0,
          "averageFormScore": 82,
          "completionPercent": null,
          "exerciseSummaries": [
            {
              "exerciseType": "pushup",
              "achievedReps": 8,
              "achievedHoldSeconds": 0,
              "averageFormScore": 82
            }
          ],
          "topCue": null,
          "effortSummary": "No face-effort signal was captured for this session."
        }
        """.data(using: .utf8) ?? Data()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(WorkoutSessionSummary.self, from: json)

        XCTAssertEqual(decoded.createdAt, decoded.endedAt)
        XCTAssertEqual(decoded.workoutOutcome, .freeAnalysisSaved)
        XCTAssertEqual(decoded.exerciseSummaries.first?.cueEvents, [])
        XCTAssertNil(decoded.deletedAt)
    }

    func testRepQualityEventCodableRoundtrip() throws {
        let event = RepQualityEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001050") ?? UUID(),
            exerciseType: .pushup,
            setIndex: 1,
            repIndex: 4,
            timestamp: Date(timeIntervalSince1970: 1_776_300_000),
            secondsIntoSet: 18.4,
            formScore: 91,
            formGrade: "A",
            phase: "up",
            cueMessageNearRep: "Keep your core braced",
            cueSeverityNearRep: .warning,
            effortAtRep: 0.62
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(event)
        let decoded = try decoder.decode(RepQualityEvent.self, from: data)

        XCTAssertEqual(decoded, event)
    }

    func testSetQualitySummaryClassifiesTrendAndCountsFormReps() {
        let improved = SetQualitySummary.build(
            repQualityEvents: [
                makeRepEvent(repIndex: 1, score: 70),
                makeRepEvent(repIndex: 2, score: 74),
                makeRepEvent(repIndex: 3, score: 86),
                makeRepEvent(repIndex: 4, score: 92, cue: "Brace", severity: .warning)
            ],
            cueEvents: [
                CueEvent(
                    timestamp: Date(timeIntervalSince1970: 1_776_300_010),
                    exerciseType: .squat,
                    cueMessage: "Brace",
                    severity: .critical
                )
            ]
        )
        let faded = SetQualitySummary.build(
            repQualityEvents: [
                makeRepEvent(repIndex: 1, score: 92),
                makeRepEvent(repIndex: 2, score: 90),
                makeRepEvent(repIndex: 3, score: 78),
                makeRepEvent(repIndex: 4, score: 74)
            ]
        )
        let stable = SetQualitySummary.build(
            repQualityEvents: [
                makeRepEvent(repIndex: 1, score: 83),
                makeRepEvent(repIndex: 2, score: 85),
                makeRepEvent(repIndex: 3, score: 84),
                makeRepEvent(repIndex: 4, score: 86)
            ]
        )

        XCTAssertEqual(improved.qualityTrend, .improved)
        XCTAssertEqual(improved.goodFormReps, 2)
        XCTAssertEqual(improved.excellentFormReps, 1)
        XCTAssertEqual(improved.highSeverityCueCount, 1)
        XCTAssertEqual(improved.mostRepeatedCue, "Brace")
        XCTAssertEqual(faded.qualityTrend, .faded)
        XCTAssertEqual(stable.qualityTrend, .stable)
    }

    func testAggregateStats() {
        let store = WorkoutHistoryStore(fileURL: temporaryHistoryURL())
        store.addSummary(
            makeStoredSummary(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001005") ?? UUID(),
                title: "Strength",
                endedAt: Date(timeIntervalSince1970: 1_776_200_400),
                totalReps: 20,
                averageFormScore: 90,
                completionPercent: 1
            )
        )
        store.addSummary(
            makeStoredSummary(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001006") ?? UUID(),
                mode: .freeAnalysis,
                title: "Form Check",
                endedAt: Date(timeIntervalSince1970: 1_776_200_500),
                totalReps: 10,
                averageFormScore: 80,
                completionPercent: nil
            )
        )

        let stats = store.aggregateStats()

        XCTAssertEqual(stats.sessionCount, 2)
        XCTAssertEqual(stats.plannedWorkoutCount, 1)
        XCTAssertEqual(stats.freeAnalysisCount, 1)
        XCTAssertEqual(stats.totalReps, 30)
        XCTAssertEqual(stats.averageFormScore, 85)
        XCTAssertEqual(stats.averageCompletionPercent, 1)
        XCTAssertEqual(stats.mostTrainedExerciseType, .squat)
    }

    func testAggregateStatsComputesEvidenceTotalsAndStreaks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: 12)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let twoDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today))
        let fourDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -4, to: today))
        let store = WorkoutHistoryStore(fileURL: temporaryHistoryURL(), calendar: calendar)

        store.addSummary(makeEvidenceSummary(idSuffix: "1061", endedAt: fourDaysAgo, scores: [72, 80], highSeverityCues: 0))
        store.addSummary(makeEvidenceSummary(idSuffix: "1062", endedAt: twoDaysAgo, scores: [78, 82], highSeverityCues: 1))
        store.addSummary(makeEvidenceSummary(idSuffix: "1063", endedAt: yesterday, scores: [84, 91], highSeverityCues: 1))
        store.addSummary(makeEvidenceSummary(idSuffix: "1064", endedAt: today, scores: [88, 94], highSeverityCues: 0))

        let stats = store.aggregateStats(now: today)

        XCTAssertEqual(stats.currentStreak, 3)
        XCTAssertEqual(stats.longestStreak, 3)
        XCTAssertEqual(stats.workoutsThisWeek, 3)
        XCTAssertEqual(stats.totalGoodFormReps, 6)
        XCTAssertEqual(stats.totalExcellentFormReps, 2)
        XCTAssertEqual(stats.totalHighSeverityCues, 2)
        XCTAssertEqual(stats.mostImprovedExerciseType, .squat)
    }

    func testPlannedWorkoutSummaryIncludesRepEvidence() throws {
        let plan = makePlan()
        let setSummary = makeSetSummary(
            planId: plan.id,
            repQualityEvents: [
                makeRepEvent(repIndex: 1, score: 84),
                makeRepEvent(repIndex: 2, score: 93, effort: 0.7)
            ]
        )

        let summary = WorkoutSessionSummary.plannedWorkout(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001070") ?? UUID(),
            plan: plan,
            startedAt: Date(timeIntervalSince1970: 1_776_200_000),
            completedSets: [setSummary],
            completedAt: Date(timeIntervalSince1970: 1_776_200_060)
        )

        XCTAssertEqual(summary.summarySchemaVersion, WorkoutSessionSummary.currentSchemaVersion)
        XCTAssertEqual(summary.workoutOutcome, .completed)
        XCTAssertEqual(summary.planTitle, plan.title)
        XCTAssertEqual(summary.exerciseSummaries.first?.repQualityEvents.count, 2)
        XCTAssertEqual(summary.exerciseSummaries.first?.qualitySummary?.goodFormReps, 2)
        XCTAssertEqual(summary.exerciseSummaries.first?.qualitySummary?.excellentFormReps, 1)
        XCTAssertEqual(summary.totalGoodFormReps, 2)
        XCTAssertEqual(summary.totalExcellentFormReps, 1)
        XCTAssertEqual(summary.structuredEffortSummary?.source, .faceBlendshapeProxy)
        XCTAssertEqual(summary.exerciseSummaries.first?.completionSource, .targetMet)
    }

    func testFreeAnalysisSummaryIncludesRepEvidence() {
        let freeSummary = makeFreeAnalysisSummary(
            repQualityEvents: [
                makeRepEvent(exerciseType: .pushup, setIndex: nil, repIndex: 1, score: 81),
                makeRepEvent(exerciseType: .pushup, setIndex: nil, repIndex: 2, score: 94)
            ]
        )

        let summary = WorkoutSessionSummary.freeAnalysis(from: freeSummary)

        XCTAssertEqual(summary.mode, .freeAnalysis)
        XCTAssertEqual(summary.workoutOutcome, .freeAnalysisSaved)
        XCTAssertEqual(summary.exerciseSummaries.first?.repQualityEvents.count, 2)
        XCTAssertEqual(summary.exerciseSummaries.first?.qualitySummary?.goodFormReps, 2)
        XCTAssertEqual(summary.totalExcellentFormReps, 1)
    }

    func testNoDuplicateSaveWhenPlannedSummaryIsRequestedMultipleTimes() throws {
        var coordinator = PlannedWorkoutCoordinator(
            plan: makePlan(),
            startedAt: Date(timeIntervalSince1970: 1_776_200_000),
            historySummaryId: UUID(uuidString: "00000000-0000-0000-0000-000000001080") ?? UUID()
        )
        let store = WorkoutHistoryStore(fileURL: temporaryHistoryURL())
        coordinator.startSession()
        let context = try XCTUnwrap(coordinator.currentContext)
        XCTAssertTrue(
            coordinator.completeCurrentSet(
                with: PlannedWorkoutSetSummary(
                    planId: context.planId,
                    exerciseType: context.exerciseType,
                    target: context.target,
                    setIndex: context.setIndex,
                    totalSets: context.totalSets,
                    exerciseIndex: context.exerciseIndex,
                    totalExercises: context.totalExercises,
                    duration: 55,
                    reps: 12,
                    holdDuration: 0,
                    latestFormScore: formScore(92),
                    peakEffort: 0.4,
                    lastCue: nil,
                    completionSource: .targetMet
                )
            )
        )

        let firstSummary = coordinator.workoutSessionSummary()
        let secondSummary = coordinator.workoutSessionSummary()
        XCTAssertTrue(store.addSummary(firstSummary))
        XCTAssertTrue(store.addSummary(secondSummary))

        XCTAssertEqual(firstSummary.id, secondSummary.id)
        XCTAssertEqual(store.fetchRecentSummaries().count, 1)
    }

    func testAddSummaryUpsertsByID() throws {
        let store = WorkoutHistoryStore(fileURL: temporaryHistoryURL())
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000001085") ?? UUID()
        let first = makeStoredSummary(
            id: id,
            title: "Original",
            endedAt: Date(timeIntervalSince1970: 1_776_200_000),
            totalReps: 8
        )
        let replacement = makeStoredSummary(
            id: id,
            title: "Replacement",
            endedAt: Date(timeIntervalSince1970: 1_776_200_100),
            totalReps: 16
        )

        XCTAssertTrue(store.addSummary(first))
        XCTAssertTrue(store.addSummary(replacement))

        XCTAssertEqual(store.fetchRecentSummaries().count, 1)
        XCTAssertEqual(store.fetchSummary(id: id)?.title, "Replacement")
        XCTAssertEqual(store.fetchSummary(id: id)?.totalReps, 16)
    }

    func testDeleteSummaryHidesVisibleQueriesButKeepsTombstoneAndRestoreReturnsIt() throws {
        let store = WorkoutHistoryStore(fileURL: temporaryHistoryURL())
        let deletedAt = Date(timeIntervalSince1970: 1_776_201_100)
        let summary = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001086") ?? UUID(),
            title: "Soft Delete",
            endedAt: Date(timeIntervalSince1970: 1_776_200_000)
        )

        XCTAssertTrue(store.addSummary(summary))
        XCTAssertEqual(store.summaries.map(\.id), [summary.id])
        XCTAssertTrue(store.deleteSummary(id: summary.id, deletedAt: deletedAt))

        XCTAssertTrue(store.summaries.isEmpty)
        XCTAssertTrue(store.fetchRecentSummaries().isEmpty)
        XCTAssertNil(store.fetchSummary(id: summary.id))
        XCTAssertEqual(store.fetchSummaryIncludingDeleted(id: summary.id)?.deletedAt, deletedAt)
        XCTAssertEqual(store.allSummariesIncludingTombstones().map(\.id), [summary.id])
        XCTAssertEqual(store.fetchDeletedSummaries().map(\.id), [summary.id])
        XCTAssertEqual(store.fetchDirtyOrDeletedSummaries().map(\.id), [summary.id])

        XCTAssertTrue(store.restoreSummary(id: summary.id))
        XCTAssertEqual(store.summaries.map(\.id), [summary.id])
        XCTAssertNil(store.fetchSummary(id: summary.id)?.deletedAt)
    }

    func testPurgeTombstonesRemovesOnlyDeletedRecordsOlderThanCutoff() throws {
        let store = WorkoutHistoryStore(fileURL: temporaryHistoryURL())
        let cutoff = Date(timeIntervalSince1970: 1_776_201_000)
        let oldDeleted = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001087") ?? UUID(),
            title: "Old Deleted",
            endedAt: Date(timeIntervalSince1970: 1_776_200_000)
        ).markedDeleted(at: cutoff.addingTimeInterval(-1))
        let recentDeleted = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001088") ?? UUID(),
            title: "Recent Deleted",
            endedAt: Date(timeIntervalSince1970: 1_776_200_100)
        ).markedDeleted(at: cutoff)
        let active = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001089") ?? UUID(),
            title: "Active",
            endedAt: Date(timeIntervalSince1970: 1_776_200_200)
        )

        XCTAssertTrue(store.addSummary(oldDeleted))
        XCTAssertTrue(store.addSummary(recentDeleted))
        XCTAssertTrue(store.addSummary(active))

        XCTAssertEqual(store.purgeTombstones(olderThan: cutoff), 1)

        XCTAssertNil(store.fetchSummaryIncludingDeleted(id: oldDeleted.id))
        XCTAssertNotNil(store.fetchSummaryIncludingDeleted(id: recentDeleted.id))
        XCTAssertNotNil(store.fetchSummary(id: active.id))
        XCTAssertEqual(store.fetchDeletedSummaries().map(\.id), [recentDeleted.id])
    }

    func testStatsAndRecentHistoryItemsIgnoreDeletedWorkouts() throws {
        let store = WorkoutHistoryStore(fileURL: temporaryHistoryURL())
        let visible = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001090") ?? UUID(),
            title: "Visible",
            endedAt: Date(timeIntervalSince1970: 1_776_200_300),
            totalReps: 10,
            averageFormScore: 90
        )
        let deleted = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001091") ?? UUID(),
            title: "Deleted",
            endedAt: Date(timeIntervalSince1970: 1_776_200_400),
            totalReps: 50,
            averageFormScore: 50
        )

        XCTAssertTrue(store.addSummary(visible))
        XCTAssertTrue(store.addSummary(deleted))
        XCTAssertTrue(store.deleteSummary(id: deleted.id, deletedAt: Date(timeIntervalSince1970: 1_776_201_200)))

        let stats = store.aggregateStats(now: Date(timeIntervalSince1970: 1_776_200_500))
        XCTAssertEqual(stats.sessionCount, 1)
        XCTAssertEqual(stats.totalReps, 10)
        XCTAssertEqual(stats.averageFormScore, 90)
        XCTAssertEqual(store.recentWorkoutHistoryItems(limit: 10).map(\.id), [visible.id])
    }

    func testRemoveSummariesForDebugPhysicallyRemovesOnlyMatchingRecords() throws {
        let url = temporaryHistoryURL()
        let store = WorkoutHistoryStore(fileURL: url)
        let sample = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001093") ?? UUID(),
            title: "Sample",
            endedAt: Date(timeIntervalSince1970: 1_776_200_500)
        )
        let kept = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001094") ?? UUID(),
            title: "Real",
            endedAt: Date(timeIntervalSince1970: 1_776_200_600)
        )

        XCTAssertTrue(store.addSummary(sample))
        XCTAssertTrue(store.addSummary(kept))
        XCTAssertTrue(store.removeSummariesForDebug(ids: [sample.id]))

        XCTAssertNil(store.fetchSummary(id: sample.id))
        XCTAssertNil(store.fetchSummaryIncludingDeleted(id: sample.id))
        XCTAssertEqual(store.fetchRecentSummaries().map(\.id), [kept.id])

        let reloaded = WorkoutHistoryStore(fileURL: url)
        XCTAssertNil(reloaded.fetchSummaryIncludingDeleted(id: sample.id))
        XCTAssertEqual(reloaded.fetchRecentSummaries().map(\.id), [kept.id])
    }

    func testPersistedJSONKeepsTombstonesAfterReload() throws {
        let url = temporaryHistoryURL()
        let store = WorkoutHistoryStore(fileURL: url)
        let deletedAt = Date(timeIntervalSince1970: 1_776_201_300)
        let summary = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001092") ?? UUID(),
            title: "Reload Tombstone",
            endedAt: Date(timeIntervalSince1970: 1_776_200_500)
        )

        XCTAssertTrue(store.addSummary(summary))
        XCTAssertTrue(store.deleteSummary(id: summary.id, deletedAt: deletedAt))

        let reloaded = WorkoutHistoryStore(fileURL: url)

        XCTAssertTrue(reloaded.summaries.isEmpty)
        XCTAssertNil(reloaded.fetchSummary(id: summary.id))
        XCTAssertEqual(reloaded.fetchSummaryIncludingDeleted(id: summary.id)?.deletedAt, deletedAt)
        XCTAssertEqual(reloaded.allSummariesIncludingTombstones().map(\.id), [summary.id])
    }

    func testSameOperationIdAddsSummaryOnlyOnce() throws {
        let url = temporaryHistoryURL()
        let journal = LocalWriteJournal(
            fileURL: LocalWriteJournal.defaultJournalURL(alongside: url)
        )
        let store = WorkoutHistoryStore(fileURL: url, accountId: "history-retry", writeJournal: journal)
        let summaryId = UUID(uuidString: "00000000-0000-0000-0000-000000001093") ?? UUID()
        let operationId = UUID(uuidString: "00000000-0000-0000-0000-00000000B001") ?? UUID()
        let first = makeStoredSummary(
            id: summaryId,
            title: "First Write",
            endedAt: Date(timeIntervalSince1970: 1_776_200_500)
        )
        let retryPayload = makeStoredSummary(
            id: summaryId,
            title: "Retry Should Not Replace",
            endedAt: Date(timeIntervalSince1970: 1_776_200_700),
            totalReps: 30
        )

        XCTAssertTrue(store.addSummary(first, operationId: operationId))
        XCTAssertTrue(store.addSummary(retryPayload, operationId: operationId))

        let fetched = try XCTUnwrap(store.fetchSummary(id: summaryId))
        XCTAssertEqual(store.fetchRecentSummaries().map(\.id), [summaryId])
        XCTAssertEqual(fetched.title, "First Write")
        XCTAssertEqual(fetched.totalReps, 12)
        XCTAssertEqual(fetched.syncMetadata.pendingOperationId, operationId)
    }

    func testDifferentOperationIdUpdatesSummaryNormally() throws {
        let url = temporaryHistoryURL()
        let journal = LocalWriteJournal(
            fileURL: LocalWriteJournal.defaultJournalURL(alongside: url)
        )
        let store = WorkoutHistoryStore(fileURL: url, accountId: "history-retry", writeJournal: journal)
        let summaryId = UUID(uuidString: "00000000-0000-0000-0000-000000001094") ?? UUID()
        let firstOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000B002") ?? UUID()
        let secondOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000B003") ?? UUID()
        let first = makeStoredSummary(
            id: summaryId,
            title: "Original Write",
            endedAt: Date(timeIntervalSince1970: 1_776_200_500)
        )
        let replacement = makeStoredSummary(
            id: summaryId,
            title: "Replacement Write",
            endedAt: Date(timeIntervalSince1970: 1_776_200_700),
            totalReps: 30
        )

        XCTAssertTrue(store.addSummary(first, operationId: firstOperationId))
        XCTAssertTrue(store.addSummary(replacement, operationId: secondOperationId))

        let fetched = try XCTUnwrap(store.fetchSummary(id: summaryId))
        XCTAssertEqual(store.fetchRecentSummaries().map(\.id), [summaryId])
        XCTAssertEqual(fetched.title, "Replacement Write")
        XCTAssertEqual(fetched.totalReps, 30)
        XCTAssertEqual(fetched.syncMetadata.pendingOperationId, secondOperationId)
    }

    func testFailedSaveDoesNotExposeUnsavedSummary() throws {
        let blockedParentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: blockedParentURL)

        let store = WorkoutHistoryStore(
            fileURL: blockedParentURL.appendingPathComponent("WorkoutHistory.json")
        )
        let summary = makeStoredSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001007") ?? UUID(),
            title: "Unwritable",
            endedAt: Date(timeIntervalSince1970: 1_776_200_600)
        )

        XCTAssertFalse(store.addSummary(summary))
        XCTAssertNil(store.fetchSummary(id: summary.id))
        XCTAssertTrue(store.fetchRecentSummaries().isEmpty)
        XCTAssertNotNil(store.persistenceError)
    }
}

private extension WorkoutHistoryStoreTests {
    func makePlan() -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001010") ?? UUID(),
            title: "Phase 10 Strength",
            subtitle: "History test plan",
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
                            sets: [PlannedSet(setIndex: 1, target: .reps(12))],
                            restSeconds: 45,
                            coachingFocus: "Depth and control.",
                            cameraPosition: .front,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: Date(timeIntervalSince1970: 1_776_200_000),
            planReason: "Stable fixture for Phase 10 history tests.",
            source: .generatedLocal
        )
    }

    func makeSetSummary(
        planId: UUID,
        repQualityEvents: [RepQualityEvent] = []
    ) -> PlannedWorkoutSetSummary {
        let cue = CueEvent(
            timestamp: Date(timeIntervalSince1970: 1_776_200_045),
            exerciseType: .squat,
            cueMessage: "Drive through the floor",
            severity: .info
        )

        return PlannedWorkoutSetSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001011") ?? UUID(),
            planId: planId,
            exerciseType: .squat,
            target: .reps(12),
            setIndex: 0,
            totalSets: 1,
            exerciseIndex: 0,
            totalExercises: 1,
            completedAt: Date(timeIntervalSince1970: 1_776_200_060),
            duration: 55,
            reps: 12,
            holdDuration: 0,
            latestFormScore: formScore(92),
            peakEffort: 0.48,
            lastCue: CoachCue(message: cue.cueMessage, severity: cue.severity),
            cueEvents: [cue],
            completionSource: .targetMet,
            repQualityEvents: repQualityEvents
        )
    }

    func makeFreeAnalysisSummary(
        repQualityEvents: [RepQualityEvent] = []
    ) -> FreeAnalysisSummary {
        let cue = CoachCue(message: "Keep your core braced", severity: .warning)
        return FreeAnalysisSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001012") ?? UUID(),
            exerciseType: .pushup,
            coach: .drill,
            startedAt: Date(timeIntervalSince1970: 1_776_200_000),
            endedAt: Date(timeIntervalSince1970: 1_776_200_090),
            duration: 90,
            reps: 15,
            holdDuration: 0,
            latestFormScore: formScore(86),
            peakEffort: 0.62,
            lastCue: cue,
            cueEvents: [
                CueEvent(
                    timestamp: Date(timeIntervalSince1970: 1_776_200_044),
                    exerciseType: .pushup,
                    cueMessage: cue.message,
                    severity: cue.severity
                )
            ],
            repQualityEvents: repQualityEvents
        )
    }

    func makeStoredSummary(
        id: UUID,
        mode: WorkoutSessionSummaryMode = .plannedWorkout,
        title: String,
        endedAt: Date,
        totalReps: Int = 12,
        averageFormScore: Double? = 88,
        completionPercent: Double? = 1
    ) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            id: id,
            mode: mode,
            planId: mode == .plannedWorkout ? UUID(uuidString: "00000000-0000-0000-0000-000000001020") : nil,
            title: title,
            goal: mode == .plannedWorkout ? "Build clean strength." : nil,
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            durationSeconds: 600,
            totalReps: totalReps,
            totalHoldSeconds: 0,
            averageFormScore: averageFormScore,
            completionPercent: completionPercent,
            exerciseSummaries: [
                ExerciseSetSummary(
                    exerciseType: .squat,
                    setIndex: mode == .plannedWorkout ? 0 : nil,
                    target: mode == .plannedWorkout ? .reps(totalReps) : nil,
                    achievedReps: totalReps,
                    achievedHoldSeconds: 0,
                    averageFormScore: averageFormScore
                )
            ],
            topCue: nil,
            effortSummary: "Peak effort reached 50%. Solid working intensity.",
            createdAt: endedAt
        )
    }

    func makeEvidenceSummary(
        idSuffix: String,
        endedAt: Date,
        scores: [Int],
        highSeverityCues: Int
    ) -> WorkoutSessionSummary {
        let events = scores.enumerated().map { index, score in
            makeRepEvent(
                repIndex: index + 1,
                score: score,
                cue: index < highSeverityCues ? "Brace" : nil,
                severity: index < highSeverityCues ? .warning : nil
            )
        }
        let cueEvents = (0..<highSeverityCues).map { index in
            CueEvent(
                timestamp: endedAt.addingTimeInterval(TimeInterval(index)),
                exerciseType: .squat,
                cueMessage: "Brace",
                severity: .warning
            )
        }
        let qualitySummary = SetQualitySummary.build(
            repQualityEvents: events,
            cueEvents: cueEvents
        )

        return WorkoutSessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000\(idSuffix)") ?? UUID(),
            mode: .plannedWorkout,
            planId: UUID(uuidString: "00000000-0000-0000-0000-000000001090"),
            title: "Evidence",
            goal: "Build clean strength.",
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            durationSeconds: 600,
            totalReps: scores.count,
            totalHoldSeconds: 0,
            averageFormScore: qualitySummary.averageFormScore,
            completionPercent: 1,
            exerciseSummaries: [
                ExerciseSetSummary(
                    exerciseType: .squat,
                    setIndex: 0,
                    target: .reps(scores.count),
                    achievedReps: scores.count,
                    achievedHoldSeconds: 0,
                    averageFormScore: qualitySummary.averageFormScore,
                    cueEvents: cueEvents,
                    qualitySummary: qualitySummary,
                    repQualityEvents: events
                )
            ],
            topCue: cueEvents.first,
            effortSummary: "No face-effort signal was captured for this session.",
            createdAt: endedAt
        )
    }

    func makeRepEvent(
        exerciseType: ExerciseType = .squat,
        setIndex: Int? = 0,
        repIndex: Int,
        score: Int,
        cue: String? = nil,
        severity: CoachCue.Severity? = nil,
        effort: Double? = nil
    ) -> RepQualityEvent {
        RepQualityEvent(
            exerciseType: exerciseType,
            setIndex: setIndex,
            repIndex: repIndex,
            timestamp: Date(timeIntervalSince1970: 1_776_300_000 + TimeInterval(repIndex)),
            secondsIntoSet: TimeInterval(repIndex * 5),
            formScore: score,
            formGrade: FormScore.Grade.from(score: score).rawValue,
            phase: RepPhase.up.rawValue,
            cueMessageNearRep: cue,
            cueSeverityNearRep: severity,
            effortAtRep: effort
        )
    }

    func formScore(_ score: Int) -> FormScore {
        FormScore(
            score: score,
            grade: .from(score: score),
            romPenalty: 0,
            tempoPenalty: 0,
            feedbackPenalty: 0
        )
    }

    func temporaryHistoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("WorkoutHistory.json")
    }
}
