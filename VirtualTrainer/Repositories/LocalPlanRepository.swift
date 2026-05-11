import Foundation

private struct LocalPlanSnapshot: Codable, Equatable {
    let schemaVersion: Int
    var records: [LocalPlanRecord]

    init(schemaVersion: Int = 1, records: [LocalPlanRecord] = []) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}

private struct LocalPlanRecord: Codable, Equatable {
    let accountId: String
    let plan: WorkoutPlanV2
    var savedAt: Date
    var isActive: Bool
    var syncMetadata: SyncMetadata

    init(
        accountId: String,
        plan: WorkoutPlanV2,
        savedAt: Date,
        isActive: Bool,
        operationId: UUID
    ) {
        self.accountId = accountId
        self.plan = plan
        self.savedAt = savedAt
        self.isActive = isActive
        self.syncMetadata = .initialPendingUpload(operationId: operationId, now: savedAt)
    }
}

@MainActor
final class LocalPlanRepository: PlanRepository {
    private let fileURL: URL
    private let writeJournal: LocalWriteJournal
    private let decoder = JSONDecoder()
    private let persistenceActor: PersistenceActor
    private var snapshot: LocalPlanSnapshot
    private var persistedSnapshot: LocalPlanSnapshot
    private var persistenceGeneration = 0
    private var loadError: String?

    init(
        fileURL: URL? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let resolvedFileURL = fileURL ?? Self.defaultPlanURL()
        self.fileURL = resolvedFileURL
        self.writeJournal = writeJournal ?? LocalWriteJournal(
            fileURL: LocalWriteJournal.defaultJournalURL(alongside: resolvedFileURL),
            persistenceActor: persistenceActor
        )
        self.persistenceActor = persistenceActor
        decoder.dateDecodingStrategy = .iso8601
        let initialSnapshot = Self.loadInitialSnapshot(
            from: resolvedFileURL,
            decoder: decoder
        )
        self.snapshot = initialSnapshot.snapshot
        self.persistedSnapshot = initialSnapshot.snapshot
        self.loadError = initialSnapshot.error
    }

    nonisolated deinit {}

    @discardableResult
    func saveActivePlan(_ plan: WorkoutPlanV2, accountId: String, operationId: UUID) async throws -> WorkoutPlanV2 {
        if let loadError {
            throw RepositoryError.invalidPayload(loadError)
        }
        let normalizedAccountId = try normalizedPlanAccountId(accountId)
        let previousSnapshot = snapshot
        let savedAt = Date()
        snapshot.records = snapshot.records.map { record in
            guard record.accountId == normalizedAccountId else { return record }
            var updatedRecord = record
            updatedRecord.isActive = false
            return updatedRecord
        }
        snapshot.records.removeAll {
            $0.accountId == normalizedAccountId && $0.plan.id == plan.id
        }
        snapshot.records.append(
            LocalPlanRecord(
                accountId: normalizedAccountId,
                plan: plan,
                savedAt: savedAt,
                isActive: true,
                operationId: operationId
            )
        )
        snapshot.records = sorted(snapshot.records)
        let generation = nextPersistenceGeneration()

        if await writeJournal.contains(operationId: operationId) {
            rollbackIfNeeded(generation: generation, to: previousSnapshot)
            return try await loadActivePlan(accountId: normalizedAccountId) ?? plan
        }

        try await persist(generation: generation)
        _ = await writeJournal.record(
            operationId: operationId,
            entityKind: .plan,
            createdAt: savedAt
        )
        return try await loadActivePlan(accountId: normalizedAccountId) ?? plan
    }

    func loadActivePlan(accountId: String) async throws -> WorkoutPlanV2? {
        if let loadError {
            throw RepositoryError.invalidPayload(loadError)
        }
        let normalizedAccountId = try normalizedPlanAccountId(accountId)
        return snapshot.records
            .filter { $0.accountId == normalizedAccountId && $0.isActive }
            .sorted { $0.savedAt > $1.savedAt }
            .first?
            .plan
    }

    func loadPlanHistory(accountId: String, limit: Int) async throws -> [WorkoutPlanV2] {
        if let loadError {
            throw RepositoryError.invalidPayload(loadError)
        }
        let normalizedAccountId = try normalizedPlanAccountId(accountId)
        return Array(
            sorted(snapshot.records)
                .filter { $0.accountId == normalizedAccountId }
                .prefix(max(limit, 0))
                .map(\.plan)
        )
    }

    private func persist(generation: Int) async throws {
        do {
            let snapshotToPersist = snapshot
            let data = try await persistenceActor.encode(
                snapshotToPersist,
                outputFormatting: [.prettyPrinted, .sortedKeys]
            )
            let outcome = try await persistenceActor.writeLatest(data, to: fileURL, options: [.atomic])
            if outcome == .written {
                persistedSnapshot = snapshotToPersist
            }
        } catch {
            rollbackIfNeeded(generation: generation, to: persistedSnapshot)
            throw RepositoryError.invalidPayload("Could not save local plans: \(error.localizedDescription)")
        }
    }

    private func nextPersistenceGeneration() -> Int {
        persistenceGeneration += 1
        return persistenceGeneration
    }

    private func rollbackIfNeeded(generation: Int, to previousSnapshot: LocalPlanSnapshot) {
        guard generation == persistenceGeneration else { return }
        snapshot = previousSnapshot
    }

    private func sorted(_ records: [LocalPlanRecord]) -> [LocalPlanRecord] {
        records.sorted {
            if $0.accountId != $1.accountId {
                return $0.accountId < $1.accountId
            }
            if $0.savedAt != $1.savedAt {
                return $0.savedAt > $1.savedAt
            }
            if $0.isActive != $1.isActive {
                return $0.isActive
            }
            return $0.plan.id.uuidString < $1.plan.id.uuidString
        }
    }

    private func normalizedPlanAccountId(_ accountId: String) throws -> String {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            throw RepositoryError.accountMissing
        }
        return normalizedAccountId
    }

    private static func defaultPlanURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("WorkoutPlans.json")
    }

    private static func loadInitialSnapshot(
        from fileURL: URL,
        decoder: JSONDecoder
    ) -> (snapshot: LocalPlanSnapshot, error: String?) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return (LocalPlanSnapshot(), nil)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decodedSnapshot = try decoder.decode(LocalPlanSnapshot.self, from: data)
            return (
                LocalPlanSnapshot(schemaVersion: decodedSnapshot.schemaVersion, records: decodedSnapshot.records.sorted {
                    if $0.accountId != $1.accountId {
                        return $0.accountId < $1.accountId
                    }
                    if $0.savedAt != $1.savedAt {
                        return $0.savedAt > $1.savedAt
                    }
                    if $0.isActive != $1.isActive {
                        return $0.isActive
                    }
                    return $0.plan.id.uuidString < $1.plan.id.uuidString
                }),
                nil
            )
        } catch {
            return (
                LocalPlanSnapshot(),
                "Could not load local plans: \(error.localizedDescription)"
            )
        }
    }
}
