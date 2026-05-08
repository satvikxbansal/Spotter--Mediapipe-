import XCTest
@testable import VirtualTrainer

@MainActor
final class TrophyEngineTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private lazy var engine = TrophyEngine(calendar: calendar)

    func testFirstSavedWorkoutUnlocksTheSpark() throws {
        let summary = makeSummary(idSuffix: "2001", endedAt: date(year: 2026, month: 5, day: 1, hour: 10))

        let result = engine.update(
            after: summary,
            history: [summary],
            calibrationStatus: .notStarted,
            now: date(year: 2026, month: 5, day: 1, hour: 11)
        )

        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.spark, in: result).earned)
        XCTAssertTrue(result.newlyEarnedEvents.contains { $0.trophyId == TrophyDefinitionCatalog.ID.spark })
    }

    func testCompletedCalibrationUnlocksCalibrated() {
        let result = engine.updateAll(
            history: [],
            calibrationStatus: .completed,
            now: date(year: 2026, month: 5, day: 1, hour: 10)
        )

        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.calibrated, in: result).earned)
    }

    func testSevenUniqueWorkoutDaysUnlocksSevenDayInferno() {
        let history = (0..<7).map { offset in
            makeSummary(
                idSuffix: "21\(offset)",
                endedAt: date(year: 2026, month: 5, day: 1 + offset, hour: 10)
            )
        }

        let result = engine.updateAll(history: history, calibrationStatus: .notStarted)

        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.sevenDayInferno, in: result).earned)
    }

    func testWeekendWorkoutsProgressWeekendFlex() {
        let saturday = makeSummary(
            idSuffix: "2201",
            endedAt: date(year: 2026, month: 5, day: 2, hour: 10)
        )
        let sunday = makeSummary(
            idSuffix: "2202",
            endedAt: date(year: 2026, month: 5, day: 3, hour: 10)
        )

        let partial = engine.updateAll(history: [saturday], calibrationStatus: .notStarted)
        let complete = engine.updateAll(history: [saturday, sunday], calibrationStatus: .notStarted)

        XCTAssertEqual(progress(TrophyDefinitionCatalog.ID.weekendFlex, in: partial).currentValue, 1)
        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.weekendFlex, in: complete).earned)
    }

    func testMorningAndNightTrophiesRespectLocalCalendar() {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        let localEngine = TrophyEngine(calendar: localCalendar)
        let morningHistory = (0..<5).map { offset in
            makeSummary(
                idSuffix: "23\(offset)",
                startedAt: localDate(year: 2026, month: 5, day: 1 + offset, hour: 6, minute: 30, calendar: localCalendar),
                endedAt: localDate(year: 2026, month: 5, day: 1 + offset, hour: 6, minute: 45, calendar: localCalendar)
            )
        }
        let night = makeSummary(
            idSuffix: "2399",
            startedAt: localDate(year: 2026, month: 5, day: 6, hour: 22, minute: 5, calendar: localCalendar),
            endedAt: localDate(year: 2026, month: 5, day: 6, hour: 22, minute: 25, calendar: localCalendar)
        )

        let result = localEngine.updateAll(
            history: morningHistory + [night],
            calibrationStatus: .notStarted
        )

        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.morningGlory, in: result).earned)
        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.nightOwl, in: result).earned)
    }

    func testOneThousandTotalRepsUnlocksOneKClub() {
        let history = (0..<10).map { offset in
            makeSummary(
                idSuffix: "24\(offset)",
                endedAt: date(year: 2026, month: 5, day: 1 + offset, hour: 10),
                reps: 100
            )
        }

        let result = engine.updateAll(history: history, calibrationStatus: .notStarted)

        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.oneKClub, in: result).earned)
    }

    func testOneHundredSquatsInOneSessionUnlocksSquatKing() {
        let summary = makeSummary(
            idSuffix: "2501",
            exerciseType: .squat,
            endedAt: date(year: 2026, month: 5, day: 1, hour: 10),
            reps: 100
        )

        let result = engine.updateAll(history: [summary], calibrationStatus: .notStarted)

        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.squatKing, in: result).earned)
    }

    func testFormArchitectUsesExactRepQualityEvents() {
        let events = (1...500).map { index in
            makeRepEvent(repIndex: index, score: 95)
        }
        let summary = makeSummary(
            idSuffix: "2601",
            exerciseType: .squat,
            endedAt: date(year: 2026, month: 5, day: 1, hour: 10),
            reps: 500,
            averageFormScore: 96,
            repQualityEvents: events
        )

        let result = engine.updateAll(history: [summary], calibrationStatus: .notStarted)
        let formArchitect = progress(TrophyDefinitionCatalog.ID.formArchitect, in: result)

        XCTAssertTrue(formArchitect.earned)
        XCTAssertEqual(formArchitect.currentValue, 500)
        XCTAssertEqual(formArchitect.confidence, .exact)
    }

    func testEliteFormRequiresZeroOrLowCueSets() {
        let nineCleanSets = (0..<9).map { index in
            makeSetSummary(
                exerciseType: .squat,
                setIndex: index,
                reps: 10,
                averageFormScore: 92
            )
        }
        let warnedSet = makeSetSummary(
            exerciseType: .squat,
            setIndex: 9,
            reps: 10,
            averageFormScore: 95,
            cueEvents: [
                CueEvent(
                    timestamp: date(year: 2026, month: 5, day: 1, hour: 10),
                    exerciseType: .squat,
                    cueMessage: "Brace",
                    severity: .warning
                )
            ]
        )
        let cleanSet = makeSetSummary(
            exerciseType: .squat,
            setIndex: 9,
            reps: 10,
            averageFormScore: 95
        )

        let partial = engine.updateAll(
            history: [
                makeSummary(
                    idSuffix: "2701",
                    endedAt: date(year: 2026, month: 5, day: 1, hour: 10),
                    exerciseSummaries: nineCleanSets + [warnedSet]
                )
            ],
            calibrationStatus: .notStarted
        )
        let complete = engine.updateAll(
            history: [
                makeSummary(
                    idSuffix: "2702",
                    endedAt: date(year: 2026, month: 5, day: 2, hour: 10),
                    exerciseSummaries: nineCleanSets + [cleanSet]
                )
            ],
            calibrationStatus: .notStarted
        )

        XCTAssertFalse(progress(TrophyDefinitionCatalog.ID.eliteForm, in: partial).earned)
        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.eliteForm, in: complete).earned)
    }

    func testZenMasterProgressesOnlyForLongevityOrMobilitySessions() {
        let mobility = (0..<9).map { offset in
            makeSummary(
                idSuffix: "28\(offset)",
                exerciseType: .downwardDog,
                title: "Mobility Flow",
                goal: "Mobility and longevity",
                endedAt: date(year: 2026, month: 5, day: 1 + offset, hour: 10),
                reps: 0,
                holdSeconds: 60
            )
        }
        let strength = makeSummary(
            idSuffix: "2898",
            exerciseType: .squat,
            title: "Strength",
            goal: "Build strength",
            endedAt: date(year: 2026, month: 5, day: 10, hour: 10),
            reps: 20
        )
        let tenthMobility = makeSummary(
            idSuffix: "2899",
            exerciseType: .cobraPose,
            title: "Longevity Flow",
            goal: "Longevity",
            endedAt: date(year: 2026, month: 5, day: 11, hour: 10),
            reps: 0,
            holdSeconds: 60
        )

        let partial = engine.updateAll(history: mobility + [strength], calibrationStatus: .notStarted)
        let complete = engine.updateAll(history: mobility + [strength, tenthMobility], calibrationStatus: .notStarted)

        XCTAssertEqual(progress(TrophyDefinitionCatalog.ID.zenMaster, in: partial).currentValue, 9)
        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.zenMaster, in: complete).earned)
    }

    func testNeonPulseIsComingSoonWhenHeartRateIsUnavailable() {
        let result = engine.updateAll(history: [], calibrationStatus: .notStarted)
        let neonPulse = progress(TrophyDefinitionCatalog.ID.neonPulse, in: result)

        XCTAssertFalse(neonPulse.earned)
        XCTAssertEqual(neonPulse.confidence, .unavailable)
        XCTAssertTrue(TrophyDefinitionCatalog.definition(for: TrophyDefinitionCatalog.ID.neonPulse)?.isComingSoon ?? false)
    }

    func testHeavyMetalIsComingSoonWhenLoadTrackingIsUnavailable() {
        let result = engine.updateAll(history: [], calibrationStatus: .notStarted)
        let heavyMetal = progress(TrophyDefinitionCatalog.ID.heavyMetal, in: result)

        XCTAssertFalse(heavyMetal.earned)
        XCTAssertEqual(heavyMetal.confidence, .unavailable)
        XCTAssertEqual(TrophyDefinitionCatalog.definition(for: TrophyDefinitionCatalog.ID.heavyMetal)?.dataRequirement, .externalLoad)
    }

    func testBurpeeBeastIsComingSoonWhenBurpeeIsUnsupported() {
        let result = engine.updateAll(history: [], calibrationStatus: .notStarted)
        let burpeeBeast = progress(TrophyDefinitionCatalog.ID.burpeeBeast, in: result)

        XCTAssertFalse(burpeeBeast.earned)
        XCTAssertEqual(burpeeBeast.confidence, .unavailable)
        XCTAssertEqual(TrophyDefinitionCatalog.definition(for: TrophyDefinitionCatalog.ID.burpeeBeast)?.dataRequirement, .unsupportedExercise)
    }

    func testApexAndAlphaExcludeComingSoonTrophiesFromEligibility() {
        let now = date(year: 2026, month: 5, day: 1, hour: 10)
        let regularIds = Set(TrophyDefinitionCatalog.regularEligibleDefinitions.map(\.id))
        let previousProgress = TrophyDefinitionCatalog.all.map { definition in
            TrophyProgress(
                trophyId: definition.id,
                currentValue: regularIds.contains(definition.id) ? definition.targetValue : 0,
                targetValue: definition.targetValue,
                earned: regularIds.contains(definition.id),
                earnedAt: regularIds.contains(definition.id) ? now : nil,
                lastUpdatedAt: now,
                confidence: definition.isComingSoon ? .unavailable : .exact,
                progressLabel: regularIds.contains(definition.id) ? "Earned" : "0/\(Int(definition.targetValue)) \(definition.unit)"
            )
        }
        let previousSnapshot = TrophyProgressSnapshot(
            catalogVersion: TrophyDefinitionCatalog.version,
            generatedAt: now,
            progress: previousProgress,
            newlyEarnedEvents: []
        )

        let result = engine.updateAll(
            history: [],
            calibrationStatus: .notStarted,
            previousSnapshot: previousSnapshot,
            now: now
        )

        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.apexSpotter, in: result).earned)
        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.alphaSpotter, in: result).earned)
        XCTAssertEqual(
            progress(TrophyDefinitionCatalog.ID.apexSpotter, in: result).targetValue,
            Double(TrophyDefinitionCatalog.regularEligibleDefinitions.count)
        )
    }

    func testNewlyEarnedTrophyEventsAreEmittedOnce() {
        let store = TrophyStore(fileURL: temporaryTrophyURL(), calendar: calendar)
        let summary = makeSummary(idSuffix: "3001", endedAt: date(year: 2026, month: 5, day: 1, hour: 10))

        let firstEvents = store.update(
            after: summary,
            history: [summary],
            calibrationStatus: .notStarted,
            now: date(year: 2026, month: 5, day: 1, hour: 11)
        )
        let secondEvents = store.updateAll(
            history: [summary],
            calibrationStatus: .notStarted,
            now: date(year: 2026, month: 5, day: 1, hour: 12)
        )

        XCTAssertTrue(firstEvents.contains { $0.trophyId == TrophyDefinitionCatalog.ID.spark })
        XCTAssertFalse(secondEvents.contains { $0.trophyId == TrophyDefinitionCatalog.ID.spark })
    }

    func testDeletedWorkoutRecomputeDoesNotRetractAlreadyEarnedTrophyState() {
        let summary = makeSummary(idSuffix: "3051", endedAt: date(year: 2026, month: 5, day: 1, hour: 10))
        let earned = engine.updateAll(
            history: [summary],
            calibrationStatus: .notStarted,
            now: date(year: 2026, month: 5, day: 1, hour: 11)
        )

        let afterDelete = engine.updateAll(
            history: [],
            calibrationStatus: .notStarted,
            previousSnapshot: earned.snapshot,
            now: date(year: 2026, month: 5, day: 1, hour: 12)
        )

        XCTAssertTrue(progress(TrophyDefinitionCatalog.ID.spark, in: afterDelete).earned)
        XCTAssertTrue(afterDelete.newlyEarnedEvents.isEmpty)
    }

    func testDebugRecalculationCanRetractSampleOnlyTrophies() {
        let store = TrophyStore(fileURL: temporaryTrophyURL(), calendar: calendar)
        let calibratedAt = date(year: 2026, month: 5, day: 1, hour: 9)
        let sampleWorkoutAt = date(year: 2026, month: 5, day: 1, hour: 10)
        let clearedAt = date(year: 2026, month: 5, day: 1, hour: 11)
        let sampleSummary = makeSummary(idSuffix: "3061", endedAt: sampleWorkoutAt)

        store.updateAll(
            history: [],
            calibrationStatus: .completed,
            now: calibratedAt
        )
        let calibratedEarnedAt = store.snapshot.progress(for: TrophyDefinitionCatalog.ID.calibrated)?.earnedAt
        store.updateAll(
            history: [sampleSummary],
            calibrationStatus: .completed,
            now: sampleWorkoutAt
        )

        XCTAssertTrue(store.snapshot.progress(for: TrophyDefinitionCatalog.ID.spark)?.earned ?? false)

        XCTAssertTrue(
            store.recalculateForDebug(
                history: [],
                calibrationStatus: .completed,
                now: clearedAt
            )
        )

        XCTAssertFalse(store.snapshot.progress(for: TrophyDefinitionCatalog.ID.spark)?.earned ?? true)
        XCTAssertTrue(store.snapshot.progress(for: TrophyDefinitionCatalog.ID.calibrated)?.earned ?? false)
        XCTAssertEqual(
            store.snapshot.progress(for: TrophyDefinitionCatalog.ID.calibrated)?.earnedAt,
            calibratedEarnedAt
        )
    }

    func testTrophyProgressPersistsAfterReload() {
        let url = temporaryTrophyURL()
        let summary = makeSummary(idSuffix: "3101", endedAt: date(year: 2026, month: 5, day: 1, hour: 10))
        let store = TrophyStore(fileURL: url, calendar: calendar)

        store.update(
            after: summary,
            history: [summary],
            calibrationStatus: .notStarted,
            now: date(year: 2026, month: 5, day: 1, hour: 11)
        )
        let reloaded = TrophyStore(fileURL: url, calendar: calendar)

        XCTAssertTrue(reloaded.snapshot.progress(for: TrophyDefinitionCatalog.ID.spark)?.earned ?? false)
        XCTAssertTrue(reloaded.snapshot.newlyEarnedEvents.isEmpty)
    }

    func testFailedTrophyUpdateDoesNotExposeUnsavedProgressOrEvents() throws {
        let summary = makeSummary(idSuffix: "3151", endedAt: date(year: 2026, month: 5, day: 1, hour: 10))
        let store = TrophyStore(fileURL: try unwritableTrophyURL(), calendar: calendar)

        let events = store.update(
            after: summary,
            history: [summary],
            calibrationStatus: .notStarted,
            now: date(year: 2026, month: 5, day: 1, hour: 11)
        )

        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(store.snapshot.progress(for: TrophyDefinitionCatalog.ID.spark)?.earned ?? true)
        XCTAssertTrue(store.snapshot.newlyEarnedEvents.isEmpty)
        XCTAssertNotNil(store.persistenceError)
    }

    func testDuplicatePersistedProgressDoesNotCrashLookup() {
        let id = TrophyDefinitionCatalog.ID.spark
        let older = makeProgress(
            trophyId: id,
            currentValue: 0,
            targetValue: 1,
            earned: false,
            earnedAt: nil,
            lastUpdatedAt: date(year: 2026, month: 5, day: 1, hour: 10),
            progressLabel: "0/1 workout"
        )
        let newer = makeProgress(
            trophyId: id,
            currentValue: 0.5,
            targetValue: 1,
            earned: false,
            earnedAt: nil,
            lastUpdatedAt: date(year: 2026, month: 5, day: 1, hour: 11),
            progressLabel: "0.5/1 workout"
        )
        let snapshot = makeSnapshot(progress: [older, newer])

        XCTAssertEqual(snapshot.progressByTrophyId[id]?.currentValue, 0.5)
    }

    func testDuplicatePersistedProgressPreservesEarnedTrophy() {
        let id = TrophyDefinitionCatalog.ID.spark
        let earnedAt = date(year: 2026, month: 5, day: 1, hour: 10)
        let earned = makeProgress(
            trophyId: id,
            currentValue: 1,
            targetValue: 1,
            earned: true,
            earnedAt: earnedAt,
            lastUpdatedAt: date(year: 2026, month: 5, day: 1, hour: 10),
            progressLabel: "Earned"
        )
        let staleUnearned = makeProgress(
            trophyId: id,
            currentValue: 0,
            targetValue: 1,
            earned: false,
            earnedAt: nil,
            lastUpdatedAt: date(year: 2026, month: 5, day: 1, hour: 12),
            progressLabel: "0/1 workout"
        )
        let snapshot = makeSnapshot(progress: [staleUnearned, earned])

        XCTAssertTrue(snapshot.progressByTrophyId[id]?.earned ?? false)
        XCTAssertEqual(snapshot.progressByTrophyId[id]?.earnedAt, earnedAt)
    }

    func testTrophyDefinitionsHaveUniqueIds() {
        let ids = TrophyDefinitionCatalog.all.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEmptyHistoryUnlocksNothingExceptStaticComingSoonStates() {
        let result = engine.updateAll(history: [], calibrationStatus: .notStarted)

        XCTAssertFalse(result.snapshot.progress.contains(where: \.earned))
        XCTAssertFalse(result.snapshot.comingSoonProgress.isEmpty)
        XCTAssertTrue(result.snapshot.comingSoonProgress.allSatisfy { $0.confidence == .unavailable })
    }
}

