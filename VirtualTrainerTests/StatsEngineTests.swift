import XCTest
@testable import VirtualTrainer

@MainActor
final class StatsEngineTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    func testStatsEngineComputesXPDeterministically() async {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(
                idSuffix: "4001",
                mode: .plannedWorkout,
                endedAt: now,
                reps: 20,
                holdSeconds: 30,
                averageFormScore: 92,
                outcome: .completed,
                goodFormReps: 15,
                excellentFormReps: 5
            ),
            makeSummary(
                idSuffix: "4002",
                mode: .freeAnalysis,
                endedAt: date(year: 2026, month: 5, day: 5, hour: 12),
                reps: 10,
                holdSeconds: 20,
                averageFormScore: 85,
                outcome: .freeAnalysisSaved,
                goodFormReps: 6,
                excellentFormReps: 1
            ),
            makeSummary(
                idSuffix: "4003",
                mode: .plannedWorkout,
                endedAt: date(year: 2026, month: 5, day: 4, hour: 12),
                reps: 8,
                averageFormScore: nil,
                completionPercent: 0.5,
                outcome: .partial
            )
        ]
        let snapshot = trophySnapshot(
            earnedIDs: [
                TrophyDefinitionCatalog.ID.spark,
                TrophyDefinitionCatalog.ID.oneKClub
            ],
            now: now
        )

        let stats = StatsEngine(calendar: calendar).makeStats(
            history: history,
            trophySnapshot: snapshot,
            now: now
        )

        XCTAssertEqual(stats.totalWorkouts, 3)
        XCTAssertEqual(stats.totalPlannedWorkouts, 2)
        XCTAssertEqual(stats.totalFreeAnalysisSessions, 1)
        XCTAssertEqual(stats.totalReps, 38)
        XCTAssertEqual(stats.totalHoldSeconds, 50)
        XCTAssertEqual(stats.totalGoodFormReps, 21)
        XCTAssertEqual(stats.totalExcellentFormReps, 6)
        XCTAssertEqual(stats.currentStreak, 3)
        XCTAssertEqual(stats.longestStreak, 3)
        XCTAssertEqual(stats.workoutsThisWeek, 3)
        XCTAssertEqual(stats.averageFormScore, 88.5)
        XCTAssertEqual(stats.trophiesEarned, 2)
        XCTAssertEqual(stats.xp, 496)
        XCTAssertEqual(stats.level, 1)
    }

    func testLevelFormulaIsStable() async {
        XCTAssertEqual(StatsEngine.level(forXP: -10), 1)
        XCTAssertEqual(StatsEngine.level(forXP: 0), 1)
        XCTAssertEqual(StatsEngine.level(forXP: 499), 1)
        XCTAssertEqual(StatsEngine.level(forXP: 500), 2)
        XCTAssertEqual(StatsEngine.level(forXP: 1_000), 3)
        XCTAssertEqual(StatsEngine.xpRequired(forLevel: 1), 0)
        XCTAssertEqual(StatsEngine.xpRequired(forLevel: 3), 1_000)
    }

    func testEmptyHistoryStatsDoNotCrash() async {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let stats = StatsEngine(calendar: calendar).makeStats(
            history: [],
            trophySnapshot: trophySnapshot(earnedIDs: [], now: now),
            now: now
        )

        XCTAssertEqual(stats.totalWorkouts, 0)
        XCTAssertEqual(stats.xp, 0)
        XCTAssertEqual(stats.level, 1)
        XCTAssertNil(stats.averageFormScore)
        XCTAssertNil(stats.lastWorkoutAt)
    }

    func testStatsEnginePrefersServerEndedAtForStreaksAndLastWorkoutDate() async {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let serverTimedSummary = makeSummary(
            idSuffix: "4051",
            mode: .plannedWorkout,
            endedAt: date(year: 2026, month: 5, day: 1, hour: 23),
            serverEndedAt: now
        )
        let yesterdaySummary = makeSummary(
            idSuffix: "4052",
            mode: .freeAnalysis,
            endedAt: date(year: 2026, month: 5, day: 5, hour: 10)
        )

        let stats = StatsEngine(calendar: calendar).makeStats(
            history: [serverTimedSummary, yesterdaySummary],
            trophySnapshot: trophySnapshot(earnedIDs: [], now: now),
            now: now
        )

        XCTAssertEqual(stats.currentStreak, 2)
        XCTAssertEqual(stats.longestStreak, 2)
        XCTAssertEqual(stats.lastWorkoutAt, now)
    }

    func testHistorySelectionReturnsDetailSummary() async {
        let first = makeSummary(
            idSuffix: "4101",
            mode: .plannedWorkout,
            endedAt: date(year: 2026, month: 5, day: 1, hour: 10)
        )
        let second = makeSummary(
            idSuffix: "4102",
            mode: .freeAnalysis,
            endedAt: date(year: 2026, month: 5, day: 2, hour: 10)
        )

        let selected = ProfileHistorySelection.detailSummary(
            for: second.id,
            in: [first, second]
        )

        XCTAssertEqual(selected, second)
    }

    func testTrophyCountComesFromTrophyStoreSnapshot() async {
        let now = date(year: 2026, month: 5, day: 1, hour: 12)
        let store = TrophyStore(fileURL: temporaryTrophyURL(), calendar: calendar)
        let summary = makeSummary(
            idSuffix: "4201",
            mode: .plannedWorkout,
            endedAt: now,
            reps: 10
        )

        await store.updateAll(
            history: [summary],
            calibrationStatus: .notStarted,
            now: now
        )
        let stats = StatsEngine(calendar: calendar).makeStats(
            history: [summary],
            trophySnapshot: store.snapshot,
            now: now
        )

        XCTAssertEqual(stats.trophiesEarned, store.snapshot.availableProgress.filter(\.earned).count)
        XCTAssertEqual(stats.trophiesEarned, 1)
    }
}

