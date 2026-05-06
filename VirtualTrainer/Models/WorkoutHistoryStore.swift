import Foundation
import Combine

nonisolated struct WorkoutHistoryStats: Equatable {
    let sessionCount: Int
    let plannedWorkoutCount: Int
    let freeAnalysisCount: Int
    let totalDurationSeconds: Int
    let totalReps: Int
    let totalHoldSeconds: Int
    let averageFormScore: Double?
    let averageCompletionPercent: Double?
    let firstWorkoutAt: Date?
    let latestWorkoutAt: Date?
    let mostTrainedExerciseType: ExerciseType?

    static let empty = WorkoutHistoryStats(
        sessionCount: 0,
        plannedWorkoutCount: 0,
        freeAnalysisCount: 0,
        totalDurationSeconds: 0,
        totalReps: 0,
        totalHoldSeconds: 0,
        averageFormScore: nil,
        averageCompletionPercent: nil,
        firstWorkoutAt: nil,
        latestWorkoutAt: nil,
        mostTrainedExerciseType: nil
    )
}

@MainActor
final class WorkoutHistoryStore: ObservableObject {
    @Published private(set) var summaries: [WorkoutSessionSummary] = []
    @Published var persistenceError: String?

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultHistoryURL()
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

    func aggregateStats() -> WorkoutHistoryStats {
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

        return WorkoutHistoryStats(
            sessionCount: summaries.count,
            plannedWorkoutCount: plannedCount,
            freeAnalysisCount: freeCount,
            totalDurationSeconds: summaries.reduce(0) { $0 + $1.durationSeconds },
            totalReps: summaries.reduce(0) { $0 + $1.totalReps },
            totalHoldSeconds: summaries.reduce(0) { $0 + $1.totalHoldSeconds },
            averageFormScore: average(formScores),
            averageCompletionPercent: average(completionScores),
            firstWorkoutAt: summaries.map(\.endedAt).min(),
            latestWorkoutAt: summaries.map(\.endedAt).max(),
            mostTrainedExerciseType: exerciseCounts.max { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.rawValue < rhs.key.rawValue
                }
                return lhs.value < rhs.value
            }?.key
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

    private static func defaultHistoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("WorkoutHistory.json")
    }
}
