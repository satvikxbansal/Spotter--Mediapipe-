import XCTest
@testable import VirtualTrainer

final class WorkoutRecapBuilderTests: XCTestCase {
    private let builder = WorkoutRecapBuilder()

    func testCleanSessionBuildsStableEvidenceRecap() {
        let summary = makeSummary(
            exerciseType: .squat,
            scores: [90, 91, 92, 93],
            completionPercent: 1
        )

        let recap = builder.build(summary: summary)

        XCTAssertEqual(recap.headline, "\(ExerciseType.squat.displayName) held the line.")
        XCTAssertTrue(recap.bodyMessage.contains("\(ExerciseType.squat.displayName) led the session with 4 reps"))
        XCTAssertTrue(recap.bodyMessage.contains("form held from 91% to 93%"))
        XCTAssertTrue(recap.bodyMessage.contains("100% complete"))
        XCTAssertEqual(recap.highlightStat, "Best rep: set 1, rep 4 hit 93%")
        XCTAssertEqual(recap.nextStep, "earn a small rep bump")
    }

    func testFadedSetCallsOutBreakdownAndCueNudge() {
        let summary = makeSummary(
            exerciseType: .squat,
            scores: [94, 92, 78, 74],
            completionPercent: 1
        )

        let recap = builder.build(summary: summary)

        XCTAssertEqual(recap.headline, "\(ExerciseType.squat.displayName) needs an early cue.")
        XCTAssertTrue(recap.bodyMessage.contains("form faded from 93% to 76%"))
        XCTAssertTrue(recap.bodyMessage.contains("Breakdown showed at set 1, rep 3"))
        XCTAssertEqual(recap.nextStep, "lock the cue early next time")
    }

    func testPartialCompletionMentionsCompletionPercent() {
        let summary = makeSummary(
            exerciseType: .pushup,
            scores: [82, 83],
            completionPercent: 0.5
        )

        let recap = builder.build(summary: summary)

        XCTAssertTrue(recap.bodyMessage.contains("50% complete"))
        XCTAssertEqual(recap.nextStep, "keep the same target, deepen quality")
    }

    func testRestExtendedNudgeWhenQualityDoesNotDemandAnotherAction() {
        let summary = makeSummary(
            exerciseType: .pushup,
            scores: [82, 83],
            completionPercent: 1,
            restExtended: true
        )

        let recap = builder.build(summary: summary)

        XCTAssertEqual(recap.nextStep, "give yourself 15s more rest next set")
    }

    func testDominantExerciseAggregatesVolumeAcrossSets() {
        let now = Date(timeIntervalSince1970: 1_776_500_050)
        let pushupSetOne = makeSet(
            exerciseType: .pushup,
            setIndex: 0,
            scores: [84, 85, 86, 87],
            start: now
        )
        let pushupSetTwo = makeSet(
            exerciseType: .pushup,
            setIndex: 1,
            scores: [85, 86, 87, 88],
            start: now.addingTimeInterval(60)
        )
        let plankSet = makeSet(
            exerciseType: .plank,
            setIndex: 2,
            scores: [],
            reps: 0,
            holdSeconds: 6,
            start: now.addingTimeInterval(120)
        )
        let summary = WorkoutSessionSummary(
            mode: .plannedWorkout,
            planId: UUID(),
            title: "Mixed Session",
            goal: "Build clean strength.",
            coach: .good,
            startedAt: now.addingTimeInterval(-300),
            endedAt: now,
            durationSeconds: 300,
            totalReps: 8,
            totalHoldSeconds: 6,
            averageFormScore: nil,
            completionPercent: 1,
            exerciseSummaries: [plankSet, pushupSetOne, pushupSetTwo],
            topCue: nil,
            effortSummary: "No face-effort signal was captured for this session.",
            createdAt: now
        )

        let recap = builder.build(summary: summary)

        XCTAssertTrue(recap.bodyMessage.contains("\(ExerciseType.pushup.displayName) led the session with 8 reps"))
    }

    func testFreeAnalysisSaveBuildsRecapFromSavedHistorySummary() {
        let now = Date(timeIntervalSince1970: 1_776_500_000)
        let repEvents = makeRepEvents(
            exerciseType: .pushup,
            setIndex: nil,
            scores: [84, 86, 88, 90],
            start: now
        )
        let qualitySummary = SetQualitySummary.build(repQualityEvents: repEvents)
        let freeSummary = FreeAnalysisSummary(
            exerciseType: .pushup,
            coach: .good,
            startedAt: now.addingTimeInterval(-180),
            endedAt: now,
            duration: 180,
            reps: 4,
            holdDuration: 0,
            latestFormScore: formScore(90),
            peakEffort: 0.42,
            lastCue: nil,
            repQualityEvents: repEvents,
            qualitySummary: qualitySummary
        )
        let historySummary = WorkoutSessionSummary.freeAnalysis(from: freeSummary, createdAt: now)

        let recap = builder.build(summary: historySummary)

        XCTAssertEqual(historySummary.mode, .freeAnalysis)
        XCTAssertTrue(recap.bodyMessage.contains("\(ExerciseType.pushup.displayName) led the session with 4 reps"))
        XCTAssertFalse(recap.bodyMessage.contains("complete"))
        XCTAssertEqual(recap.highlightStat, "Best rep: rep 4 hit 90%")
    }