private extension StatsEngineTests {
    func makeSummary(
        idSuffix: String,
        mode: WorkoutSessionSummaryMode,
        endedAt: Date,
        reps: Int = 12,
        holdSeconds: Int = 0,
        averageFormScore: Double? = 88,
        completionPercent: Double? = 1,
        outcome: WorkoutOutcome? = nil,
        goodFormReps: Int = 0,
        excellentFormReps: Int = 0,
        serverEndedAt: Date? = nil
    ) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000\(idSuffix)") ?? UUID(),
            mode: mode,
            planId: mode == .plannedWorkout ? UUID(uuidString: "00000000-0000-0000-0000-000000004999") : nil,
            title: mode == .plannedWorkout ? "Stats Plan" : "Stats Form Check",
            goal: mode == .plannedWorkout ? "Build clean strength." : nil,
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            serverEndedAt: serverEndedAt,
            durationSeconds: 600,
            totalReps: reps,
            totalHoldSeconds: holdSeconds,
            averageFormScore: averageFormScore,
            completionPercent: mode == .plannedWorkout ? completionPercent : nil,
            exerciseSummaries: [
                ExerciseSetSummary(
                    exerciseType: .squat,
                    setIndex: mode == .plannedWorkout ? 0 : nil,
                    target: reps > 0 ? .reps(reps) : .hold(seconds: holdSeconds),
                    achievedReps: reps,
                    achievedHoldSeconds: holdSeconds,
                    averageFormScore: averageFormScore
                )
            ],
            topCue: nil,
            effortSummary: "No face-effort signal was captured for this session.",
            workoutOutcome: outcome,
            totalGoodFormReps: goodFormReps,
            totalExcellentFormReps: excellentFormReps,
            createdAt: endedAt
        )
    }

    func trophySnapshot(
        earnedIDs: Set<String>,
        now: Date
    ) -> TrophyProgressSnapshot {
        TrophyProgressSnapshot(
            catalogVersion: TrophyDefinitionCatalog.version,
            generatedAt: now,
            progress: TrophyDefinitionCatalog.all.map { definition in
                let earned = earnedIDs.contains(definition.id)
                return TrophyProgress(
                    trophyId: definition.id,
                    currentValue: earned ? definition.targetValue : 0,
                    targetValue: definition.targetValue,
                    earned: earned,
                    earnedAt: earned ? now : nil,
                    lastUpdatedAt: now,
                    confidence: definition.isComingSoon ? .unavailable : .exact,
                    progressLabel: earned ? "Earned" : "0/\(Int(definition.targetValue)) \(definition.unit)"
                )
            },
            newlyEarnedEvents: []
        )
    }

    func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        ) ?? Date(timeIntervalSince1970: 0)
    }

    func temporaryTrophyURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("TrophyProgress.json")
    }
}