private extension TrophyEngineTests {
    func progress(_ trophyId: String, in result: TrophyEngineResult) -> TrophyProgress {
        guard let progress = result.snapshot.progress(for: trophyId) else {
            XCTFail("Missing trophy progress for \(trophyId)")
            return TrophyProgress(
                trophyId: trophyId,
                currentValue: 0,
                targetValue: 1,
                earned: false,
                earnedAt: nil,
                lastUpdatedAt: Date(timeIntervalSince1970: 0),
                confidence: .unavailable,
                progressLabel: "Missing"
            )
        }
        return progress
    }

    func makeSummary(
        idSuffix: String,
        exerciseType: ExerciseType = .squat,
        title: String? = nil,
        goal: String? = nil,
        startedAt: Date? = nil,
        endedAt: Date,
        reps: Int = 10,
        holdSeconds: Int = 0,
        averageFormScore: Double? = 90,
        repQualityEvents: [RepQualityEvent] = [],
        cueEvents: [CueEvent] = [],
        exerciseSummaries: [ExerciseSetSummary]? = nil
    ) -> WorkoutSessionSummary {
        let startedAt = startedAt ?? endedAt.addingTimeInterval(-600)
        let summaries = exerciseSummaries ?? [
            makeSetSummary(
                exerciseType: exerciseType,
                setIndex: 0,
                reps: reps,
                holdSeconds: holdSeconds,
                averageFormScore: averageFormScore,
                repQualityEvents: repQualityEvents,
                cueEvents: cueEvents
            )
        ]

        return WorkoutSessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000\(idSuffix)") ?? UUID(),
            mode: .plannedWorkout,
            planId: UUID(uuidString: "00000000-0000-0000-0000-000000009999"),
            title: title ?? exerciseType.displayName,
            goal: goal,
            coach: .good,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: max(Int(endedAt.timeIntervalSince(startedAt)), 0),
            totalReps: summaries.reduce(0) { $0 + $1.achievedReps },
            totalHoldSeconds: summaries.reduce(0) { $0 + $1.achievedHoldSeconds },
            averageFormScore: averageFormScore,
            completionPercent: 1,
            exerciseSummaries: summaries,
            topCue: cueEvents.first,
            effortSummary: "No face-effort signal was captured for this session.",
            createdAt: endedAt
        )
    }

    func makeSetSummary(
        exerciseType: ExerciseType,
        setIndex: Int,
        reps: Int,
        holdSeconds: Int = 0,
        averageFormScore: Double?,
        repQualityEvents: [RepQualityEvent] = [],
        cueEvents: [CueEvent] = []
    ) -> ExerciseSetSummary {
        let qualitySummary = (repQualityEvents.isEmpty && cueEvents.isEmpty)
            ? nil
            : SetQualitySummary.build(
                repQualityEvents: repQualityEvents,
                cueEvents: cueEvents
            )
        return ExerciseSetSummary(
            exerciseType: exerciseType,
            setIndex: setIndex,
            target: reps > 0 ? .reps(reps) : .hold(seconds: holdSeconds),
            achievedReps: reps,
            achievedHoldSeconds: holdSeconds,
            averageFormScore: qualitySummary?.averageFormScore ?? averageFormScore,
            cueEvents: cueEvents,
            qualitySummary: qualitySummary,
            repQualityEvents: repQualityEvents,
            completedAt: date(year: 2026, month: 5, day: 1, hour: 10),
            durationSeconds: max(holdSeconds, reps * 3)
        )
    }

    func makeRepEvent(
        exerciseType: ExerciseType = .squat,
        repIndex: Int,
        score: Int,
        cue: String? = nil,
        severity: CoachCue.Severity? = nil
    ) -> RepQualityEvent {
        RepQualityEvent(
            exerciseType: exerciseType,
            setIndex: 0,
            repIndex: repIndex,
            timestamp: date(year: 2026, month: 5, day: 1, hour: 10).addingTimeInterval(TimeInterval(repIndex)),
            secondsIntoSet: TimeInterval(repIndex * 3),
            formScore: score,
            formGrade: nil,
            phase: nil,
            cueMessageNearRep: cue,
            cueSeverityNearRep: severity
        )
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

    func localDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
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

    func makeProgress(
        trophyId: String,
        currentValue: Double,
        targetValue: Double,
        earned: Bool,
        earnedAt: Date?,
        lastUpdatedAt: Date,
        progressLabel: String
    ) -> TrophyProgress {
        TrophyProgress(
            trophyId: trophyId,
            currentValue: currentValue,
            targetValue: targetValue,
            earned: earned,
            earnedAt: earnedAt,
            lastUpdatedAt: lastUpdatedAt,
            confidence: .exact,
            progressLabel: progressLabel
        )
    }

    func makeSnapshot(progress: [TrophyProgress]) -> TrophyProgressSnapshot {
        TrophyProgressSnapshot(
            catalogVersion: TrophyDefinitionCatalog.version,
            generatedAt: date(year: 2026, month: 5, day: 1, hour: 12),
            progress: progress,
            newlyEarnedEvents: []
        )
    }

    func temporaryTrophyURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("TrophyProgress.json")
    }

    func unwritableTrophyURL() throws -> URL {
        let blockedParentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrophyEngineTests-blocked-\(UUID().uuidString)")
        try Data().write(to: blockedParentURL)
        return blockedParentURL.appendingPathComponent("TrophyProgress.json")
    }
}
