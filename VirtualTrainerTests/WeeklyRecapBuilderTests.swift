import XCTest
@testable import VirtualTrainer

final class WeeklyRecapBuilderTests: XCTestCase {
    func testEmptyWeekStillAcknowledgesRestAndProvidesEvidence() throws {
        let now = date(year: 2026, month: 5, day: 4, hour: 9)
        let recap = try XCTUnwrap(
            WeeklyRecapBuilder(calendar: calendar).build(
                history: [],
                profile: makeProfile(),
                trophies: TrophyProgressSnapshot.empty(now: now),
                now: now
            )
        )

        XCTAssertEqual(recap.stats.first { $0.label == "Sessions" }?.value, "0")
        XCTAssertTrue(recap.narrative.lowercased().contains("no saved sessions"))
        XCTAssertTrue(recap.narrative.lowercased().contains("baseline"))
        XCTAssertFalse(recap.evidence.isEmpty)
        XCTAssertFalse(recap.nextWeekFocus.isEmpty)
    }

    func testNormalWeekBuildsStatsEvidenceAndForwardNudge() throws {
        let now = date(year: 2026, month: 5, day: 4, hour: 9)
        let first = makeSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101") ?? UUID(),
            title: "Clean Squat",
            endedAt: date(year: 2026, month: 4, day: 29, hour: 18),
            exerciseType: .squat,
            reps: 18,
            holdSeconds: 0,
            averageForm: 91
        )
        let second = makeSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102") ?? UUID(),
            title: "Core Hold",
            endedAt: date(year: 2026, month: 5, day: 2, hour: 8),
            exerciseType: .plank,
            reps: 0,
            holdSeconds: 90,
            averageForm: 84
        )

        let recap = try XCTUnwrap(
            WeeklyRecapBuilder(calendar: calendar).build(
                history: [first, second],
                profile: makeProfile(goal: .strength),
                trophies: TrophyProgressSnapshot.empty(now: now),
                now: now
            )
        )

        XCTAssertEqual(recap.stats.first { $0.label == "Sessions" }?.value, "2")
        XCTAssertEqual(recap.stats.first { $0.label == "Total reps" }?.value, "18")
        XCTAssertEqual(recap.stats.first { $0.label == "Hold" }?.value, "1:30")
        XCTAssertEqual(recap.evidence.count, 2)
        XCTAssertTrue(recap.evidence.allSatisfy { $0.workoutId != nil })
        XCTAssertTrue(recap.nextWeekFocus.contains("Next week"))
        XCTAssertTrue(recap.narrative.contains("18 reps"))
    }

    func testAllRestWeekWithOlderHistoryTreatsRestAsSignal() throws {
        let now = date(year: 2026, month: 5, day: 4, hour: 9)
        let older = makeSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201") ?? UUID(),
            title: "Older Push-Up",
            endedAt: date(year: 2026, month: 4, day: 20, hour: 7),
            exerciseType: .pushup,
            reps: 12,
            holdSeconds: 0,
            averageForm: 82
        )

        let recap = try XCTUnwrap(
            WeeklyRecapBuilder(calendar: calendar).build(
                history: [older],
                profile: makeProfile(goal: .longevity),
                trophies: TrophyProgressSnapshot.empty(now: now),
                now: now
            )
        )

        XCTAssertEqual(recap.stats.first { $0.label == "Sessions" }?.value, "0")
        XCTAssertTrue(recap.headline.lowercased().contains("recovery"))
        XCTAssertTrue(recap.biggestSurprise.lowercased().contains("rest week"))
        XCTAssertEqual(recap.evidence.first?.metric, "weeklyRest")
        XCTAssertTrue(recap.nextWeekFocus.lowercased().contains("restart"))
    }
}

private extension WeeklyRecapBuilderTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        return calendar
    }

    func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        ) ?? Date()
    }

    func makeProfile(goal: FitnessGoal = .strength) -> UserProfile {
        let now = date(year: 2026, month: 4, day: 1, hour: 9)
        return UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000006666") ?? UUID(),
            displayName: "Weekly Tester",
            genderIdentity: .preferNotToSay,
            age: 32,
            height: 170,
            heightUnit: .metric,
            weight: 70,
            weightUnit: .metric,
            primaryGoal: goal,
            fitnessLevel: .beginner,
            equipment: [.bodyweight, .mat],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            preferredSessionLength: .fifteen,
            timezoneIdentifier: "Asia/Kolkata",
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    func makeSummary(
        id: UUID,
        title: String,
        endedAt: Date,
        exerciseType: ExerciseType,
        reps: Int,
        holdSeconds: Int,
        averageForm: Double?
    ) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            id: id,
            mode: .plannedWorkout,
            planTitle: title,
            title: title,
            goal: "Build clean strength.",
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-900),
            endedAt: endedAt,
            durationSeconds: 900,
            totalReps: reps,
            totalHoldSeconds: holdSeconds,
            averageFormScore: averageForm,
            completionPercent: 1,
            exerciseSummaries: [
                ExerciseSetSummary(
                    exerciseType: exerciseType,
                    setIndex: 0,
                    target: reps > 0 ? .reps(reps) : .hold(seconds: holdSeconds),
                    achievedReps: reps,
                    achievedHoldSeconds: holdSeconds,
                    averageFormScore: averageForm
                )
            ],
            topCue: nil,
            effortSummary: "Controlled session.",
            createdAt: endedAt
        )
    }
}
