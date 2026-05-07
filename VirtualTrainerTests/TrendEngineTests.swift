import XCTest
@testable import VirtualTrainer

final class TrendEngineTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    func testCurrentStreakCalculation() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "7001", endedAt: now),
            makeSummary(idSuffix: "7002", endedAt: date(year: 2026, month: 5, day: 5, hour: 12)),
            makeSummary(idSuffix: "7003", endedAt: date(year: 2026, month: 5, day: 4, hour: 12))
        ]

        let streak = TrendEngine(calendar: calendar).currentStreak(
            history: history,
            profile: makeProfile(),
            now: now
        )

        XCTAssertEqual(streak, 3)
    }

    func testLongestStreakCalculation() {
        let history = [
            makeSummary(idSuffix: "7011", endedAt: date(year: 2026, month: 5, day: 1, hour: 12)),
            makeSummary(idSuffix: "7012", endedAt: date(year: 2026, month: 5, day: 2, hour: 12)),
            makeSummary(idSuffix: "7013", endedAt: date(year: 2026, month: 5, day: 4, hour: 12)),
            makeSummary(idSuffix: "7014", endedAt: date(year: 2026, month: 5, day: 5, hour: 12)),
            makeSummary(idSuffix: "7015", endedAt: date(year: 2026, month: 5, day: 6, hour: 12)),
            makeSummary(idSuffix: "7016", endedAt: date(year: 2026, month: 5, day: 6, hour: 16))
        ]

        let streak = TrendEngine(calendar: calendar).longestStreak(
            history: history,
            profile: makeProfile()
        )

        XCTAssertEqual(streak, 3)
    }

    func testMultipleWorkoutsSameDayCountOnceForStreak() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "7021", endedAt: now),
            makeSummary(idSuffix: "7022", endedAt: date(year: 2026, month: 5, day: 6, hour: 18)),
            makeSummary(idSuffix: "7023", endedAt: date(year: 2026, month: 5, day: 5, hour: 12)),
            makeSummary(idSuffix: "7024", endedAt: date(year: 2026, month: 5, day: 3, hour: 12))
        ]

        let streak = TrendEngine(calendar: calendar).currentStreak(
            history: history,
            profile: makeProfile(),
            now: now
        )

        XCTAssertEqual(streak, 2)
    }

    func testSevenWorkoutAverageFormCalculation() throws {
        let now = date(year: 2026, month: 5, day: 8, hour: 12)
        let scores = [60, 70, 72, 74, 76, 78, 80, 82]
        let history = scores.enumerated().map { index, score in
            makeSummary(
                idSuffix: "703\(index)",
                endedAt: date(year: 2026, month: 5, day: index + 1, hour: 12),
                averageFormScore: Double(score)
            )
        }

        let average = try XCTUnwrap(
            TrendEngine(calendar: calendar).averageForm(
                history: history,
                window: .sevenWorkout,
                profile: makeProfile(),
                now: now
            )
        )

        XCTAssertEqual(average, 76, accuracy: 0.0001)
    }

    func testStrongestExerciseDetection() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "7041", endedAt: now, exerciseType: .squat, averageFormScore: 94),
            makeSummary(idSuffix: "7042", endedAt: date(year: 2026, month: 5, day: 5, hour: 12), exerciseType: .squat, averageFormScore: 90),
            makeSummary(idSuffix: "7043", endedAt: date(year: 2026, month: 5, day: 4, hour: 12), exerciseType: .pushup, averageFormScore: 78)
        ]

        let snapshot = TrendEngine(calendar: calendar).buildSnapshot(
            history: history,
            profile: makeProfile(),
            trophies: emptyTrophySnapshot(now: now),
            now: now
        )

        XCTAssertEqual(snapshot.strongestExercise, .squat)
    }

    func testImprovingExerciseDetection() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "7051", endedAt: date(year: 2026, month: 5, day: 1, hour: 12), exerciseType: .pushup, averageFormScore: 68),
            makeSummary(idSuffix: "7052", endedAt: date(year: 2026, month: 5, day: 2, hour: 12), exerciseType: .pushup, averageFormScore: 72),
            makeSummary(idSuffix: "7053", endedAt: date(year: 2026, month: 5, day: 5, hour: 12), exerciseType: .pushup, averageFormScore: 86),
            makeSummary(idSuffix: "7054", endedAt: now, exerciseType: .pushup, averageFormScore: 92),
            makeSummary(idSuffix: "7055", endedAt: now, exerciseType: .squat, averageFormScore: 82)
        ]

        let snapshot = TrendEngine(calendar: calendar).buildSnapshot(
            history: history,
            profile: makeProfile(),
            trophies: emptyTrophySnapshot(now: now),
            now: now
        )

        XCTAssertEqual(snapshot.improvingExercise, .pushup)
    }

    func testStrugglingExerciseDetectionFromRepeatedCuesAndFormDrop() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(
                idSuffix: "7061",
                endedAt: now,
                exerciseType: .lunge,
                scores: [88, 82, 70, 66],
                cueMessages: ["Keep your front knee steady", "Keep your front knee steady"]
            ),
            makeSummary(
                idSuffix: "7062",
                endedAt: date(year: 2026, month: 5, day: 5, hour: 12),
                exerciseType: .lunge,
                scores: [84, 80, 72, 68],
                cueMessages: ["Keep your front knee steady"]
            ),
            makeSummary(idSuffix: "7063", endedAt: now, exerciseType: .squat, averageFormScore: 88)
        ]

        let snapshot = TrendEngine(calendar: calendar).buildSnapshot(
            history: history,
            profile: makeProfile(),
            trophies: emptyTrophySnapshot(now: now),
            now: now
        )

        XCTAssertEqual(snapshot.strugglingExercise, .lunge)
        XCTAssertEqual(snapshot.mostRepeatedCue, "Keep your front knee steady")
    }

    func testRepeatedCueNormalizesCaseWhitespacePunctuationAndLeadingCueWords() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let profile = makeProfile()
        let engine = TrendEngine(calendar: calendar)
        let trophies = emptyTrophySnapshot(now: now)
        let history = [
            makeSummary(
                idSuffix: "7064",
                endedAt: now,
                exerciseType: .lunge,
                scores: [88, 76],
                cueMessages: ["Keep your front knee steady"]
            ),
            makeSummary(
                idSuffix: "7065",
                endedAt: date(year: 2026, month: 5, day: 5, hour: 12),
                exerciseType: .lunge,
                scores: [84, 72],
                cueMessages: ["  keep   your front knee steady!  "]
            )
        ]

        let snapshot = engine.buildSnapshot(
            history: history,
            profile: profile,
            trophies: trophies,
            now: now
        )
        let signals = SignalExtractor(trendEngine: engine).extractSignals(
            snapshot: snapshot,
            history: history,
            profile: profile,
            trophies: trophies
        )
        let repeatedCue = try XCTUnwrap(signals.first { $0.type == .repeatedCue })

        XCTAssertEqual(snapshot.mostRepeatedCue, "Keep your front knee steady")
        XCTAssertEqual(repeatedCue.value, "Keep your front knee steady")
        XCTAssertEqual(repeatedCue.evidenceRefs.count, 4)
        XCTAssertEqual(Set(repeatedCue.evidenceRefs.map { CueNormalizer.normalize($0.label) }), ["front knee steady"])
    }

    func testMostRepeatedCueUsesRecentSessionWindowByDefault() {
        let now = date(year: 2026, month: 5, day: 20, hour: 12)
        let profile = makeProfile()
        let trophies = emptyTrophySnapshot(now: now)
        var history = [
            makeSummary(
                idSuffix: "7110",
                endedAt: now,
                exerciseType: .lunge,
                cueMessages: ["Keep your chest tall"]
            )
        ]
        history += (1...11).map { offset in
            makeSummary(
                idSuffix: String(format: "%04d", 7110 + offset),
                endedAt: dayOffset(-offset, from: now),
                exerciseType: .lunge
            )
        }
        history += (12...14).map { offset in
            makeSummary(
                idSuffix: String(format: "%04d", 7110 + offset),
                endedAt: dayOffset(-offset, from: now),
                exerciseType: .lunge,
                cueMessages: ["Let your knee cave in"]
            )
        }

        let snapshot = TrendEngine(calendar: calendar).buildSnapshot(
            history: history,
            profile: profile,
            trophies: trophies,
            now: now
        )

        XCTAssertEqual(snapshot.mostRepeatedCue, "Keep your chest tall")
    }

    func testCameraFrictionCountUsesRecentSetupWindowByDefault() {
        let now = date(year: 2026, month: 5, day: 20, hour: 12)
        let profile = makeProfile()
        let trophies = emptyTrophySnapshot(now: now)
        let engine = TrendEngine(calendar: calendar)
        let oldCameraCue = makeSummary(
            idSuffix: "7130",
            endedAt: dayOffset(-15, from: now),
            exerciseType: .squat,
            cueMessages: ["Camera needs your full body in frame"]
        )
        let recentClean = makeSummary(
            idSuffix: "7131",
            endedAt: dayOffset(-1, from: now),
            exerciseType: .squat
        )
        let recentCameraCue = makeSummary(
            idSuffix: "7132",
            endedAt: dayOffset(-13, from: now),
            exerciseType: .squat,
            cueMessages: ["Move back so your full body is visible"]
        )

        let oldOnlySnapshot = engine.buildSnapshot(
            history: [recentClean, oldCameraCue],
            profile: profile,
            trophies: trophies,
            now: now
        )
        let recentSnapshot = engine.buildSnapshot(
            history: [recentClean, oldCameraCue, recentCameraCue],
            profile: profile,
            trophies: trophies,
            now: now
        )

        XCTAssertEqual(oldOnlySnapshot.cameraFrictionCount, 0)
        XCTAssertEqual(recentSnapshot.cameraFrictionCount, 1)
    }

    func testExerciseTrendCueCountsUseRecentExerciseSessionsByDefault() throws {
        let now = date(year: 2026, month: 5, day: 20, hour: 12)
        let profile = makeProfile()
        let trophies = emptyTrophySnapshot(now: now)
        var history = [
            makeSummary(
                idSuffix: "7140",
                endedAt: now,
                exerciseType: .lunge,
                cueMessages: ["Keep your ribs stacked"]
            )
        ]
        history += (1...4).map { offset in
            makeSummary(
                idSuffix: String(format: "%04d", 7140 + offset),
                endedAt: dayOffset(-offset, from: now),
                exerciseType: .lunge
            )
        }
        history.append(
            makeSummary(
                idSuffix: "7145",
                endedAt: dayOffset(-5, from: now),
                exerciseType: .lunge,
                cueMessages: ["Let your knee cave in", "Let your knee cave in", "Let your knee cave in"]
            )
        )

        let snapshot = TrendEngine(calendar: calendar).buildSnapshot(
            history: history,
            profile: profile,
            trophies: trophies,
            now: now
        )
        let trend = try XCTUnwrap(snapshot.exerciseTrends.first { $0.exerciseType == .lunge })

        XCTAssertEqual(trend.mostCommonCue, "Keep your ribs stacked")
        XCTAssertEqual(trend.highSeverityCueCount, 1)
    }

    func testRepeatedCueEvidenceRefsStayInsideRecentCueWindow() throws {
        let now = date(year: 2026, month: 5, day: 20, hour: 12)
        let profile = makeProfile()
        let engine = TrendEngine(calendar: calendar)
        let trophies = emptyTrophySnapshot(now: now)
        let recentCueSummaries = [
            makeSummary(
                idSuffix: "7150",
                endedAt: now,
                exerciseType: .pushup,
                cueMessages: ["Brace your ribs"]
            ),
            makeSummary(
                idSuffix: "7151",
                endedAt: dayOffset(-1, from: now),
                exerciseType: .pushup,
                cueMessages: ["Brace your ribs"]
            )
        ]
        let fillerSummaries = (2...6).map { offset in
            makeSummary(
                idSuffix: String(format: "%04d", 7150 + offset),
                endedAt: dayOffset(-offset, from: now),
                exerciseType: .pushup
            )
        }
        let oldCueSummaries = (7...9).map { offset in
            makeSummary(
                idSuffix: String(format: "%04d", 7150 + offset),
                endedAt: dayOffset(-offset, from: now),
                exerciseType: .pushup,
                cueMessages: ["Brace your ribs"]
            )
        }
        let history = recentCueSummaries + fillerSummaries + oldCueSummaries

        let snapshot = engine.buildSnapshot(
            history: history,
            profile: profile,
            trophies: trophies,
            now: now
        )
        let signals = SignalExtractor(trendEngine: engine).extractSignals(
            snapshot: snapshot,
            history: history,
            profile: profile,
            trophies: trophies
        )
        let repeatedCue = try XCTUnwrap(signals.first { $0.type == .repeatedCue })
        let recentSummaryIDs = Set(recentCueSummaries.map(\.id))

        XCTAssertEqual(snapshot.mostRepeatedCue, "Brace your ribs")
        XCTAssertEqual(repeatedCue.evidenceRefs.count, 2)
        XCTAssertEqual(repeatedCue.comparisonValue, "2 cue events")
        XCTAssertEqual(Set(repeatedCue.evidenceRefs.compactMap(\.summaryId)), recentSummaryIDs)
    }

    func testRecentSessionWindowsIgnoreFutureDatedHistory() {
        let now = date(year: 2026, month: 5, day: 20, hour: 12)
        let profile = makeProfile()
        let trophies = emptyTrophySnapshot(now: now)
        let engine = TrendEngine(calendar: calendar)
        let currentCue = makeSummary(
            idSuffix: "7160",
            endedAt: now,
            exerciseType: .pushup,
            cueMessages: ["Brace your ribs"]
        )
        let futureCue = makeSummary(
            idSuffix: "7161",
            endedAt: dayOffset(1, from: now),
            exerciseType: .pushup,
            cueMessages: ["Let your knee cave in", "Let your knee cave in", "Let your knee cave in"]
        )

        let snapshot = engine.buildSnapshot(
            history: [currentCue, futureCue],
            profile: profile,
            trophies: trophies,
            now: now
        )

        XCTAssertEqual(snapshot.totalWorkouts, 2)
        XCTAssertEqual(snapshot.mostRepeatedCue, "Brace your ribs")
    }

    func testFutureDatedSessionsDoNotConsumeRecentCueWindowSlots() {
        let now = date(year: 2026, month: 5, day: 20, hour: 12)
        let profile = makeProfile()
        let trophies = emptyTrophySnapshot(now: now)
        let currentCue = makeSummary(
            idSuffix: "7170",
            endedAt: now,
            exerciseType: .pushup,
            cueMessages: ["Brace your ribs"]
        )
        let futureSummaries = (1...7).map { offset in
            makeSummary(
                idSuffix: String(format: "%04d", 7170 + offset),
                endedAt: dayOffset(offset, from: now),
                exerciseType: .pushup,
                cueMessages: ["Future cue should not win"]
            )
        }

        let snapshot = TrendEngine(calendar: calendar).buildSnapshot(
            history: futureSummaries + [currentCue],
            profile: profile,
            trophies: trophies,
            now: now
        )

        XCTAssertEqual(snapshot.mostRepeatedCue, "Brace your ribs")
    }

    func testTrophyProximitySignal() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let profile = makeProfile()
        let history = [makeSummary(idSuffix: "7071", endedAt: now, reps: 12)]
        let trophies = trophySnapshot(
            now: now,
            customProgress: [
                TrophyDefinitionCatalog.ID.oneKClub: 850
            ]
        )
        let engine = TrendEngine(calendar: calendar)
        let snapshot = engine.buildSnapshot(
            history: history,
            profile: profile,
            trophies: trophies,
            now: now
        )

        let signals = SignalExtractor(trendEngine: engine).extractSignals(
            snapshot: snapshot,
            history: history,
            profile: profile,
            trophies: trophies
        )

        let signal = try XCTUnwrap(signals.first { $0.type == .trophyProximity })
        XCTAssertEqual(signal.confidence, .high)
        XCTAssertEqual(signal.value, "850/1000 reps")
    }

    func testCameraFrictionSignalIfDataExists() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let profile = makeProfile()
        let history = [
            makeSummary(
                idSuffix: "7081",
                endedAt: now,
                exerciseType: .squat,
                cueMessages: ["Move back so your full body is visible"]
            ),
            makeSummary(
                idSuffix: "7082",
                endedAt: date(year: 2026, month: 5, day: 5, hour: 12),
                exerciseType: .pushup,
                cueMessages: ["Camera needs your full body in frame"]
            )
        ]
        let engine = TrendEngine(calendar: calendar)
        let snapshot = engine.buildSnapshot(
            history: history,
            profile: profile,
            trophies: emptyTrophySnapshot(now: now),
            now: now
        )

        let signals = SignalExtractor(trendEngine: engine).extractSignals(
            snapshot: snapshot,
            history: history,
            profile: profile,
            trophies: emptyTrophySnapshot(now: now)
        )

        XCTAssertEqual(snapshot.cameraFrictionCount, 2)
        XCTAssertNotNil(signals.first { $0.type == .cameraFriction })
    }

    func testEmptyHistoryProducesSafeEmptySnapshot() {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let profile = makeProfile()
        let snapshot = TrendEngine(calendar: calendar).buildSnapshot(
            history: [],
            profile: profile,
            trophies: emptyTrophySnapshot(now: now),
            now: now
        )

        XCTAssertEqual(snapshot.totalWorkouts, 0)
        XCTAssertEqual(snapshot.currentStreak, 0)
        XCTAssertEqual(snapshot.workoutsThisWeek, 0)
        XCTAssertEqual(snapshot.workoutDaysThisWeek, 0)
        XCTAssertEqual(snapshot.weeklyConsistencyStatus, .noHistory)
        XCTAssertEqual(snapshot.overallFormTrend, .unavailable)
        XCTAssertNil(snapshot.strongestExercise)
        XCTAssertTrue(snapshot.exerciseTrends.isEmpty)
    }

    func testCompletionSignalUsesActiveDaysNotSameDayWorkoutCount() throws {
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let profile = makeProfile(workoutDaysPerWeek: 1)
        let history = [
            makeSummary(idSuffix: "7101", endedAt: now),
            makeSummary(idSuffix: "7102", endedAt: date(year: 2026, month: 5, day: 6, hour: 18))
        ]
        let engine = TrendEngine(calendar: calendar)
        let trophies = emptyTrophySnapshot(now: now)
        let snapshot = engine.buildSnapshot(
            history: history,
            profile: profile,
            trophies: trophies,
            now: now
        )

        let signals = SignalExtractor(trendEngine: engine).extractSignals(
            snapshot: snapshot,
            history: history,
            profile: profile,
            trophies: trophies
        )

        let signal = try XCTUnwrap(signals.first { $0.type == .completion })
        XCTAssertEqual(snapshot.workoutsThisWeek, 2)
        XCTAssertEqual(snapshot.workoutDaysThisWeek, 1)
        XCTAssertEqual(signal.value, "1 day this week")
        XCTAssertEqual(signal.comparisonValue, "1 day target")
        XCTAssertEqual(signal.delta, 0.0)
    }

    func testTimezoneBoundariesAreStable() throws {
        let profile = makeProfile(timezoneIdentifier: "Asia/Kolkata")
        let now = date(year: 2026, month: 5, day: 6, hour: 4, minute: 30)
        let mayFiveLocal = date(year: 2026, month: 5, day: 4, hour: 19, minute: 15)
        let maySixLocalFirst = date(year: 2026, month: 5, day: 5, hour: 18, minute: 45)
        let maySixLocalSecond = date(year: 2026, month: 5, day: 5, hour: 19, minute: 15)
        let history = [
            makeSummary(idSuffix: "7091", endedAt: mayFiveLocal),
            makeSummary(idSuffix: "7092", endedAt: maySixLocalFirst),
            makeSummary(idSuffix: "7093", endedAt: maySixLocalSecond)
        ]
        let engine = TrendEngine(calendar: calendar)

        let counts = engine.dailyWorkoutCounts(history: history, profile: profile)
        let snapshot = engine.monthSnapshot(history: history, profile: profile, now: now)

        XCTAssertEqual(engine.currentStreak(history: history, profile: profile, now: now), 2)
        XCTAssertEqual(counts.values.sorted(), [1, 2])
        XCTAssertEqual(snapshot.completedDays.count, 2)
        XCTAssertEqual(snapshot.timeZoneIdentifier, "Asia/Kolkata")
    }

    func testDailyIntensitySummaryReturnsFullTwelveWeekWindow() throws {
        let profile = makeProfile()
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "7121", endedAt: now, reps: 40, averageFormScore: 88),
            makeSummary(
                idSuffix: "7122",
                endedAt: date(year: 2026, month: 4, day: 12, hour: 12),
                reps: 30,
                holdSeconds: 90,
                averageFormScore: 82
            )
        ]

        let summary = TrendEngine(calendar: calendar).dailyIntensitySummary(
            history: history,
            profile: profile,
            days: 84,
            now: now
        )
        let today = calendar.startOfDay(for: now)
        let oldestDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -83, to: today))

        XCTAssertEqual(summary.count, 84)
        XCTAssertNotNil(summary[today])
        XCTAssertNotNil(summary[oldestDay])
        XCTAssertEqual(summary[today]?.workoutCount, 1)
    }

    func testDailyIntensitySummaryCombinesWorkoutQualityAndVolumeIntoIntensity() throws {
        let profile = makeProfile()
        let now = date(year: 2026, month: 5, day: 6, hour: 12)
        let history = [
            makeSummary(idSuffix: "7131", endedAt: now, reps: 70, averageFormScore: 90),
            makeSummary(
                idSuffix: "7132",
                endedAt: date(year: 2026, month: 5, day: 6, hour: 18),
                reps: 45,
                holdSeconds: 30,
                averageFormScore: 86
            )
        ]

        let summary = TrendEngine(calendar: calendar).dailyIntensitySummary(
            history: history,
            profile: profile,
            days: 84,
            now: now
        )
        let day = try XCTUnwrap(summary[calendar.startOfDay(for: now)])

        XCTAssertEqual(day.workoutCount, 2)
        XCTAssertEqual(day.totalReps, 115)
        XCTAssertEqual(day.sessions.count, 2)
        XCTAssertEqual(day.intensity, 4)
    }
}