    func testZeroRepHoldOnlySetBuildsHonestHoldRecap() {
        let summary = makeSummary(
            exerciseType: .plank,
            scores: [],
            reps: 0,
            holdSeconds: 45,
            completionPercent: 1
        )

        let recap = builder.build(summary: summary)

        XCTAssertEqual(recap.headline, "Plank work is logged.")
        XCTAssertTrue(recap.bodyMessage.contains("45s hold"))
        XCTAssertEqual(recap.highlightStat, "Hold total: 45s")
        XCTAssertEqual(recap.nextStep, "keep the same target, deepen quality")
    }

    func testZeroEvidenceFallbackDoesNotEchoBlockedGoalText() {
        let now = Date(timeIntervalSince1970: 1_776_500_100)
        let summary = WorkoutSessionSummary(
            mode: .plannedWorkout,
            planId: UUID(),
            title: "Empty Session",
            goal: "Weight loss and calorie burn",
            coach: .good,
            startedAt: now.addingTimeInterval(-60),
            endedAt: now,
            durationSeconds: 60,
            totalReps: 0,
            totalHoldSeconds: 0,
            averageFormScore: nil,
            completionPercent: nil,
            exerciseSummaries: [],
            topCue: nil,
            effortSummary: "No face-effort signal was captured for this session.",
            createdAt: now
        )

        let recap = builder.build(summary: summary)

        XCTAssertEqual(recap.headline, "Session logged.")
        XCTAssertTrue(recap.bodyMessage.contains("Logged a session."))
        XCTAssertFalse(recap.bodyMessage.lowercased().contains("weight loss"))
        XCTAssertFalse(recap.bodyMessage.lowercased().contains("calorie"))
    }
}

private extension WorkoutRecapBuilderTests {
    func makeSummary(
        exerciseType: ExerciseType,
        scores: [Int],
        reps: Int? = nil,
        holdSeconds: Int = 0,
        completionPercent: Double? = 1,
        restExtended: Bool = false
    ) -> WorkoutSessionSummary {
        let now = Date(timeIntervalSince1970: 1_776_500_000)
        let set = makeSet(
            exerciseType: exerciseType,
            setIndex: 0,
            scores: scores,
            reps: reps,
            holdSeconds: holdSeconds,
            restExtended: restExtended,
            start: now
        )
        let totalReps = max(reps ?? scores.count, 0)

        return WorkoutSessionSummary(
            mode: .plannedWorkout,
            planId: UUID(),
            title: "\(exerciseType.displayName) Test",
            goal: "Build clean strength.",
            coach: .good,
            startedAt: now.addingTimeInterval(-300),
            endedAt: now,
            durationSeconds: 300,
            totalReps: totalReps,
            totalHoldSeconds: holdSeconds,
            averageFormScore: set.averageFormScore,
            completionPercent: completionPercent,
            exerciseSummaries: [set],
            topCue: nil,
            effortSummary: "No face-effort signal was captured for this session.",
            workoutOutcome: (completionPercent ?? 0) >= 1 ? .completed : .partial,
            createdAt: now
        )
    }

    func makeSet(
        exerciseType: ExerciseType,
        setIndex: Int?,
        scores: [Int],
        reps: Int? = nil,
        holdSeconds: Int = 0,
        restExtended: Bool = false,
        start: Date
    ) -> ExerciseSetSummary {
        let repEvents = makeRepEvents(
            exerciseType: exerciseType,
            setIndex: setIndex,
            scores: scores,
            start: start
        )
        let qualitySummary = scores.isEmpty
            ? nil
            : SetQualitySummary.build(repQualityEvents: repEvents)
        let achievedReps = max(reps ?? scores.count, 0)

        return ExerciseSetSummary(
            exerciseType: exerciseType,
            setIndex: setIndex,
            target: achievedReps > 0 ? .reps(achievedReps) : .hold(seconds: holdSeconds),
            achievedReps: achievedReps,
            achievedHoldSeconds: holdSeconds,
            averageFormScore: qualitySummary?.averageFormScore,
            restExtended: restExtended,
            qualitySummary: qualitySummary,
            repQualityEvents: repEvents
        )
    }

    func makeRepEvents(
        exerciseType: ExerciseType,
        setIndex: Int?,
        scores: [Int],
        start: Date
    ) -> [RepQualityEvent] {
        scores.enumerated().map { index, score in
            RepQualityEvent(
                exerciseType: exerciseType,
                setIndex: setIndex,
                repIndex: index + 1,
                timestamp: start.addingTimeInterval(TimeInterval(index)),
                secondsIntoSet: TimeInterval((index + 1) * 5),
                formScore: score,
                formGrade: FormScore.Grade.from(score: score).rawValue
            )
        }
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
}
