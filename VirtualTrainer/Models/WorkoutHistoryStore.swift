import Foundation
import Combine

nonisolated struct WorkoutHistoryStats: Equatable {
    let sessionCount: Int
    let currentStreak: Int
    let longestStreak: Int
    let workoutsThisWeek: Int
    let plannedWorkoutCount: Int
    let freeAnalysisCount: Int
    let totalDurationSeconds: Int
    let totalReps: Int
    let totalHoldSeconds: Int
    let totalGoodFormReps: Int
    let totalExcellentFormReps: Int
    let totalHighSeverityCues: Int
    let averageFormScore: Double?
    let averageCompletionPercent: Double?
    let firstWorkoutAt: Date?
    let latestWorkoutAt: Date?
    let mostTrainedExerciseType: ExerciseType?
    let mostImprovedExerciseType: ExerciseType?

    static let empty = WorkoutHistoryStats(
        sessionCount: 0,
        currentStreak: 0,
        longestStreak: 0,
        workoutsThisWeek: 0,
        plannedWorkoutCount: 0,
        freeAnalysisCount: 0,
        totalDurationSeconds: 0,
        totalReps: 0,
        totalHoldSeconds: 0,
        totalGoodFormReps: 0,
        totalExcellentFormReps: 0,
        totalHighSeverityCues: 0,
        averageFormScore: nil,
        averageCompletionPercent: nil,
        firstWorkoutAt: nil,
        latestWorkoutAt: nil,
        mostTrainedExerciseType: nil,
        mostImprovedExerciseType: nil
    )
}

@MainActor
final class WorkoutHistoryStore: ObservableObject {
    @Published private(set) var summaries: [WorkoutSessionSummary] = []
    @Published var persistenceError: String?

