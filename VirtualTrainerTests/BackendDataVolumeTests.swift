import XCTest
@testable import VirtualTrainer

@MainActor
final class BackendDataVolumeTests: XCTestCase {
    private let accountId = "phase-17-volume-account"
    private let now = Date(timeIntervalSince1970: 1_779_900_000)

    func testHundredWorkoutsProfileAndHistoryLoadStaySnappy() throws {
        let directory = try makeTemporaryDirectory(named: "hundred-workouts")
        let profileURL = directory.appendingPathComponent("UserProfile.json")
        let historyURL = directory.appendingPathComponent("WorkoutHistory.json")
        try write(makeProfile(), to: profileURL)
        try write(makeSummaries(count: 100, setCount: 4), to: historyURL)

        let startedAt = Date()
        let profileStore = OnboardingStore(fileURL: profileURL, accountId: accountId)
        let historyStore = WorkoutHistoryStore(fileURL: historyURL, accountId: accountId)
        let recent = historyStore.fetchRecentSummaries(limit: 100)
        let stats = historyStore.aggregateStats(now: now)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(profileStore.profile?.accountId, accountId)
        XCTAssertEqual(recent.count, 100)
        XCTAssertEqual(stats.sessionCount, 100)
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testFiveHundredWorkoutsHeatmapAndHistoryStayResponsive() throws {
        let directory = try makeTemporaryDirectory(named: "five-hundred-workouts")
        let historyURL = directory.appendingPathComponent("WorkoutHistory.json")
        let summaries = makeSummaries(count: 500, setCount: 4)
        try write(summaries, to: historyURL)

        let historyStore = WorkoutHistoryStore(fileURL: historyURL, accountId: accountId)
        let profile = makeProfile()
        let startedAt = Date()
        let recent = historyStore.fetchRecentSummaries(limit: 500)
        let heatmap = TrendEngine().dailyIntensitySummary(
            history: recent,
            profile: profile,
            days: TrainingHeatmapView.defaultDayCount,
            now: now
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(recent.count, 500)
        XCTAssertEqual(heatmap.count, TrainingHeatmapView.defaultDayCount)
        XCTAssertLessThan(elapsed, 1.5)
    }

    func testLargestWorkoutDetailLoadsUnderOnePointFiveSeconds() async throws {
        let directory = try makeTemporaryDirectory(named: "largest-workout-detail")
        let historyURL = directory.appendingPathComponent("WorkoutHistory.json")
        let workoutId = fixedUUID(17_900)
        let compactSummary = makeSummary(id: workoutId, index: 0, setCount: 0)
        let detailedSummary = makeSummary(id: workoutId, index: 0, setCount: 32)
        try write([compactSummary], to: historyURL)

        let repository = DetailWorkoutRepository(summary: detailedSummary)
        let historyStore = WorkoutHistoryStore(fileURL: historyURL, accountId: accountId)
        historyStore.configureRemoteSync(
            backendMode: .firebase,
            workoutRepository: repository,
            autoObserve: false
        )

        let startedAt = Date()
        let loadedSummary = await historyStore.loadDetailedSummaryIfNeeded(id: workoutId)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(loadedSummary?.exerciseSummaries.count, 32)
        XCTAssertLessThan(elapsed, 1.5)
    }
}

private extension BackendDataVolumeTests {
    func makeProfile() -> UserProfile {
        UserProfile(
            id: fixedUUID(17_001),
            accountId: accountId,
            displayName: "Volume Tester",
            genderIdentity: .preferNotToSay,
            age: 34,
            height: 174,
            heightUnit: .metric,
            weight: 73,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .intermediate,
            equipment: [.bodyweight, .dumbbells, .mat],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            preferredSessionLength: .twentyFive,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now,
            syncMetadata: .initialPendingUpload(operationId: nil, now: now)
        )
    }

    func makeSummaries(count: Int, setCount: Int) -> [WorkoutSessionSummary] {
        (0..<count).map { index in
            makeSummary(id: fixedUUID(18_000 + index), index: index, setCount: setCount)
        }
    }

    func makeSummary(id: UUID, index: Int, setCount: Int) -> WorkoutSessionSummary {
        let endedAt = now.addingTimeInterval(-Double(index * 3_600))
        let sets = (0..<setCount).map { setIndex in
            ExerciseSetSummary(
                exerciseType: setIndex.isMultiple(of: 2) ? .squat : .pushup,
                setIndex: setIndex,
                target: .reps(10),
                achievedReps: 10 + (setIndex % 4),
                achievedHoldSeconds: 0,
                averageFormScore: 82 + Double(setIndex % 12),
                completionSource: .targetMet,
                completedAt: endedAt.addingTimeInterval(Double(setIndex * 60)),
                durationSeconds: 45,
                peakEffort: 0.72
            )
        }

        return WorkoutSessionSummary(
            id: id,
            accountId: accountId,
            mode: index.isMultiple(of: 3) ? .freeAnalysis : .plannedWorkout,
            planId: index.isMultiple(of: 3) ? nil : fixedUUID(19_000 + index),
            planTitle: index.isMultiple(of: 3) ? nil : "Volume Plan",
            title: index.isMultiple(of: 3) ? "Free Analysis" : "Volume Plan",
            goal: "Keep the saved history responsive.",
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-1_800),
            endedAt: endedAt,
            durationSeconds: 1_800,
            totalReps: sets.reduce(0) { $0 + $1.achievedReps },
            totalHoldSeconds: 0,
            averageFormScore: 86,
            completionPercent: 1,
            exerciseSummaries: sets,
            topCue: nil,
            effortSummary: "Volume test summary.",
            createdAt: endedAt,
            syncMetadata: .initialPendingUpload(operationId: nil, now: endedAt)
        )
    }

    func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotterBackendDataVolumeTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }
}

@MainActor
private final class DetailWorkoutRepository: WorkoutRepository {
    private let summary: WorkoutSessionSummary

    init(summary: WorkoutSessionSummary) {
        self.summary = summary
    }

    func saveWorkoutSummary(
        _ summary: WorkoutSessionSummary,
        operationId _: UUID
    ) async throws -> WorkoutSessionSummary {
        summary
    }

    func loadRecentWorkouts(
        accountId _: String,
        limit _: Int,
        since _: Date?
    ) async throws -> [WorkoutSessionSummary] {
        [summary]
    }

    func loadWorkout(accountId _: String, id: UUID) async throws -> WorkoutSessionSummary? {
        summary.id == id ? summary : nil
    }

    func deleteWorkout(accountId _: String, id _: UUID, operationId _: UUID) async throws {}

    func observeRecentWorkouts(accountId _: String, limit _: Int) async throws -> AsyncStream<[WorkoutSessionSummary]> {
        AsyncStream { continuation in
            continuation.yield([summary])
        }
    }
}
