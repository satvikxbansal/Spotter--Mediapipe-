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

    func makeSetSummary(planId: UUID) -> PlannedWorkoutSetSummary {
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
            completionSource: .targetMet
        )
    }

    func makeFreeAnalysisSummary() -> FreeAnalysisSummary {
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
            ]
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
