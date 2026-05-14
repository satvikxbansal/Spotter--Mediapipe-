import Foundation

@MainActor
final class LocalProfileRepository: ProfileRepository {
    private let store: OnboardingStore
    private let defaultAccountId: String?
    private var profileContinuations: [UUID: AsyncStream<UserProfile?>.Continuation] = [:]

    init(
        fileURL: URL? = nil,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.defaultAccountId = normalizedAccountId
        self.store = OnboardingStore(
            fileURL: fileURL,
            accountId: normalizedAccountId,
            writeJournal: writeJournal,
            persistenceActor: persistenceActor
        )
    }

    func loadProfile(accountId: String) async throws -> UserProfile? {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return store.profile
    }

    @discardableResult
    func saveProfile(_ profile: UserProfile, operationId: UUID) async throws -> UserProfile {
        store.setCurrentAccountId(profile.accountId ?? defaultAccountId)
        guard await store.saveProfile(profile, operationId: operationId) else {
            throw localSaveError(store.persistenceError, fallback: "Could not save local profile.")
        }
        notifyProfileObservers()
        return store.profile ?? profile
    }

    func observeProfile(accountId: String) async throws -> AsyncStream<UserProfile?> {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return AsyncStream { continuation in
            let id = UUID()
            profileContinuations[id] = continuation
            continuation.yield(store.profile)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.profileContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func notifyProfileObservers() {
        profileContinuations.values.forEach {
            $0.yield(store.profile)
        }
    }
}

@MainActor
final class LocalWorkoutRepository: WorkoutRepository {
    private let store: WorkoutHistoryStore
    private let defaultAccountId: String?
    private var workoutContinuations: [UUID: WorkoutObserver] = [:]

    private struct WorkoutObserver {
        let accountId: String
        let limit: Int
        let continuation: AsyncStream<[WorkoutSessionSummary]>.Continuation
    }

    init(
        fileURL: URL? = nil,
        calendar: Calendar = .current,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.defaultAccountId = normalizedAccountId
        self.store = WorkoutHistoryStore(
            fileURL: fileURL,
            calendar: calendar,
            accountId: normalizedAccountId,
            writeJournal: writeJournal,
            persistenceActor: persistenceActor
        )
    }

    @discardableResult
    func saveWorkoutSummary(_ summary: WorkoutSessionSummary, operationId: UUID) async throws -> WorkoutSessionSummary {
        store.setCurrentAccountId(summary.accountId ?? defaultAccountId)
        guard await store.addSummary(summary, operationId: operationId) else {
            throw localSaveError(store.persistenceError, fallback: "Could not save local workout summary.")
        }
        notifyWorkoutObservers()
        return store.fetchSummaryIncludingDeleted(id: summary.id) ?? summary
    }

    func loadRecentWorkouts(
        accountId: String,
        limit: Int,
        since: Date?
    ) async throws -> [WorkoutSessionSummary] {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        let visibleSummaries = store.fetchRecentSummaries(limit: Int.max)
        let filteredSummaries = visibleSummaries.filter { summary in
            guard let since else { return true }
            return summary.authoritativeEndedAt >= since
        }
        return Array(filteredSummaries.prefix(max(limit, 0)))
    }

    func loadWorkout(accountId: String, id: UUID) async throws -> WorkoutSessionSummary? {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return store.fetchSummary(id: id)
    }

    func deleteWorkout(accountId: String, id: UUID, operationId: UUID) async throws {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        guard await store.deleteSummary(id: id, operationId: operationId) else {
            throw RepositoryError.notFound
        }
        notifyWorkoutObservers()
    }

    func observeRecentWorkouts(accountId: String, limit: Int) async throws -> AsyncStream<[WorkoutSessionSummary]> {
        let normalizedAccountId = try normalizedRequiredAccountId(accountId)
        store.setCurrentAccountId(normalizedAccountId)
        return AsyncStream { continuation in
            let id = UUID()
            workoutContinuations[id] = WorkoutObserver(
                accountId: normalizedAccountId,
                limit: limit,
                continuation: continuation
            )
            continuation.yield(recentWorkouts(accountId: normalizedAccountId, limit: limit))
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.workoutContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func notifyWorkoutObservers() {
        workoutContinuations.values.forEach { observer in
            observer.continuation.yield(
                recentWorkouts(accountId: observer.accountId, limit: observer.limit)
            )
        }
    }

    private func recentWorkouts(accountId: String, limit: Int) -> [WorkoutSessionSummary] {
        store.setCurrentAccountId(accountId)
        return Array(store.fetchRecentSummaries(limit: Int.max).prefix(max(limit, 0)))
    }
}

@MainActor
final class LocalTrophyRepository: TrophyRepository {
    private let store: TrophyStore
    private let defaultAccountId: String?
    private var trophyContinuations: [UUID: TrophyObserver] = [:]

    private struct TrophyObserver {
        let accountId: String
        let continuation: AsyncStream<[TrophyUnlockEvent]>.Continuation
    }

    init(
        fileURL: URL? = nil,
        calendar: Calendar = .current,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.defaultAccountId = normalizedAccountId
        self.store = TrophyStore(
            fileURL: fileURL,
            calendar: calendar,
            accountId: normalizedAccountId,
            writeJournal: writeJournal,
            persistenceActor: persistenceActor
        )
    }

    func loadTrophyDefinitions() async throws -> [TrophyDefinition] {
        TrophyDefinitionCatalog.all
    }

    func loadTrophyEvents(accountId: String, since: Date?) async throws -> [TrophyUnlockEvent] {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return store.allUnlockEvents().filter { event in
            guard let since else { return true }
            return event.authoritativeEarnedAt >= since
        }
    }

    @discardableResult
    func saveTrophyEvent(_ event: TrophyUnlockEvent, operationId: UUID) async throws -> TrophyUnlockEvent {
        store.setCurrentAccountId(event.accountId ?? defaultAccountId)
        guard await store.saveUnlockEvent(event, operationId: operationId) else {
            throw localSaveError(store.persistenceError, fallback: "Could not save local trophy event.")
        }
        notifyTrophyObservers()
        return store.allUnlockEvents().first { $0.id == event.id } ?? event
    }

    func loadTrophyProgress(accountId: String) async throws -> [TrophyProgress] {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return store.snapshot.progress
    }

    func observeTrophyEvents(accountId: String) async throws -> AsyncStream<[TrophyUnlockEvent]> {
        let normalizedAccountId = try normalizedRequiredAccountId(accountId)
        store.setCurrentAccountId(normalizedAccountId)
        return AsyncStream { continuation in
            let id = UUID()
            trophyContinuations[id] = TrophyObserver(
                accountId: normalizedAccountId,
                continuation: continuation
            )
            continuation.yield(trophyEvents(accountId: normalizedAccountId))
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.trophyContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func notifyTrophyObservers() {
        trophyContinuations.values.forEach { observer in
            observer.continuation.yield(trophyEvents(accountId: observer.accountId))
        }
    }

    private func trophyEvents(accountId: String) -> [TrophyUnlockEvent] {
        store.setCurrentAccountId(accountId)
        return store.allUnlockEvents()
    }
}

@MainActor
final class LocalInsightRepository: InsightRepository {
    private let store: InsightStore
    private let defaultAccountId: String?

    init(
        fileURL: URL? = nil,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.defaultAccountId = normalizedAccountId
        self.store = InsightStore(
            fileURL: fileURL,
            accountId: normalizedAccountId,
            writeJournal: writeJournal,
            persistenceActor: persistenceActor
        )
    }

    @discardableResult
    func saveInsights(_ insights: [AIInsight], operationId: UUID) async throws -> [AIInsight] {
        store.setCurrentAccountId(firstAccountId(in: insights) ?? defaultAccountId)
        guard await store.saveInsights(insights, operationId: operationId) else {
            throw localSaveError(store.persistenceError, fallback: "Could not save local insights.")
        }
        let savedDedupeKeys = Set(insights.map(\.dedupeKey))
        return store.recentInsights.filter { savedDedupeKeys.contains($0.dedupeKey) }
    }

    func loadRecentInsights(accountId: String, limit: Int) async throws -> [AIInsight] {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return Array(store.recentInsights.filter { !$0.isDeleted }.prefix(max(limit, 0)))
    }

    @discardableResult
    func saveDeliveryRecord(_ record: InsightDeliveryRecord, operationId: UUID) async throws -> InsightDeliveryRecord {
        store.setCurrentAccountId(record.accountId ?? defaultAccountId)
        guard await store.saveDeliveryRecord(record, operationId: operationId) else {
            throw localSaveError(store.persistenceError, fallback: "Could not save local insight delivery record.")
        }
        return store
            .allDeliveryRecordsIncludingTombstones()
            .first { $0.dedupeKey == record.dedupeKey } ?? record
    }

    func loadDeliveryRecords(accountId: String) async throws -> [InsightDeliveryRecord] {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return store.allDeliveryRecordsIncludingTombstones()
    }

    @discardableResult
    func saveEngagementRecord(_ record: InsightEngagementRecord, operationId: UUID) async throws -> InsightEngagementRecord {
        store.setCurrentAccountId(record.accountId ?? defaultAccountId)
        guard await store.saveEngagementRecord(record, operationId: operationId) else {
            throw localSaveError(store.persistenceError, fallback: "Could not save local insight engagement record.")
        }
        return store
            .allEngagementRecordsIncludingTombstones()
            .first { $0.dedupeKey == record.dedupeKey } ?? record
    }

    func loadEngagementRecords(accountId: String) async throws -> [InsightEngagementRecord] {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return store.allEngagementRecordsIncludingTombstones()
    }

    func invalidateInsight(accountId: String, dedupeKey: String, operationId: UUID) async throws {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        guard await store.invalidateInsight(dedupeKey: dedupeKey, operationId: operationId) else {
            throw RepositoryError.notFound
        }
    }

    private func firstAccountId(in insights: [AIInsight]) -> String? {
        insights.lazy.compactMap(\.accountId).first
    }
}

@MainActor
final class LocalThemeRepository: ThemeRepository {
    private let store: ThemeStore
    private var themeContinuations: [UUID: AsyncStream<SpotterThemeOption>.Continuation] = [:]

    init(
        fileURL: URL? = nil,
        defaultTheme: SpotterThemeOption = .hyper,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        self.store = ThemeStore(
            fileURL: fileURL,
            defaultTheme: defaultTheme,
            accountId: AccountOwnership.normalizedAccountId(accountId),
            writeJournal: writeJournal,
            persistenceActor: persistenceActor
        )
    }

    func loadTheme(accountId: String) async throws -> SpotterThemeOption {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return store.selectedTheme
    }

    func saveTheme(_ theme: SpotterThemeOption, accountId: String, operationId: UUID) async throws {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        guard await store.updateSelectedTheme(theme, operationId: operationId) else {
            throw localSaveError(store.persistenceError, fallback: "Could not save local theme.")
        }
        notifyThemeObservers()
    }

    func observeTheme(accountId: String) async throws -> AsyncStream<SpotterThemeOption> {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return AsyncStream { continuation in
            let id = UUID()
            themeContinuations[id] = continuation
            continuation.yield(store.selectedTheme)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.themeContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func notifyThemeObservers() {
        themeContinuations.values.forEach {
            $0.yield(store.selectedTheme)
        }
    }
}

@MainActor
final class LocalCalibrationRepository: CalibrationRepository {
    private let store: CalibrationStore
    private let defaultAccountId: String?
    private var calibrationContinuations: [UUID: AsyncStream<CalibrationRecord?>.Continuation] = [:]

    init(
        fileURL: URL? = nil,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.defaultAccountId = normalizedAccountId
        self.store = CalibrationStore(
            fileURL: fileURL,
            accountId: normalizedAccountId,
            writeJournal: writeJournal,
            persistenceActor: persistenceActor
        )
    }

    func loadCalibrationRecord(accountId: String) async throws -> CalibrationRecord? {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return store.record
    }

    @discardableResult
    func saveCalibrationRecord(_ record: CalibrationRecord, operationId: UUID) async throws -> CalibrationRecord {
        store.setCurrentAccountId(record.accountId ?? defaultAccountId)
        guard await store.saveCalibrationRecord(record, operationId: operationId) else {
            throw localSaveError(store.persistenceError, fallback: "Could not save local calibration record.")
        }
        notifyCalibrationObservers()
        return store.record ?? record
    }

    func observeCalibrationRecord(accountId: String) async throws -> AsyncStream<CalibrationRecord?> {
        store.setCurrentAccountId(try normalizedRequiredAccountId(accountId))
        return AsyncStream { continuation in
            let id = UUID()
            calibrationContinuations[id] = continuation
            continuation.yield(store.record)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.calibrationContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func notifyCalibrationObservers() {
        calibrationContinuations.values.forEach {
            $0.yield(store.record)
        }
    }
}

@MainActor
private func normalizedRequiredAccountId(_ accountId: String) throws -> String {
    guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
        throw RepositoryError.accountMissing
    }
    return normalizedAccountId
}

@MainActor
private func localSaveError(_ message: String?, fallback: String) -> RepositoryError {
    .invalidPayload(message ?? fallback)
}