private extension TrendEngineTests {
    func makeProfile(
        timezoneIdentifier: String = "UTC",
        limitations: Set<PhysicalLimitation> = [],
        workoutDaysPerWeek: Int? = 3
    ) -> UserProfile {
        UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000007999") ?? UUID(),
            displayName: "Test Athlete",
            genderIdentity: .preferNotToSay,
            age: 30,
            height: 170,
            heightUnit: .metric,
            weight: 70,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .beginner,
            equipment: [.bodyweight],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            limitations: limitations,
            preferredSessionLength: .fifteen,
            workoutDaysPerWeek: workoutDaysPerWeek,
            reminderPreference: .none,
            timezoneIdentifier: timezoneIdentifier,
            avatarStyle: .default,
            onboardingCompletedAt: date(year: 2026, month: 5, day: 1, hour: 9),
            createdAt: date(year: 2026, month: 5, day: 1, hour: 9),
            updatedAt: date(year: 2026, month: 5, day: 1, hour: 9)
        )
    }

    func makeSummary(
        idSuffix: String,
        endedAt: Date,
        exerciseType: ExerciseType = .squat,
        reps: Int = 10,
        holdSeconds: Int = 0,
        averageFormScore: Double? = 84,
        scores: [Int] = [],
        cueMessages: [String] = [],
        restExtended: Bool = false,
        skipped: Bool = false
    ) -> WorkoutSessionSummary {
        let setSummary = makeSetSummary(
            exerciseType: exerciseType,
            endedAt: endedAt,
            reps: scores.isEmpty ? reps : scores.count,
            holdSeconds: holdSeconds,
            averageFormScore: averageFormScore,
            scores: scores,
            cueMessages: cueMessages,
            restExtended: restExtended,
            skipped: skipped
        )
        let topCue = setSummary.cueEvents.first
        let resolvedReps = scores.isEmpty ? reps : scores.count
        let resolvedAverage = setSummary.qualitySummary?.averageFormScore ?? averageFormScore

        return WorkoutSessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000\(idSuffix)") ?? UUID(),
            mode: .plannedWorkout,
            planId: UUID(uuidString: "00000000-0000-0000-0000-000000007000"),
            title: "\(exerciseType.displayName) Trend",
            goal: "Build clean strength.",
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            durationSeconds: 600,
            totalReps: resolvedReps,
            totalHoldSeconds: holdSeconds,
            averageFormScore: resolvedAverage,
            completionPercent: skipped ? 0.5 : 1,
            exerciseSummaries: [setSummary],
            topCue: topCue,
            effortSummary: "No face-effort signal was captured for this session.",
            workoutOutcome: skipped ? .partial : .completed,
            structuredEffortSummary: nil,
            createdAt: endedAt
        )
    }

    func makeSetSummary(
        exerciseType: ExerciseType,
        endedAt: Date,
        reps: Int,
        holdSeconds: Int,
        averageFormScore: Double?,
        scores: [Int],
        cueMessages: [String],
        restExtended: Bool,
        skipped: Bool
    ) -> ExerciseSetSummary {
        let repEvents = scores.enumerated().map { index, score in
            RepQualityEvent(
                exerciseType: exerciseType,
                setIndex: 0,
                repIndex: index + 1,
                timestamp: endedAt.addingTimeInterval(TimeInterval(index - scores.count)),
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
                timestamp: endedAt.addingTimeInterval(TimeInterval(index)),
                exerciseType: exerciseType,
                cueMessage: message,
                severity: .warning,
                setIndex: 0,
                repIndex: scores.isEmpty ? nil : min(index + 1, scores.count),
                secondsIntoSet: TimeInterval((index + 1) * 5),
                formScoreAtEvent: scores.dropFirst(index).first
            )
        }
        let quality = scores.isEmpty
            ? nil
            : SetQualitySummary.build(repQualityEvents: repEvents, cueEvents: cueEvents)

        return ExerciseSetSummary(
            exerciseType: exerciseType,
            setIndex: 0,
            target: reps > 0 ? .reps(reps) : .hold(seconds: holdSeconds),
            achievedReps: reps,
            achievedHoldSeconds: holdSeconds,
            averageFormScore: quality?.averageFormScore ?? averageFormScore,
            cueEvents: cueEvents,
            restExtended: restExtended,
            skipped: skipped,
            qualitySummary: quality,
            repQualityEvents: repEvents,
            completionSource: skipped ? .manual : .targetMet,
            completedAt: endedAt,
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

    func dayOffset(_ days: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}
