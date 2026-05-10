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
    private let writeJournal: LocalWriteJournal
    private let decoder = JSONDecoder()
    private let persistenceActor: PersistenceActor
    private var currentAccountId: String?
    private var allSummaries: [WorkoutSessionSummary] = []
    private var persistedAllSummaries: [WorkoutSessionSummary] = []
    private var persistenceGeneration = 0

    init(
        fileURL: URL? = nil,
        calendar: Calendar = .current,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let resolvedFileURL = fileURL ?? Self.defaultHistoryURL()
        self.fileURL = resolvedFileURL
        self.calendar = calendar
        self.writeJournal = writeJournal ?? LocalWriteJournal(
            fileURL: LocalWriteJournal.defaultJournalURL(alongside: resolvedFileURL),
            persistenceActor: persistenceActor
        )
        self.persistenceActor = persistenceActor
        self.currentAccountId = AccountOwnership.normalizedAccountId(accountId)
        decoder.dateDecodingStrategy = .iso8601
        loadSummaries()
    }

    nonisolated deinit {}

    func setCurrentAccountId(_ accountId: String?) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        guard currentAccountId != normalizedAccountId else { return }
        currentAccountId = normalizedAccountId
        applyAllSummaries(allSummaries)
    }

    @discardableResult
    func addSummary(_ summary: WorkoutSessionSummary, operationId: UUID? = nil) async -> Bool {
        await upsert(summary, operationId: operationId)
    }

    @discardableResult
    func updateSummary(_ summary: WorkoutSessionSummary, operationId: UUID? = nil) async -> Bool {
        await upsert(summary, operationId: operationId)
    }

    @discardableResult
    func deleteSummary(id: UUID, deletedAt: Date = Date(), operationId: UUID? = nil) async -> Bool {
        let writeOperationId = operationId ?? UUID()
        guard let existingIndex = allSummaries.firstIndex(where: {
            $0.id == id && isVisible($0)
        }) else {
            return false
        }

        let previousAllSummaries = allSummaries
        var updatedSummaries = allSummaries
        updatedSummaries[existingIndex] = updatedSummaries[existingIndex].markedDeleted(
            at: deletedAt,
            operationId: writeOperationId
        )

        let generation = applyLocalMutation(updatedSummaries)
        if await writeJournal.contains(operationId: writeOperationId) {
            rollbackLocalMutationIfNeeded(generation: generation, allSummaries: previousAllSummaries)
            return true
        }
        guard await persist(generation: generation) != nil else { return false }
        await recordWriteOperation(writeOperationId, entityKind: .workout, createdAt: deletedAt)
        return true
    }

    @discardableResult
    func restoreSummary(id: UUID, operationId: UUID? = nil) async -> Bool {
        let writeOperationId = operationId ?? UUID()
        guard let existingIndex = allSummaries.firstIndex(where: {
            $0.id == id && isVisible($0)
        }) else {
            return false
        }

        let writeCreatedAt = Date()
        let previousAllSummaries = allSummaries
        var updatedSummaries = allSummaries
        updatedSummaries[existingIndex] = updatedSummaries[existingIndex].restored(
            operationId: writeOperationId
        )

        let generation = applyLocalMutation(updatedSummaries)
        if await writeJournal.contains(operationId: writeOperationId) {
            rollbackLocalMutationIfNeeded(generation: generation, allSummaries: previousAllSummaries)
            return true
        }
        guard await persist(generation: generation) != nil else { return false }
        await recordWriteOperation(writeOperationId, entityKind: .workout, createdAt: writeCreatedAt)
        return true
    }

    @discardableResult
    func purgeTombstones(olderThan cutoff: Date) async -> Int {
        let updatedSummaries = allSummaries.filter { summary in
            guard let deletedAt = summary.deletedAt else { return true }
            return deletedAt >= cutoff
        }
        let purgedCount = allSummaries.count - updatedSummaries.count
        guard purgedCount > 0 else { return 0 }

        let generation = applyLocalMutation(updatedSummaries)
        guard await persist(generation: generation) != nil else { return 0 }
        return purgedCount
    }

    @discardableResult
    func removeSummariesForDebug(ids: Set<UUID>) async -> Bool {
        guard !ids.isEmpty else { return true }

        let updatedSummaries = allSummaries.filter { !ids.contains($0.id) }
        guard updatedSummaries.count != allSummaries.count else { return true }

        let generation = applyLocalMutation(updatedSummaries)
        return await persist(generation: generation) != nil
    }

    func fetchRecentSummaries(limit: Int = 10) -> [WorkoutSessionSummary] {
        let safeLimit = max(limit, 0)
        return Array(sortedSummaries(summaries).prefix(safeLimit))
    }

    func fetchSummary(id: UUID) -> WorkoutSessionSummary? {
        summaries.first { $0.id == id }
    }

    func fetchSummaryIncludingDeleted(id: UUID) -> WorkoutSessionSummary? {
        allSummaries.first { $0.id == id && isVisible($0) }
    }

    func allSummariesIncludingTombstones() -> [WorkoutSessionSummary] {
        sortedSummaries(allSummaries.filter(isVisible))
    }

    func fetchDeletedSummaries() -> [WorkoutSessionSummary] {
        sortedSummaries(allSummaries.filter { $0.isDeleted && isVisible($0) })
    }

    func fetchDirtyOrDeletedSummaries() -> [WorkoutSessionSummary] {
        sortedSummaries(
            allSummaries.filter {
                isVisible($0) &&
                    ($0.isDeleted ||
                     $0.syncMetadata.syncState == .pendingUpload ||
                     $0.syncMetadata.syncState == .conflict)
            }
        )
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
        let workoutDays = Set(summaries.map { calendar.startOfDay(for: $0.authoritativeEndedAt) })

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
            firstWorkoutAt: summaries.map(\.authoritativeEndedAt).min(),
            latestWorkoutAt: summaries.map(\.authoritativeEndedAt).max(),
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
                completedAt: summary.authoritativeEndedAt
            )
        }
    }

    func reload() {
        loadSummaries()
    }

    @discardableResult
    func claimLocalDataForAccount(id accountId: String, operationId: UUID? = nil) async -> Bool {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            persistenceError = "Account id is required before local workout history can be claimed."
            return false
        }
        guard allSummaries.contains(where: { $0.accountId == nil }) else { return true }

        let writeOperationId = operationId ?? UUID()

        let writeCreatedAt = Date()
        let previousAllSummaries = allSummaries
        let updatedSummaries = allSummaries.map { summary in
            summary.accountId == nil
                ? summary.withAccountId(
                    normalizedAccountId,
                    operationId: writeOperationId,
                    now: writeCreatedAt
                )
                : summary
        }

        let generation = applyLocalMutation(updatedSummaries)
        if await writeJournal.contains(operationId: writeOperationId) {
            rollbackLocalMutationIfNeeded(generation: generation, allSummaries: previousAllSummaries)
            return true
        }
        guard await persist(generation: generation) != nil else { return false }
        await recordWriteOperation(writeOperationId, entityKind: .workout, createdAt: writeCreatedAt)
        return true
    }

    private func loadSummaries() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            allSummaries = []
            summaries = []
            persistedAllSummaries = []
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            applyAllSummaries(try decoder.decode([WorkoutSessionSummary].self, from: data))
            persistedAllSummaries = allSummaries
            persistenceError = nil
        } catch {
            allSummaries = []
            summaries = []
            persistedAllSummaries = []
            persistenceError = "Could not load workout history: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func upsert(_ summary: WorkoutSessionSummary, operationId: UUID? = nil) async -> Bool {
        let writeOperationId = operationId ?? UUID()

        let writeCreatedAt = Date()
        let previousAllSummaries = allSummaries
        var updatedSummaries = allSummaries
        let accountStampedSummary = summary.withAccountId(
            currentAccountId,
            operationId: writeOperationId,
            now: writeCreatedAt
        )
        if let existingIndex = updatedSummaries.firstIndex(where: { $0.id == accountStampedSummary.id }) {
            updatedSummaries[existingIndex] = accountStampedSummary
        } else {
            updatedSummaries.append(accountStampedSummary)
        }

        let generation = applyLocalMutation(updatedSummaries)
        if await writeJournal.contains(operationId: writeOperationId) {
            rollbackLocalMutationIfNeeded(generation: generation, allSummaries: previousAllSummaries)
            return true
        }
        guard await persist(generation: generation) != nil else { return false }
        await recordWriteOperation(writeOperationId, entityKind: .workout, createdAt: writeCreatedAt)
        return true
    }

    private func recordWriteOperation(
        _ operationId: UUID,
        entityKind: WriteEntityKind,
        createdAt: Date
    ) async {
        _ = await writeJournal.record(
            operationId: operationId,
            entityKind: entityKind,
            createdAt: createdAt
        )
    }

    @discardableResult
    private func persist(generation: Int) async -> PersistenceWriteOutcome? {
        do {
            let sortedSummaries = sortedSummaries(allSummaries)
            let data = try await persistenceActor.encode(
                sortedSummaries,
                outputFormatting: [.prettyPrinted, .sortedKeys]
            )
            let outcome = try await persistenceActor.writeLatest(data, to: fileURL, options: [.atomic])
            if outcome == .written {
                persistedAllSummaries = sortedSummaries
            }
            persistenceError = nil
            return outcome
        } catch {
            rollbackLatestMutationIfNeeded(generation: generation)
            persistenceError = "Could not save workout history: \(error.localizedDescription)"
            return nil
        }
    }

    private func applyLocalMutation(_ updatedSummaries: [WorkoutSessionSummary]) -> Int {
        persistenceGeneration += 1
        applyAllSummaries(updatedSummaries)
        return persistenceGeneration
    }

    private func rollbackLatestMutationIfNeeded(generation: Int) {
        guard generation == persistenceGeneration else { return }
        applyAllSummaries(persistedAllSummaries)
    }

    private func rollbackLocalMutationIfNeeded(
        generation: Int,
        allSummaries previousAllSummaries: [WorkoutSessionSummary]
    ) {
        guard generation == persistenceGeneration else { return }
        applyAllSummaries(previousAllSummaries)
    }

    private func applyAllSummaries(_ updatedSummaries: [WorkoutSessionSummary]) {
        allSummaries = sortedSummaries(updatedSummaries)
        summaries = sortedSummaries(allSummaries.filter { !$0.isDeleted && isVisible($0) })
    }

    private func sortedSummaries(
        _ summaries: [WorkoutSessionSummary]
    ) -> [WorkoutSessionSummary] {
        summaries.sorted {
            if $0.authoritativeEndedAt == $1.authoritativeEndedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.authoritativeEndedAt > $1.authoritativeEndedAt
        }
    }

    private func isVisible(_ summary: WorkoutSessionSummary) -> Bool {
        AccountOwnership.isVisible(
            recordAccountId: summary.accountId,
            currentAccountId: currentAccountId
        )
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
            let workoutWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: summary.authoritativeEndedAt)
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