    private let fileURL: URL
    private let calendar: Calendar
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil, calendar: Calendar = .current) {
        self.fileURL = fileURL ?? Self.defaultHistoryURL()
        self.calendar = calendar
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadSummaries()
    }

    nonisolated deinit {}

    @discardableResult
    func addSummary(_ summary: WorkoutSessionSummary) -> Bool {
        let previousSummaries = summaries
        if let existingIndex = summaries.firstIndex(where: { $0.id == summary.id }) {
            summaries[existingIndex] = summary
        } else {
            summaries.append(summary)
        }
        summaries = sortedSummaries(summaries)
        guard persist() else {
            summaries = previousSummaries
            return false
        }
        return true
    }

    func fetchRecentSummaries(limit: Int = 10) -> [WorkoutSessionSummary] {
        let safeLimit = max(limit, 0)
        return Array(sortedSummaries(summaries).prefix(safeLimit))
    }

    func fetchSummary(id: UUID) -> WorkoutSessionSummary? {
        summaries.first { $0.id == id }
    }

    func aggregateStats(now: Date = Date()) -> WorkoutHistoryStats {
        guard !summaries.isEmpty else { return .empty }

        let plannedCount = summaries.filter { $0.mode == .plannedWorkout }.count
        let freeCount = summaries.filter { $0.mode == .freeAnalysis }.count
        let formScores = summaries.compactMap(\.averageFormScore)
        let completionScores = summaries.compactMap(\.completionPercent)
        let exerciseCounts = summaries
            .flatMap(\.exerciseSummaries)
            .reduce(into: [ExerciseType: Int]()) { result, exercise in
                result[exercise.exerciseType, default: 0] += 1
            }
        let workoutDays = Set(summaries.map { calendar.startOfDay(for: $0.endedAt) })

        return WorkoutHistoryStats(
            sessionCount: summaries.count,
            currentStreak: currentStreakDays(from: workoutDays, now: now),
            longestStreak: longestStreakDays(from: workoutDays),
            workoutsThisWeek: workoutsThisWeek(now: now),
            plannedWorkoutCount: plannedCount,
            freeAnalysisCount: freeCount,
            totalDurationSeconds: summaries.reduce(0) { $0 + $1.durationSeconds },
            totalReps: summaries.reduce(0) { $0 + $1.totalReps },
            totalHoldSeconds: summaries.reduce(0) { $0 + $1.totalHoldSeconds },
            totalGoodFormReps: summaries.reduce(0) { $0 + $1.totalGoodFormReps },
            totalExcellentFormReps: summaries.reduce(0) { $0 + $1.totalExcellentFormReps },
            totalHighSeverityCues: summaries.reduce(0) { $0 + $1.totalHighSeverityCues },
            averageFormScore: average(formScores),
            averageCompletionPercent: average(completionScores),
            firstWorkoutAt: summaries.map(\.endedAt).min(),
            latestWorkoutAt: summaries.map(\.endedAt).max(),
            mostTrainedExerciseType: exerciseCounts.max { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.rawValue < rhs.key.rawValue
                }
                return lhs.value < rhs.value
            }?.key,
            mostImprovedExerciseType: mostImprovedExerciseType()
        )
    }

    func recentWorkoutHistoryItems(limit: Int = 20) -> [RecentWorkoutHistoryItem] {
        fetchRecentSummaries(limit: limit).compactMap { summary in
            guard let exerciseType = summary.primaryExerciseType else { return nil }
            return RecentWorkoutHistoryItem(
                id: summary.id,
                exerciseType: exerciseType,
                completedAt: summary.endedAt
            )
        }
    }

    func reload() {
        loadSummaries()
    }

    private func loadSummaries() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            summaries = []
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            summaries = sortedSummaries(try decoder.decode([WorkoutSessionSummary].self, from: data))
            persistenceError = nil
        } catch {
            summaries = []
            persistenceError = "Could not load workout history: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(summaries)
            try data.write(to: fileURL, options: [.atomic])
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Could not save workout history: \(error.localizedDescription)"
            return false
        }
    }

    private func sortedSummaries(
        _ summaries: [WorkoutSessionSummary]
    ) -> [WorkoutSessionSummary] {
        summaries.sorted {
            if $0.endedAt == $1.endedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.endedAt > $1.endedAt
        }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func currentStreakDays(from workoutDays: Set<Date>, now: Date) -> Int {
        guard !workoutDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var cursor = workoutDays.contains(today) ? today : yesterday
        var streak = 0

        while workoutDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }

        return streak
    }

    private func longestStreakDays(from workoutDays: Set<Date>) -> Int {
        let sortedDays = workoutDays.sorted()
        guard !sortedDays.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for index in sortedDays.indices.dropFirst() {
            let previous = sortedDays[sortedDays.index(before: index)]
            let day = sortedDays[index]
            let expectedNext = calendar.date(byAdding: .day, value: 1, to: previous)
            if expectedNext == day {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
        }

        return longest
    }

    private func workoutsThisWeek(now: Date) -> Int {
        let currentWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
        return summaries.filter { summary in
            let workoutWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: summary.endedAt)
            return workoutWeek.weekOfYear == currentWeek.weekOfYear &&
                workoutWeek.yearForWeekOfYear == currentWeek.yearForWeekOfYear
        }.count
    }

    private func mostImprovedExerciseType() -> ExerciseType? {
        let improvements = summaries
            .flatMap(\.exerciseSummaries)
            .reduce(into: [ExerciseType: Double]()) { result, setSummary in
                guard let first = setSummary.qualitySummary?.firstHalfAverageFormScore,
                      let second = setSummary.qualitySummary?.secondHalfAverageFormScore
                else { return }

                let delta = second - first
                guard delta > 0 else { return }
                result[setSummary.exerciseType, default: 0] += delta
            }

        return improvements.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.rawValue < rhs.key.rawValue
            }
            return lhs.value < rhs.value
        }?.key
    }

    private static func defaultHistoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("WorkoutHistory.json")
    }
}
