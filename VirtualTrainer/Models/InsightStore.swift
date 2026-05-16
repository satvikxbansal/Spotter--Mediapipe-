import Foundation
import Combine

nonisolated private func maxOptionalDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    switch (lhs, rhs) {
    case let (lhs?, rhs?):
        return max(lhs, rhs)
    case let (lhs?, nil):
        return lhs
    case let (nil, rhs?):
        return rhs
    case (nil, nil):
        return nil
    }
}

// SYNC SEMANTICS:
// Delivery and engagement records are account-scoped, per-dedupeKey behavior
// records that should be server-mirrored once repositories exist. They carry
// only privacy-light insight behavior data: dedupe keys, presentation surfaces,
// engagement kinds/counts, event dates, tombstones, and sync metadata. They must
// never contain raw workout data, camera frames, video, face images, raw pose
// streams, raw biometric face data, or raw pose timelines.
//
// Delivery conflicts preserve the earliest firstPresentedAt, latest
// lastPresentedAt, and latest date per surface. presentationCount uses max
// instead of sum because delivery records are aggregates, not per-impression
// event logs; max keeps remote re-apply idempotent and avoids overstating how
// often an insight was shown. Engagement conflicts sum counts and keep the max
// last-engagement date per kind. Unresolved repository version conflicts must
// stay .conflict.
nonisolated struct InsightDeliveryRecord: Codable, Equatable {
    let accountId: String?
    let dedupeKey: String
    var firstPresentedAt: Date
    var lastPresentedAt: Date
    var presentationCount: Int
    var surfaceLastPresentedAt: [String: Date]
    var deletedAt: Date?
    var syncMetadata: SyncMetadata

    init(
        accountId: String? = nil,
        dedupeKey: String,
        presentedAt: Date,
        surface: InsightSurface,
        deletedAt: Date? = nil,
        syncMetadata: SyncMetadata? = nil
    ) {
        self.init(
            accountId: accountId,
            dedupeKey: dedupeKey,
            firstPresentedAt: presentedAt,
            lastPresentedAt: presentedAt,
            presentationCount: 1,
            surfaceLastPresentedAt: [surface.rawValue: presentedAt],
            deletedAt: deletedAt,
            syncMetadata: syncMetadata
        )
    }

    init(
        accountId: String? = nil,
        dedupeKey: String,
        firstPresentedAt: Date,
        lastPresentedAt: Date,
        presentationCount: Int,
        surfaceLastPresentedAt: [String: Date],
        deletedAt: Date? = nil,
        syncMetadata: SyncMetadata? = nil
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.accountId = normalizedAccountId
        self.dedupeKey = dedupeKey
        self.firstPresentedAt = firstPresentedAt
        self.lastPresentedAt = lastPresentedAt
        self.presentationCount = max(presentationCount, 0)
        self.surfaceLastPresentedAt = surfaceLastPresentedAt
        self.deletedAt = deletedAt
        let metadataDate = maxOptionalDate(deletedAt, lastPresentedAt) ?? lastPresentedAt
        self.syncMetadata = syncMetadata ?? (
            normalizedAccountId == nil
                ? .initialLocalOnly(now: metadataDate)
                : .initialPendingUpload(operationId: nil, now: metadataDate)
        )
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    mutating func recordPresentation(
        at date: Date,
        surface: InsightSurface,
        operationId: UUID? = nil
    ) {
        firstPresentedAt = min(firstPresentedAt, date)
        lastPresentedAt = max(lastPresentedAt, date)
        presentationCount = max(presentationCount, 0) + 1
        if let existingDate = surfaceLastPresentedAt[surface.rawValue] {
            surfaceLastPresentedAt[surface.rawValue] = max(existingDate, date)
        } else {
            surfaceLastPresentedAt[surface.rawValue] = date
        }
        deletedAt = nil
        syncMetadata.markLocalMutation(
            accountId: accountId,
            operationId: operationId,
            now: date
        )
    }

    func markedDeleted(at date: Date, operationId: UUID? = nil) -> InsightDeliveryRecord {
        var copy = self
        copy.deletedAt = date
        copy.syncMetadata.markLocalMutation(
            accountId: accountId,
            operationId: operationId,
            now: date
        )
        return copy
    }

    func restored(operationId: UUID? = nil, now: Date = Date()) -> InsightDeliveryRecord {
        var copy = self
        copy.deletedAt = nil
        copy.syncMetadata.markLocalMutation(
            accountId: accountId,
            operationId: operationId,
            now: now
        )
        return copy
    }

    func withAccountId(
        _ accountId: String?,
        operationId: UUID? = nil,
        now: Date = Date()
    ) -> InsightDeliveryRecord {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        return InsightDeliveryRecord(
            accountId: normalizedAccountId,
            dedupeKey: dedupeKey,
            firstPresentedAt: firstPresentedAt,
            lastPresentedAt: lastPresentedAt,
            presentationCount: presentationCount,
            surfaceLastPresentedAt: surfaceLastPresentedAt,
            deletedAt: deletedAt,
            syncMetadata: syncMetadata.markedForLocalMutation(
                accountId: normalizedAccountId,
                operationId: operationId,
                now: now
            )
        )
    }

    static func merged(
        local: InsightDeliveryRecord,
        remote: InsightDeliveryRecord
    ) -> InsightDeliveryRecord {
        var mergedSurfaces = local.surfaceLastPresentedAt
        for (surface, date) in remote.surfaceLastPresentedAt {
            if let existingDate = mergedSurfaces[surface] {
                mergedSurfaces[surface] = max(existingDate, date)
            } else {
                mergedSurfaces[surface] = date
            }
        }

        return InsightDeliveryRecord(
            accountId: remote.accountId ?? local.accountId,
            dedupeKey: local.dedupeKey,
            firstPresentedAt: min(local.firstPresentedAt, remote.firstPresentedAt),
            lastPresentedAt: max(local.lastPresentedAt, remote.lastPresentedAt),
            presentationCount: max(max(local.presentationCount, remote.presentationCount), 0),
            surfaceLastPresentedAt: mergedSurfaces,
            deletedAt: maxOptionalDate(local.deletedAt, remote.deletedAt),
            syncMetadata: SyncMetadata.preferredForMerge(local.syncMetadata, remote.syncMetadata)
        )
    }
}

nonisolated extension InsightDeliveryRecord {
    private enum CodingKeys: String, CodingKey {
        case accountId
        case dedupeKey
        case firstPresentedAt
        case lastPresentedAt
        case presentationCount
        case surfaceLastPresentedAt
        case deletedAt
        case syncMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedAccountId = AccountOwnership.normalizedAccountId(
            try container.decodeIfPresent(String.self, forKey: .accountId)
        )
        let dedupeKey = try container.decode(String.self, forKey: .dedupeKey)
        let firstPresentedAt = try container.decode(Date.self, forKey: .firstPresentedAt)
        let lastPresentedAt = try container.decode(Date.self, forKey: .lastPresentedAt)
        let deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        self.init(
            accountId: decodedAccountId,
            dedupeKey: dedupeKey,
            firstPresentedAt: firstPresentedAt,
            lastPresentedAt: lastPresentedAt,
            presentationCount: try container.decode(Int.self, forKey: .presentationCount),
            surfaceLastPresentedAt: try container.decode([String: Date].self, forKey: .surfaceLastPresentedAt),
            deletedAt: deletedAt,
            syncMetadata: try container.decodeIfPresent(SyncMetadata.self, forKey: .syncMetadata)
                ?? .initialLocalOnly(now: maxOptionalDate(deletedAt, lastPresentedAt) ?? lastPresentedAt)
        )
    }
}

nonisolated enum InsightEngagementKind: String, Codable, CaseIterable, Hashable {
    case opened
    case dismissed
    case helpful
    case notHelpful
}

nonisolated struct InsightEngagementRecord: Codable, Equatable {
    let accountId: String?
    let dedupeKey: String
    private var engagementCounts: [String: Int]
    private var lastEngagementDates: [String: Date]
    var deletedAt: Date?
    var syncMetadata: SyncMetadata

    init(
        accountId: String? = nil,
        dedupeKey: String,
        engagementCounts: [String: Int] = [:],
        lastEngagementDates: [String: Date] = [:],
        deletedAt: Date? = nil,
        syncMetadata: SyncMetadata? = nil
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.accountId = normalizedAccountId
        self.dedupeKey = dedupeKey
        self.engagementCounts = engagementCounts
        self.lastEngagementDates = lastEngagementDates
        self.deletedAt = deletedAt
        let localUpdatedAt = maxOptionalDate(lastEngagementDates.values.max(), deletedAt) ?? Date()
        self.syncMetadata = syncMetadata ?? (
            normalizedAccountId == nil
                ? .initialLocalOnly(now: localUpdatedAt)
                : .initialPendingUpload(operationId: nil, now: localUpdatedAt)
        )
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    mutating func record(
        _ kind: InsightEngagementKind,
        at date: Date,
        operationId: UUID? = nil
    ) {
        engagementCounts[kind.rawValue, default: 0] += 1
        lastEngagementDates[kind.rawValue] = date
        deletedAt = nil
        syncMetadata.markLocalMutation(
            accountId: accountId,
            operationId: operationId,
            now: date
        )
    }

    func count(for kind: InsightEngagementKind) -> Int {
        engagementCounts[kind.rawValue] ?? 0
    }

    func lastEngagedAt(for kind: InsightEngagementKind) -> Date? {
        lastEngagementDates[kind.rawValue]
    }

    func latestEngagedAt() -> Date? {
        lastEngagementDates.values.max()
    }

    func merged(with other: InsightEngagementRecord) -> InsightEngagementRecord {
        var mergedCounts = engagementCounts
        for (kind, count) in other.engagementCounts {
            mergedCounts[kind, default: 0] += count
        }
        var mergedDates = lastEngagementDates
        for (kind, date) in other.lastEngagementDates {
            if let existingDate = mergedDates[kind] {
                mergedDates[kind] = max(existingDate, date)
            } else {
                mergedDates[kind] = date
            }
        }

        return InsightEngagementRecord(
            accountId: other.accountId ?? accountId,
            dedupeKey: dedupeKey,
            engagementCounts: mergedCounts,
            lastEngagementDates: mergedDates,
            deletedAt: maxOptionalDate(deletedAt, other.deletedAt),
            syncMetadata: SyncMetadata.preferredForMerge(syncMetadata, other.syncMetadata)
        )
    }

    func mergedAggregateSnapshot(with other: InsightEngagementRecord) -> InsightEngagementRecord {
        var mergedCounts = engagementCounts
        for (kind, count) in other.engagementCounts {
            mergedCounts[kind] = max(mergedCounts[kind] ?? 0, count)
        }
        var mergedDates = lastEngagementDates
        for (kind, date) in other.lastEngagementDates {
            if let existingDate = mergedDates[kind] {
                mergedDates[kind] = max(existingDate, date)
            } else {
                mergedDates[kind] = date
            }
        }

        return InsightEngagementRecord(
            accountId: other.accountId ?? accountId,
            dedupeKey: dedupeKey,
            engagementCounts: mergedCounts,
            lastEngagementDates: mergedDates,
            deletedAt: maxOptionalDate(deletedAt, other.deletedAt),
            syncMetadata: SyncMetadata.preferredForMerge(syncMetadata, other.syncMetadata)
        )
    }

    func markedDeleted(at date: Date, operationId: UUID? = nil) -> InsightEngagementRecord {
        var copy = self
        copy.deletedAt = date
        copy.syncMetadata.markLocalMutation(
            accountId: accountId,
            operationId: operationId,
            now: date
        )
        return copy
    }

    func restored(operationId: UUID? = nil, now: Date = Date()) -> InsightEngagementRecord {
        var copy = self
        copy.deletedAt = nil
        copy.syncMetadata.markLocalMutation(
            accountId: accountId,
            operationId: operationId,
            now: now
        )
        return copy
    }

    func withAccountId(
        _ accountId: String?,
        operationId: UUID? = nil,
        now: Date = Date()
    ) -> InsightEngagementRecord {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        return InsightEngagementRecord(
            accountId: normalizedAccountId,
            dedupeKey: dedupeKey,
            engagementCounts: engagementCounts,
            lastEngagementDates: lastEngagementDates,
            deletedAt: deletedAt,
            syncMetadata: syncMetadata.markedForLocalMutation(
                accountId: normalizedAccountId,
                operationId: operationId,
                now: now
            )
        )
    }
}

nonisolated extension InsightEngagementRecord {
    private enum CodingKeys: String, CodingKey {
        case accountId
        case dedupeKey
        case engagementCounts
        case lastEngagementDates
        case deletedAt
        case syncMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedDates = try container.decode([String: Date].self, forKey: .lastEngagementDates)
        let deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        let localUpdatedAt = maxOptionalDate(decodedDates.values.max(), deletedAt) ?? Date()

        self.init(
            accountId: try container.decodeIfPresent(String.self, forKey: .accountId),
            dedupeKey: try container.decode(String.self, forKey: .dedupeKey),
            engagementCounts: try container.decode([String: Int].self, forKey: .engagementCounts),
            lastEngagementDates: decodedDates,
            deletedAt: deletedAt,
            syncMetadata: try container.decodeIfPresent(SyncMetadata.self, forKey: .syncMetadata)
                ?? .initialLocalOnly(now: localUpdatedAt)
        )
    }
}

nonisolated struct PersistedInsightStoreSnapshot: Codable, Equatable {
    let sourcePolicyVersion: String
    let savedAt: Date
    let recentInsights: [AIInsight]
    let deliveryRecords: [InsightDeliveryRecord]
    let engagementRecords: [InsightEngagementRecord]

    init(
        sourcePolicyVersion: String,
        savedAt: Date,
        recentInsights: [AIInsight],
        deliveryRecords: [InsightDeliveryRecord],
        engagementRecords: [InsightEngagementRecord] = []
    ) {
        self.sourcePolicyVersion = sourcePolicyVersion
        self.savedAt = savedAt
        self.recentInsights = recentInsights
        self.deliveryRecords = deliveryRecords
        self.engagementRecords = engagementRecords
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePolicyVersion
        case savedAt
        case recentInsights
        case deliveryRecords
        case engagementRecords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePolicyVersion = try container.decode(String.self, forKey: .sourcePolicyVersion)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        recentInsights = try container.decode([AIInsight].self, forKey: .recentInsights)
        deliveryRecords = try container.decode([InsightDeliveryRecord].self, forKey: .deliveryRecords)
        engagementRecords = try container.decodeIfPresent([InsightEngagementRecord].self, forKey: .engagementRecords) ?? []
    }
}

@MainActor
final class InsightStore: ObservableObject {
    @Published private(set) var recentInsights: [AIInsight] = []
    @Published var persistenceError: String?

    private let fileURL: URL
    private let writeJournal: LocalWriteJournal
    private var currentAccountId: String?
    private var allInsights: [AIInsight] = []
    private var allDeliveryRecords: [String: InsightDeliveryRecord] = [:]
    private var allEngagementRecords: [String: InsightEngagementRecord] = [:]
    private var deliveryRecords: [String: InsightDeliveryRecord] = [:]
    private var engagementRecords: [String: InsightEngagementRecord] = [:]
    private let ranker = InsightRanker()
    private let decoder = JSONDecoder()
    private let persistenceActor: PersistenceActor
    private var backendMode: BackendMode = .local
    private var insightRepository: (any InsightRepository)?
    private var insightObservationTask: Task<Void, Never>?
    private var deliveryObservationTask: Task<Void, Never>?
    private var engagementObservationTask: Task<Void, Never>?
    private var autoObserveRemote = true

    init(
        fileURL: URL? = nil,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let resolvedFileURL = fileURL ?? Self.defaultInsightURL()
        self.fileURL = resolvedFileURL
        self.writeJournal = writeJournal ?? LocalWriteJournal(
            fileURL: LocalWriteJournal.defaultJournalURL(alongside: resolvedFileURL),
            persistenceActor: persistenceActor
        )
        self.persistenceActor = persistenceActor
        self.currentAccountId = AccountOwnership.normalizedAccountId(accountId)
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    nonisolated deinit {}

    func setCurrentAccountId(_ accountId: String?) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        guard currentAccountId != normalizedAccountId else { return }
        currentAccountId = normalizedAccountId
        applyVisibleState()
        restartInsightObservationIfNeeded()
    }

    func configureRemoteSync(
        backendMode: BackendMode,
        insightRepository: (any InsightRepository)?,
        autoObserve: Bool = true
    ) {
        self.backendMode = backendMode
        self.insightRepository = backendMode == .firebase ? insightRepository : nil
        self.autoObserveRemote = autoObserve
        restartInsightObservationIfNeeded()
    }

    @discardableResult
    func selectInsights(
        _ generatedInsights: [AIInsight],
        for surface: InsightSurface,
        profile: UserProfile,
        limit: Int,
        now: Date = Date(),
        operationId: UUID? = nil
    ) async -> [AIInsight] {
        let writeOperationId = operationId ?? UUID()
        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords
        ingest(generatedInsights, now: now, operationId: writeOperationId)
        expireStale(now: now)

        if await writeJournal.contains(operationId: writeOperationId) {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return Array(fetchCandidates(for: surface, profile: profile, now: now).prefix(max(limit, 0)))
        }

        let candidates = fetchCandidates(for: surface, profile: profile, now: now)
        let selected = Array(candidates.prefix(max(limit, 0)))
        guard await persist() != nil else {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return []
        }
        await saveInsightsRemotelyIfNeeded(generatedInsights, operationId: writeOperationId)
        await recordWriteOperation(writeOperationId, entityKind: .insight, createdAt: now)
        return selected
    }

    @discardableResult
    func selectGeneratedInsights(
        _ generatedInsights: [AIInsight],
        for surface: InsightSurface,
        profile: UserProfile,
        limit: Int,
        now: Date = Date(),
        operationId: UUID? = nil
    ) async -> [AIInsight] {
        let writeOperationId = operationId ?? UUID()
        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords
        ingest(generatedInsights, now: now, operationId: writeOperationId)
        expireStale(now: now)

        let generatedDedupeKeys = Set(
            generatedInsights
                .filter { !$0.isDeleted && !$0.isExpired(now: now) && !$0.evidence.isEmpty && $0.surfaces.contains(surface) }
                .map(\.dedupeKey)
        )
        if await writeJournal.contains(operationId: writeOperationId) {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return Array(
                fetchCandidates(for: surface, profile: profile, now: now)
                    .filter { generatedDedupeKeys.contains($0.dedupeKey) }
                    .prefix(max(limit, 0))
            )
        }

        let candidates = fetchCandidates(for: surface, profile: profile, now: now)
            .filter { generatedDedupeKeys.contains($0.dedupeKey) }
        let selected = Array(candidates.prefix(max(limit, 0)))
        guard await persist() != nil else {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return []
        }
        await saveInsightsRemotelyIfNeeded(generatedInsights, operationId: writeOperationId)
        await recordWriteOperation(writeOperationId, entityKind: .insight, createdAt: now)
        return selected
    }

    func insights(
        for surface: InsightSurface,
        profile: UserProfile,
        limit: Int,
        now: Date = Date()
    ) -> [AIInsight] {
        Array(
            recentInsights
                .filter { !$0.isDeleted && !$0.isExpired(now: now) && $0.surfaces.contains(surface) }
                .sorted {
                    let leftScore = ranker.score(
                        $0,
                        surface: surface,
                        profile: profile,
                        engagementRecords: engagementRecords,
                        now: now
                    )
                    let rightScore = ranker.score(
                        $1,
                        surface: surface,
                        profile: profile,
                        engagementRecords: engagementRecords,
                        now: now
                    )
                    if leftScore == rightScore {
                        return $0.createdAt > $1.createdAt
                    }
                    return leftScore > rightScore
                }
                .prefix(max(limit, 0))
        )
    }

    func deliveryRecord(for dedupeKey: String) -> InsightDeliveryRecord? {
        deliveryRecords[dedupeKey]
    }

    func engagementRecord(for dedupeKey: String) -> InsightEngagementRecord? {
        engagementRecords[dedupeKey]
    }

    func engagementRecordsSnapshot() -> [String: InsightEngagementRecord] {
        engagementRecords
    }

    func allDeliveryRecordsIncludingTombstones() -> [InsightDeliveryRecord] {
        sortedDeliveryRecords(allDeliveryRecords.values.filter(isVisible))
    }

    func allEngagementRecordsIncludingTombstones() -> [InsightEngagementRecord] {
        sortedEngagementRecords(allEngagementRecords.values.filter(isVisible))
    }

    var pendingUploadCount: Int {
        allInsights.filter { isVisible($0) && $0.syncMetadata.syncState == .pendingUpload }.count +
            allDeliveryRecords.values.filter { isVisible($0) && $0.syncMetadata.syncState == .pendingUpload }.count +
            allEngagementRecords.values.filter { isVisible($0) && $0.syncMetadata.syncState == .pendingUpload }.count
    }

    func pendingInsightsForSync() -> [AIInsight] {
        allInsights.filter { isVisible($0) && $0.syncMetadata.syncState == .pendingUpload }
    }

    func pendingDeliveryRecordsForSync() -> [InsightDeliveryRecord] {
        sortedDeliveryRecords(
            allDeliveryRecords.values.filter { isVisible($0) && $0.syncMetadata.syncState == .pendingUpload }
        )
    }

    func pendingEngagementRecordsForSync() -> [InsightEngagementRecord] {
        sortedEngagementRecords(
            allEngagementRecords.values.filter { isVisible($0) && $0.syncMetadata.syncState == .pendingUpload }
        )
    }

    @discardableResult
    func saveInsights(_ insights: [AIInsight], operationId: UUID? = nil) async -> Bool {
        guard !insights.isEmpty else { return true }

        let writeOperationId = operationId ?? UUID()
        let writeCreatedAt = insights.map(\.createdAt).max() ?? Date()
        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords

        ingest(insights, now: writeCreatedAt, operationId: writeOperationId)
        expireStale(now: writeCreatedAt)

        if await writeJournal.contains(operationId: writeOperationId) {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return true
        }

        guard await persist() != nil else {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return false
        }
        await saveInsightsRemotelyIfNeeded(insights, operationId: writeOperationId)
        await recordWriteOperation(writeOperationId, entityKind: .insight, createdAt: writeCreatedAt)
        return true
    }

    @discardableResult
    func saveDeliveryRecord(_ record: InsightDeliveryRecord, operationId: UUID? = nil) async -> Bool {
        let writeOperationId = operationId ?? UUID()
        let writeCreatedAt = maxOptionalDate(record.deletedAt, record.lastPresentedAt) ?? record.lastPresentedAt
        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords
        let stampedRecord = record.withAccountId(
            currentAccountId ?? record.accountId,
            operationId: writeOperationId,
            now: writeCreatedAt
        )
        let key = storageKey(accountId: stampedRecord.accountId, dedupeKey: stampedRecord.dedupeKey)

        if let existingRecord = allDeliveryRecords[key] {
            allDeliveryRecords[key] = InsightDeliveryRecord.merged(
                local: existingRecord,
                remote: stampedRecord
            )
        } else {
            allDeliveryRecords[key] = stampedRecord
        }
        allDeliveryRecords = bestDeliveryRecordsByStorageKey(Array(allDeliveryRecords.values))
        applyVisibleState()

        if await writeJournal.contains(operationId: writeOperationId) {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return true
        }

        guard await persist() != nil else {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return false
        }
        await saveDeliveryRecordRemotelyIfNeeded(
            dedupeKey: stampedRecord.dedupeKey,
            operationId: writeOperationId
        )
        await recordWriteOperation(writeOperationId, entityKind: .insightDelivery, createdAt: writeCreatedAt)
        return true
    }

    @discardableResult
    func saveEngagementRecord(_ record: InsightEngagementRecord, operationId: UUID? = nil) async -> Bool {
        let writeOperationId = operationId ?? UUID()
        let writeCreatedAt = maxOptionalDate(record.deletedAt, record.latestEngagedAt()) ?? Date()
        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords
        let stampedRecord = record.withAccountId(
            currentAccountId ?? record.accountId,
            operationId: writeOperationId,
            now: writeCreatedAt
        )
        let key = storageKey(accountId: stampedRecord.accountId, dedupeKey: stampedRecord.dedupeKey)

        if let existingRecord = allEngagementRecords[key] {
            allEngagementRecords[key] = existingRecord.merged(with: stampedRecord)
        } else {
            allEngagementRecords[key] = stampedRecord
        }
        allEngagementRecords = bestEngagementRecordsByStorageKey(Array(allEngagementRecords.values))
        applyVisibleState()

        if await writeJournal.contains(operationId: writeOperationId) {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return true
        }

        guard await persist() != nil else {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return false
        }
        await saveEngagementRecordRemotelyIfNeeded(stampedRecord, operationId: writeOperationId)
        await recordWriteOperation(writeOperationId, entityKind: .insightEngagement, createdAt: writeCreatedAt)
        return true
    }

    @discardableResult
    func applyRemoteDeliveryRecords(
        _ remoteRecords: [InsightDeliveryRecord],
        allowReplacingPending: Bool = false
    ) async -> Bool {
        let incomingRecords = remoteRecords.filter(isVisible).map { record in
            var copy = record
            copy.syncMetadata = record.syncMetadata.markedSynced(
                serverVersion: record.syncMetadata.serverVersion
            )
            return copy
        }
        guard !incomingRecords.isEmpty else { return true }
        let deliveryAlreadyApplied = incomingRecords.allSatisfy { incomingRecord in
            allDeliveryRecords.contains {
                $0.key == storageKey(accountId: incomingRecord.accountId, dedupeKey: incomingRecord.dedupeKey) &&
                    $0.value.syncMetadata == incomingRecord.syncMetadata
            }
        }
        if deliveryAlreadyApplied { return true }

        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords

        for remoteRecord in incomingRecords {
            let key = storageKey(accountId: remoteRecord.accountId, dedupeKey: remoteRecord.dedupeKey)
            if let existingRecord = allDeliveryRecords[key] {
                if existingRecord.syncMetadata.syncState == .conflict {
                    continue
                }
                var mergedRecord = InsightDeliveryRecord.merged(
                    local: existingRecord,
                    remote: remoteRecord
                )
                if remoteRecord.deletedAt != nil {
                    mergedRecord.syncMetadata = remoteRecord.syncMetadata
                } else if allowReplacingPending,
                          existingRecord.syncMetadata.syncState == .pendingUpload {
                    mergedRecord.syncMetadata = remoteRecord.syncMetadata
                } else if existingRecord.syncMetadata.syncState == .pendingUpload {
                    mergedRecord.syncMetadata = existingRecord.syncMetadata
                }
                allDeliveryRecords[key] = mergedRecord
            } else {
                allDeliveryRecords[key] = remoteRecord
            }
        }
        allDeliveryRecords = bestDeliveryRecordsByStorageKey(Array(allDeliveryRecords.values))
        applyVisibleState()

        guard await persist() != nil else {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return false
        }
        return true
    }

    @discardableResult
    func applyRemoteEngagementRecords(
        _ remoteRecords: [InsightEngagementRecord],
        allowReplacingPending: Bool = false
    ) async -> Bool {
        let incomingRecords = remoteRecords.filter(isVisible).map { record in
            var copy = record
            copy.syncMetadata = record.syncMetadata.markedSynced(
                serverVersion: record.syncMetadata.serverVersion
            )
            return copy
        }
        guard !incomingRecords.isEmpty else { return true }
        let engagementAlreadyApplied = incomingRecords.allSatisfy { incomingRecord in
            allEngagementRecords.contains {
                $0.key == storageKey(accountId: incomingRecord.accountId, dedupeKey: incomingRecord.dedupeKey) &&
                    $0.value.syncMetadata == incomingRecord.syncMetadata
            }
        }
        if engagementAlreadyApplied { return true }

        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords

        for remoteRecord in incomingRecords {
            let key = storageKey(accountId: remoteRecord.accountId, dedupeKey: remoteRecord.dedupeKey)
            if let existingRecord = allEngagementRecords[key] {
                if existingRecord.syncMetadata.syncState == .conflict {
                    continue
                }
                var mergedRecord = existingRecord.mergedAggregateSnapshot(with: remoteRecord)
                if remoteRecord.deletedAt != nil {
                    mergedRecord.syncMetadata = remoteRecord.syncMetadata
                } else if allowReplacingPending,
                          existingRecord.syncMetadata.syncState == .pendingUpload {
                    mergedRecord.syncMetadata = remoteRecord.syncMetadata
                } else if existingRecord.syncMetadata.syncState == .pendingUpload {
                    mergedRecord.syncMetadata = existingRecord.syncMetadata
                }
                allEngagementRecords[key] = mergedRecord
            } else {
                allEngagementRecords[key] = remoteRecord
            }
        }
        allEngagementRecords = bestEngagementRecordsByStorageKey(Array(allEngagementRecords.values))
        applyVisibleState()

        guard await persist() != nil else {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return false
        }
        return true
    }

    func canPresentOnce(
        dedupeKey: String,
        on surface: InsightSurface
    ) -> Bool {
        deliveryRecords[dedupeKey]?.surfaceLastPresentedAt[surface.rawValue] == nil
    }

    func recordImpression(
        _ insight: AIInsight,
        on surface: InsightSurface,
        now: Date = Date(),
        operationId: UUID? = nil
    ) async {
        let writeOperationId = operationId ?? UUID()
        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords
        recordPresented(insight, on: surface, now: now, operationId: writeOperationId)
        if await writeJournal.contains(operationId: writeOperationId) {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return
        }
        guard await persist() != nil else {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return
        }
        await saveDeliveryRecordRemotelyIfNeeded(
            dedupeKey: insight.dedupeKey,
            operationId: writeOperationId
        )
        await recordWriteOperation(writeOperationId, entityKind: .insightDelivery, createdAt: now)
    }

    func recordPresentation(
        dedupeKey: String,
        on surface: InsightSurface,
        now: Date = Date(),
        operationId: UUID? = nil
    ) async {
        let writeOperationId = operationId ?? UUID()
        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords
        recordPresented(dedupeKey: dedupeKey, on: surface, now: now, operationId: writeOperationId)
        if await writeJournal.contains(operationId: writeOperationId) {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return
        }
        guard await persist() != nil else {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return
        }
        await saveDeliveryRecordRemotelyIfNeeded(
            dedupeKey: dedupeKey,
            operationId: writeOperationId
        )
        await recordWriteOperation(writeOperationId, entityKind: .insightDelivery, createdAt: now)
    }

    func recordEngagement(
        _ insight: AIInsight,
        kind: InsightEngagementKind,
        now: Date = Date(),
        operationId: UUID? = nil
    ) async {
        let writeOperationId = operationId ?? UUID()
        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords
        var remoteDeltaRecord = InsightEngagementRecord(
            accountId: currentAccountId,
            dedupeKey: insight.dedupeKey
        )
        remoteDeltaRecord.record(kind, at: now, operationId: writeOperationId)
        let key = storageKey(accountId: currentAccountId, dedupeKey: insight.dedupeKey)
        if var record = allEngagementRecords[key] {
            record.record(kind, at: now, operationId: writeOperationId)
            allEngagementRecords[key] = record.withAccountId(
                currentAccountId,
                operationId: writeOperationId,
                now: now
            )
        } else {
            var record = InsightEngagementRecord(
                accountId: currentAccountId,
                dedupeKey: insight.dedupeKey
            )
            record.record(kind, at: now, operationId: writeOperationId)
            allEngagementRecords[key] = record
        }
        applyVisibleState()
        if await writeJournal.contains(operationId: writeOperationId) {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return
        }
        guard await persist() != nil else {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return
        }
        await saveEngagementRecordRemotelyIfNeeded(remoteDeltaRecord, operationId: writeOperationId)
        await recordWriteOperation(writeOperationId, entityKind: .insightEngagement, createdAt: now)
    }

    @discardableResult
    func seedInsightsForDebug(
        _ insights: [AIInsight],
        replacingInsightsReferencing workoutIds: Set<UUID> = [],
        now: Date = Date()
    ) async -> Bool {
        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords
        let sampleKeys = Set(insights.map(\.dedupeKey))

        _ = await removeInsightsForDebug(
            dedupeKeys: sampleKeys,
            referencingWorkoutIds: workoutIds,
            shouldPersist: false
        )
        for key in sampleKeys.union(keysReferencingWorkoutIds(workoutIds)) {
            removeVisibleDeliveryRecords(dedupeKey: key)
            removeVisibleEngagementRecords(dedupeKey: key)
        }
        ingest(insights, now: now)
        expireStale(now: now)
        guard await persist() != nil else {
            allInsights = previousAllInsights
            allDeliveryRecords = previousAllDeliveryRecords
            allEngagementRecords = previousAllEngagementRecords
            applyVisibleState()
            return false
        }
        return true
    }

    @discardableResult
    func removeInsightsForDebug(
        dedupeKeys: Set<String>,
        referencingWorkoutIds workoutIds: Set<UUID> = []
    ) async -> Bool {
        await removeInsightsForDebug(
            dedupeKeys: dedupeKeys,
            referencingWorkoutIds: workoutIds,
            shouldPersist: true
        )
    }

    @discardableResult
    func invalidateInsight(dedupeKey: String, deletedAt: Date = Date(), operationId: UUID? = nil) async -> Bool {
        let writeOperationId = operationId ?? UUID()
        let previousAllInsights = allInsights
        var didInvalidate = false
        allInsights = allInsights.map { insight in
            guard insight.dedupeKey == dedupeKey,
                  isVisible(insight),
                  !insight.isDeleted
            else {
                return insight
            }
            didInvalidate = true
            return insight.markedDeleted(at: deletedAt, operationId: writeOperationId)
        }

        guard didInvalidate else {
            return await writeJournal.contains(operationId: writeOperationId)
        }
        applyVisibleState()
        if await writeJournal.contains(operationId: writeOperationId) {
            allInsights = previousAllInsights
            applyVisibleState()
            return true
        }
        guard await persist() != nil else {
            allInsights = previousAllInsights
            applyVisibleState()
            return false
        }
        await invalidateInsightRemotelyIfNeeded(
            dedupeKey: dedupeKey,
            operationId: writeOperationId
        )
        await recordWriteOperation(writeOperationId, entityKind: .insight, createdAt: deletedAt)
        return true
    }

    @discardableResult
    func invalidateInsightsReferencingWorkout(
        id: UUID,
        deletedAt: Date = Date(),
        operationId: UUID? = nil
    ) async -> Int {
        let writeOperationId = operationId ?? UUID()
        let previousAllInsights = allInsights
        var invalidatedCount = 0
        var invalidatedDedupeKeys: [String] = []
        allInsights = allInsights.map { insight in
            guard !insight.isDeleted,
                  isVisible(insight),
                  insight.evidence.contains(where: { $0.workoutId == id })
            else { return insight }

            invalidatedCount += 1
            invalidatedDedupeKeys.append(insight.dedupeKey)
            return insight.markedDeleted(at: deletedAt, operationId: writeOperationId)
        }

        guard invalidatedCount > 0 else { return 0 }
        applyVisibleState()
        if await writeJournal.contains(operationId: writeOperationId) {
            allInsights = previousAllInsights
            applyVisibleState()
            return 0
        }
        guard await persist() != nil else {
            allInsights = previousAllInsights
            applyVisibleState()
            return 0
        }
        for dedupeKey in invalidatedDedupeKeys {
            await invalidateInsightRemotelyIfNeeded(
                dedupeKey: dedupeKey,
                operationId: writeOperationId
            )
        }
        await recordWriteOperation(writeOperationId, entityKind: .insight, createdAt: deletedAt)
        return invalidatedCount
    }

    func clearForDebug() async {
        allInsights.removeAll { isVisible($0) }
        allDeliveryRecords = allDeliveryRecords.filter { !isVisible($0.value) }
        allEngagementRecords = allEngagementRecords.filter { !isVisible($0.value) }
        applyVisibleState()
        _ = await persist()
    }

    func reload() {
        load()
    }

    @discardableResult
    func claimLocalDataForAccount(id accountId: String, operationId: UUID? = nil) async -> Bool {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            persistenceError = "Account id is required before local insight data can be claimed."
            return false
        }
        let hasClaimableData = allInsights.contains { $0.accountId == nil } ||
            allDeliveryRecords.values.contains { $0.accountId == nil } ||
            allEngagementRecords.values.contains { $0.accountId == nil }
        guard hasClaimableData else { return true }

        let writeOperationId = operationId ?? UUID()

        let writeCreatedAt = Date()
        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords

        allInsights = dedupedInsightsByStorageKey(
            allInsights.map { insight in
                insight.accountId == nil
                    ? insight.withAccountId(
                        normalizedAccountId,
                        operationId: writeOperationId,
                        now: writeCreatedAt
                    )
                    : insight
            }
        )
        allDeliveryRecords = bestDeliveryRecordsByStorageKey(
            allDeliveryRecords.values.map { record in
                record.accountId == nil
                    ? record.withAccountId(
                        normalizedAccountId,
                        operationId: writeOperationId,
                        now: writeCreatedAt
                    )
                    : record
            }
        )
        allEngagementRecords = bestEngagementRecordsByStorageKey(
            allEngagementRecords.values.map { record in
                record.accountId == nil
                    ? record.withAccountId(
                        normalizedAccountId,
                        operationId: writeOperationId,
                        now: writeCreatedAt
                    )
                    : record
            }
        )
        applyVisibleState()

        if await writeJournal.contains(operationId: writeOperationId) {
            allInsights = previousAllInsights
            allDeliveryRecords = previousAllDeliveryRecords
            allEngagementRecords = previousAllEngagementRecords
            applyVisibleState()
            return true
        }

        guard await persist() != nil else {
            allInsights = previousAllInsights
            allDeliveryRecords = previousAllDeliveryRecords
            allEngagementRecords = previousAllEngagementRecords
            applyVisibleState()
            return false
        }
        await syncVisibleInsightStateRemotelyIfNeeded(operationId: writeOperationId)
        await recordWriteOperation(writeOperationId, entityKind: .insight, createdAt: writeCreatedAt)
        return true
    }

    @discardableResult
    func markInsightConflict(
        dedupeKey: String,
        serverVersion: String?,
        localVersion: String?
    ) async -> Bool {
        let previousAllInsights = allInsights
        var didMark = false
        allInsights = allInsights.map { insight in
            guard insight.dedupeKey == dedupeKey, isVisible(insight) else { return insight }
            var copy = insight
            copy.syncMetadata = insight.syncMetadata.markedConflict(
                serverVersion: serverVersion,
                localVersion: localVersion
            )
            didMark = true
            return copy
        }
        guard didMark else { return false }
        applyVisibleState()
        guard await persist() != nil else {
            allInsights = previousAllInsights
            applyVisibleState()
            return false
        }
        return true
    }

    @discardableResult
    func markDeliveryConflict(
        dedupeKey: String,
        serverVersion: String?,
        localVersion: String?
    ) async -> Bool {
        let previousAllDeliveryRecords = allDeliveryRecords
        guard let key = allDeliveryRecords.first(where: {
            $0.value.dedupeKey == dedupeKey && isVisible($0.value)
        })?.key else {
            return false
        }
        var record = allDeliveryRecords[key]!
        record.syncMetadata = record.syncMetadata.markedConflict(
            serverVersion: serverVersion,
            localVersion: localVersion
        )
        allDeliveryRecords[key] = record
        applyVisibleState()
        guard await persist() != nil else {
            allDeliveryRecords = previousAllDeliveryRecords
            applyVisibleState()
            return false
        }
        return true
    }

    @discardableResult
    func markEngagementConflict(
        dedupeKey: String,
        serverVersion: String?,
        localVersion: String?
    ) async -> Bool {
        let previousAllEngagementRecords = allEngagementRecords
        guard let key = allEngagementRecords.first(where: {
            $0.value.dedupeKey == dedupeKey && isVisible($0.value)
        })?.key else {
            return false
        }
        var record = allEngagementRecords[key]!
        record.syncMetadata = record.syncMetadata.markedConflict(
            serverVersion: serverVersion,
            localVersion: localVersion
        )
        allEngagementRecords[key] = record
        applyVisibleState()
        guard await persist() != nil else {
            allEngagementRecords = previousAllEngagementRecords
            applyVisibleState()
            return false
        }
        return true
    }
}

extension InsightStore {
    func fetchCandidates(
        for surface: InsightSurface,
        profile: UserProfile,
        now: Date
    ) -> [AIInsight] {
        recentInsights
            .filter { !$0.isDeleted && !$0.isExpired(now: now) && $0.surfaces.contains(surface) }
            .filter { !wasRecentlyPresented($0, on: surface, now: now) }
            .reduce(into: [String: AIInsight]()) { result, insight in
                if let existing = result[insight.dedupeKey] {
                    let existingScore = ranker.score(
                        existing,
                        surface: surface,
                        profile: profile,
                        engagementRecords: engagementRecords,
                        now: now
                    )
                    let newScore = ranker.score(
                        insight,
                        surface: surface,
                        profile: profile,
                        engagementRecords: engagementRecords,
                        now: now
                    )
                    if newScore > existingScore ||
                        (newScore == existingScore && insight.createdAt > existing.createdAt) {
                        result[insight.dedupeKey] = insight
                    }
                } else {
                    result[insight.dedupeKey] = insight
                }
            }
            .values
            .sorted { lhs, rhs in
                let left = ranker.score(
                    lhs,
                    surface: surface,
                    profile: profile,
                    engagementRecords: engagementRecords,
                    now: now
                )
                let right = ranker.score(
                    rhs,
                    surface: surface,
                    profile: profile,
                    engagementRecords: engagementRecords,
                    now: now
                )
                if left == right {
                    return lhs.createdAt > rhs.createdAt
                }
                return left > right
            }
    }

    func ingest(
        _ insights: [AIInsight],
        now: Date,
        operationId: UUID? = nil
    ) {
        var byKey = bestInsightsByDedupeKey(allInsights.filter { belongsToCurrentAccount($0) })
        for insight in insights where !insight.isExpired(now: now) && !insight.evidence.isEmpty {
            let accountStampedInsight = insight.withAccountId(
                currentAccountId,
                operationId: operationId,
                now: now
            )
            if let existing = byKey[accountStampedInsight.dedupeKey] {
                if existing.isDeleted && !accountStampedInsight.isDeleted {
                    continue
                }
                if shouldPrefer(accountStampedInsight, over: existing) ||
                    accountStampedInsight.userValueScore >= existing.userValueScore ||
                    accountStampedInsight.createdAt > existing.createdAt {
                    byKey[accountStampedInsight.dedupeKey] = accountStampedInsight
                }
            } else {
                byKey[accountStampedInsight.dedupeKey] = accountStampedInsight
            }
        }

        let sortedInsights = byKey.values
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.userValueScore > $1.userValueScore
                }
                return $0.createdAt > $1.createdAt
            }
        let visibleInsights = sortedInsights.filter { !$0.isDeleted }.prefix(80)
        let deletedInsights = sortedInsights.filter(\.isDeleted)
        replaceCurrentAccountInsights(with: Array(visibleInsights) + deletedInsights)
        applyVisibleState()
    }

    func expireStale(now: Date) {
        allInsights = allInsights.filter { $0.isDeleted || !$0.isExpired(now: now) }
        let retainedInsightKeys = Set(allInsights.map {
            storageKey(accountId: $0.accountId, dedupeKey: $0.dedupeKey)
        })
        allDeliveryRecords = allDeliveryRecords.filter { element in
            let recordActivityAt = maxOptionalDate(element.value.deletedAt, element.value.lastPresentedAt)
                ?? element.value.lastPresentedAt
            return retainedInsightKeys.contains(element.key) ||
                recordActivityAt > staleDeliveryCutoff(now: now)
        }
        applyVisibleState()
    }

    func recordPresented(
        _ insight: AIInsight,
        on surface: InsightSurface,
        now: Date,
        operationId: UUID? = nil
    ) {
        let key = storageKey(accountId: currentAccountId, dedupeKey: insight.dedupeKey)
        if var record = allDeliveryRecords[key] {
            record.recordPresentation(at: now, surface: surface, operationId: operationId)
            allDeliveryRecords[key] = record.withAccountId(
                currentAccountId,
                operationId: operationId,
                now: now
            )
        } else {
            allDeliveryRecords[key] = InsightDeliveryRecord(
                accountId: currentAccountId,
                dedupeKey: insight.dedupeKey,
                presentedAt: now,
                surface: surface,
                syncMetadata: initialSyncMetadata(operationId: operationId, now: now)
            )
        }
        applyVisibleState()
    }

    func recordPresented(
        dedupeKey: String,
        on surface: InsightSurface,
        now: Date,
        operationId: UUID? = nil
    ) {
        let key = storageKey(accountId: currentAccountId, dedupeKey: dedupeKey)
        if var record = allDeliveryRecords[key] {
            record.recordPresentation(at: now, surface: surface, operationId: operationId)
            allDeliveryRecords[key] = record.withAccountId(
                currentAccountId,
                operationId: operationId,
                now: now
            )
        } else {
            allDeliveryRecords[key] = InsightDeliveryRecord(
                accountId: currentAccountId,
                dedupeKey: dedupeKey,
                presentedAt: now,
                surface: surface,
                syncMetadata: initialSyncMetadata(operationId: operationId, now: now)
            )
        }
        applyVisibleState()
    }

    func wasRecentlyPresented(
        _ insight: AIInsight,
        on surface: InsightSurface,
        now: Date
    ) -> Bool {
        guard insight.severity != .important else { return false }
        guard let record = deliveryRecords[insight.dedupeKey],
              let lastPresented = record.surfaceLastPresentedAt[surface.rawValue]
        else { return false }

        return now.timeIntervalSince(lastPresented) < repeatCooldown(for: surface)
    }

    func repeatCooldown(for surface: InsightSurface) -> TimeInterval {
        switch surface {
        case .dashboard:
            return 18 * 60 * 60
        case .profile:
            return 22 * 60 * 60
        case .workoutPreview:
            return 6 * 60 * 60
        case .workoutSummary:
            return 10 * 60
        case .trophyScreen:
            return 18 * 60 * 60
        }
    }

    func staleDeliveryCutoff(now: Date) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .day, value: -45, to: now) ?? now
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            allInsights = []
            allDeliveryRecords = [:]
            allEngagementRecords = [:]
            recentInsights = []
            deliveryRecords = [:]
            engagementRecords = [:]
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try decoder.decode(PersistedInsightStoreSnapshot.self, from: data)
            allInsights = dedupedInsightsByStorageKey(snapshot.recentInsights)
            allDeliveryRecords = bestDeliveryRecordsByStorageKey(snapshot.deliveryRecords)
            allEngagementRecords = bestEngagementRecordsByStorageKey(snapshot.engagementRecords)
            applyVisibleState()
            persistenceError = nil
        } catch {
            allInsights = []
            allDeliveryRecords = [:]
            allEngagementRecords = [:]
            recentInsights = []
            deliveryRecords = [:]
            engagementRecords = [:]
            persistenceError = "Could not load coach insights: \(error.localizedDescription)"
        }
    }

    private func restartInsightObservationIfNeeded() {
        insightObservationTask?.cancel()
        deliveryObservationTask?.cancel()
        engagementObservationTask?.cancel()
        insightObservationTask = nil
        deliveryObservationTask = nil
        engagementObservationTask = nil

        guard backendMode == .firebase,
              autoObserveRemote,
              let insightRepository,
              let currentAccountId else {
            return
        }

        insightObservationTask = Task { [weak self, insightRepository, currentAccountId] in
            do {
                let loadedInsights = try await insightRepository.loadRecentInsights(
                    accountId: currentAccountId,
                    limit: 80
                )
                _ = await self?.applyRemoteInsights(loadedInsights)

                let stream = try await insightRepository.observeRecentInsights(
                    accountId: currentAccountId,
                    limit: 80
                )
                for await remoteInsights in stream {
                    _ = await self?.applyRemoteInsights(remoteInsights)
                }
            } catch {
                self?.setRemoteInsightError(error)
            }
        }

        deliveryObservationTask = Task { [weak self, insightRepository, currentAccountId] in
            do {
                let loadedRecords = try await insightRepository.loadDeliveryRecords(accountId: currentAccountId)
                _ = await self?.applyRemoteDeliveryRecords(loadedRecords)

                let stream = try await insightRepository.observeDeliveryRecords(accountId: currentAccountId)
                for await remoteRecords in stream {
                    _ = await self?.applyRemoteDeliveryRecords(remoteRecords)
                }
            } catch {
                self?.setRemoteInsightError(error)
            }
        }

        engagementObservationTask = Task { [weak self, insightRepository, currentAccountId] in
            do {
                let loadedRecords = try await insightRepository.loadEngagementRecords(accountId: currentAccountId)
                _ = await self?.applyRemoteEngagementRecords(loadedRecords)

                let stream = try await insightRepository.observeEngagementRecords(accountId: currentAccountId)
                for await remoteRecords in stream {
                    _ = await self?.applyRemoteEngagementRecords(remoteRecords)
                }
            } catch {
                self?.setRemoteInsightError(error)
            }
        }
    }

    @discardableResult
    func applyRemoteInsights(
        _ remoteInsights: [AIInsight],
        allowReplacingPending: Bool = false
    ) async -> Bool {
        let incomingInsights = remoteInsights.filter(isVisible).map { insight in
            var copy = insight
            copy.syncMetadata = insight.syncMetadata.markedSynced(
                serverVersion: insight.syncMetadata.serverVersion
            )
            return copy
        }
        guard !incomingInsights.isEmpty else { return true }
        let alreadyApplied = incomingInsights.allSatisfy { incomingInsight in
            allInsights.contains {
                storageKey(accountId: $0.accountId, dedupeKey: $0.dedupeKey) ==
                    storageKey(accountId: incomingInsight.accountId, dedupeKey: incomingInsight.dedupeKey) &&
                    $0.syncMetadata == incomingInsight.syncMetadata
            }
        }
        if alreadyApplied { return true }

        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords
        var updatedInsights = allInsights
        for incomingInsight in incomingInsights {
            let incomingKey = storageKey(
                accountId: incomingInsight.accountId,
                dedupeKey: incomingInsight.dedupeKey
            )
            if let existingIndex = updatedInsights.firstIndex(where: {
                storageKey(accountId: $0.accountId, dedupeKey: $0.dedupeKey) == incomingKey
            }) {
                let existingInsight = updatedInsights[existingIndex]
                if existingInsight.syncMetadata.syncState == .conflict ||
                    (!allowReplacingPending && existingInsight.syncMetadata.syncState == .pendingUpload) {
                    continue
                }
                updatedInsights[existingIndex] = incomingInsight
            } else {
                updatedInsights.append(incomingInsight)
            }
        }
        allInsights = dedupedInsightsByStorageKey(updatedInsights)
        applyVisibleState()

        guard await persist() != nil else {
            restoreState(
                insights: previousAllInsights,
                deliveryRecords: previousAllDeliveryRecords,
                engagementRecords: previousAllEngagementRecords
            )
            return false
        }
        return true
    }

    private func saveInsightsRemotelyIfNeeded(
        _ insights: [AIInsight],
        operationId: UUID
    ) async {
        guard backendMode == .firebase,
              let insightRepository,
              let currentAccountId else {
            return
        }
        let now = Date()
        let outgoingInsights = insights
            .filter { !$0.isExpired(now: now) && !$0.evidence.isEmpty }
            .map {
                $0.withAccountId(
                    currentAccountId,
                    operationId: operationId,
                    now: $0.createdAt
                )
            }
        guard !outgoingInsights.isEmpty else { return }

        do {
            _ = try await insightRepository.saveInsights(
                outgoingInsights,
                operationId: operationId
            )
        } catch {
            setRemoteInsightError(error)
        }
    }

    private func saveDeliveryRecordRemotelyIfNeeded(
        dedupeKey: String,
        operationId: UUID
    ) async {
        guard backendMode == .firebase,
              let insightRepository,
              let currentAccountId else {
            return
        }
        let key = storageKey(accountId: currentAccountId, dedupeKey: dedupeKey)
        guard let record = allDeliveryRecords[key] else { return }

        do {
            _ = try await insightRepository.saveDeliveryRecord(
                record.withAccountId(currentAccountId, operationId: operationId),
                operationId: operationId
            )
        } catch {
            setRemoteInsightError(error)
        }
    }

    private func saveEngagementRecordRemotelyIfNeeded(
        _ record: InsightEngagementRecord,
        operationId: UUID
    ) async {
        guard backendMode == .firebase,
              let insightRepository,
              let currentAccountId else {
            return
        }
        let activityDate = maxOptionalDate(record.deletedAt, record.latestEngagedAt()) ?? Date()

        do {
            _ = try await insightRepository.saveEngagementRecord(
                record.withAccountId(currentAccountId, operationId: operationId, now: activityDate),
                operationId: operationId
            )
        } catch {
            setRemoteInsightError(error)
        }
    }

    private func invalidateInsightRemotelyIfNeeded(
        dedupeKey: String,
        operationId: UUID
    ) async {
        guard backendMode == .firebase,
              let insightRepository,
              let currentAccountId else {
            return
        }

        do {
            try await insightRepository.invalidateInsight(
                accountId: currentAccountId,
                dedupeKey: dedupeKey,
                operationId: operationId
            )
        } catch {
            setRemoteInsightError(error)
        }
    }

    private func syncVisibleInsightStateRemotelyIfNeeded(operationId: UUID) async {
        guard backendMode == .firebase,
              let insightRepository,
              let currentAccountId else {
            return
        }
        let now = Date()
        let outgoingInsights = allInsights
            .filter { isVisible($0) && !$0.isDeleted && !$0.isExpired(now: now) && !$0.evidence.isEmpty }
            .map { $0.withAccountId(currentAccountId, operationId: operationId, now: $0.createdAt) }
        let outgoingDeliveryRecords = allDeliveryRecords.values
            .filter { isVisible($0) && !$0.isDeleted }
            .map { $0.withAccountId(currentAccountId, operationId: operationId) }
        let outgoingEngagementRecords = allEngagementRecords.values
            .filter { isVisible($0) && !$0.isDeleted }
            .map { $0.withAccountId(currentAccountId, operationId: operationId) }

        do {
            if !outgoingInsights.isEmpty {
                _ = try await insightRepository.saveInsights(outgoingInsights, operationId: operationId)
            }
            for record in outgoingDeliveryRecords {
                _ = try await insightRepository.saveDeliveryRecord(record, operationId: operationId)
            }
            for record in outgoingEngagementRecords {
                _ = try await insightRepository.saveEngagementRecord(record, operationId: operationId)
            }
        } catch {
            setRemoteInsightError(error)
        }
    }

    private func setRemoteInsightError(_ error: Error) {
        persistenceError = "Could not sync coach insights: \(error.localizedDescription)"
    }

    @discardableResult
    func persist() async -> PersistenceWriteOutcome? {
        do {
            let snapshot = PersistedInsightStoreSnapshot(
                sourcePolicyVersion: AIInsight.currentSourcePolicyVersion,
                savedAt: Date(),
                recentInsights: allInsights,
                deliveryRecords: Array(allDeliveryRecords.values),
                engagementRecords: Array(allEngagementRecords.values)
            )
            let data = try await persistenceActor.encode(
                snapshot,
                outputFormatting: [.prettyPrinted, .sortedKeys]
            )
            let outcome = try await persistenceActor.writeLatest(data, to: fileURL, options: [.atomic])
            persistenceError = nil
            return outcome
        } catch {
            persistenceError = "Could not save coach insights: \(error.localizedDescription)"
            return nil
        }
    }

    static func defaultInsightURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("CoachInsights.json")
    }

    func initialSyncMetadata(operationId: UUID?, now: Date) -> SyncMetadata {
        currentAccountId == nil
            ? .initialLocalOnly(now: now)
            : .initialPendingUpload(operationId: operationId, now: now)
    }

    func recordWriteOperation(
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

    func restoreState(
        insights: [AIInsight],
        deliveryRecords: [String: InsightDeliveryRecord],
        engagementRecords: [String: InsightEngagementRecord]
    ) {
        allInsights = insights
        allDeliveryRecords = deliveryRecords
        allEngagementRecords = engagementRecords
        applyVisibleState()
    }

    func applyVisibleState() {
        recentInsights = bestInsightsByDedupeKey(allInsights.filter { isVisible($0) })
            .values
            .sorted { $0.createdAt > $1.createdAt }
        deliveryRecords = bestDeliveryRecordsByDedupeKey(
            allDeliveryRecords.values.filter { !$0.isDeleted && isVisible($0) }
        )
        engagementRecords = bestEngagementRecordsByDedupeKey(
            allEngagementRecords.values.filter { !$0.isDeleted && isVisible($0) }
        )
    }

    func replaceCurrentAccountInsights(with insights: [AIInsight]) {
        allInsights.removeAll(where: belongsToCurrentAccount)
        allInsights.append(contentsOf: insights.map { $0.withAccountId(currentAccountId) })
        allInsights = dedupedInsightsByStorageKey(allInsights)
    }

    func belongsToCurrentAccount(_ insight: AIInsight) -> Bool {
        AccountOwnership.normalizedAccountId(insight.accountId) == currentAccountId
    }

    func isVisible(_ insight: AIInsight) -> Bool {
        AccountOwnership.isVisible(
            recordAccountId: insight.accountId,
            currentAccountId: currentAccountId
        )
    }

    func isVisible(_ record: InsightDeliveryRecord) -> Bool {
        AccountOwnership.isVisible(
            recordAccountId: record.accountId,
            currentAccountId: currentAccountId
        )
    }

    func isVisible(_ record: InsightEngagementRecord) -> Bool {
        AccountOwnership.isVisible(
            recordAccountId: record.accountId,
            currentAccountId: currentAccountId
        )
    }

    func storageKey(accountId: String?, dedupeKey: String) -> String {
        AccountOwnership.storageKey(accountId: accountId, recordId: dedupeKey)
    }

    func sortedDeliveryRecords(
        _ records: [InsightDeliveryRecord]
    ) -> [InsightDeliveryRecord] {
        records.sorted {
            if $0.dedupeKey != $1.dedupeKey {
                return $0.dedupeKey < $1.dedupeKey
            }
            if ($0.accountId ?? "") != ($1.accountId ?? "") {
                return ($0.accountId ?? "") < ($1.accountId ?? "")
            }
            let leftActivityAt = maxOptionalDate($0.deletedAt, $0.lastPresentedAt) ?? $0.lastPresentedAt
            let rightActivityAt = maxOptionalDate($1.deletedAt, $1.lastPresentedAt) ?? $1.lastPresentedAt
            return leftActivityAt > rightActivityAt
        }
    }

    func sortedEngagementRecords(
        _ records: [InsightEngagementRecord]
    ) -> [InsightEngagementRecord] {
        records.sorted {
            if $0.dedupeKey != $1.dedupeKey {
                return $0.dedupeKey < $1.dedupeKey
            }
            if ($0.accountId ?? "") != ($1.accountId ?? "") {
                return ($0.accountId ?? "") < ($1.accountId ?? "")
            }
            let leftActivityAt = maxOptionalDate($0.deletedAt, $0.latestEngagedAt())
            let rightActivityAt = maxOptionalDate($1.deletedAt, $1.latestEngagedAt())
            return (leftActivityAt ?? .distantPast) > (rightActivityAt ?? .distantPast)
        }
    }

    func dedupedInsightsByStorageKey(_ insights: [AIInsight]) -> [AIInsight] {
        let groupedInsights = Dictionary(grouping: insights) {
            storageKey(accountId: $0.accountId, dedupeKey: $0.dedupeKey)
        }
        return groupedInsights.values.compactMap { entries in
            bestInsightsByDedupeKey(entries).values.first
        }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.userValueScore > rhs.userValueScore
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func bestDeliveryRecordsByStorageKey(
        _ records: [InsightDeliveryRecord]
    ) -> [String: InsightDeliveryRecord] {
        records.reduce(into: [String: InsightDeliveryRecord]()) { result, record in
            let key = storageKey(accountId: record.accountId, dedupeKey: record.dedupeKey)
            if let existing = result[key] {
                result[key] = InsightDeliveryRecord.merged(local: existing, remote: record)
            } else {
                result[key] = record
            }
        }
    }

    func bestEngagementRecordsByStorageKey(
        _ records: [InsightEngagementRecord]
    ) -> [String: InsightEngagementRecord] {
        records.reduce(into: [String: InsightEngagementRecord]()) { result, record in
            let key = storageKey(accountId: record.accountId, dedupeKey: record.dedupeKey)
            if let existing = result[key] {
                result[key] = existing.mergedAggregateSnapshot(with: record)
            } else {
                result[key] = record
            }
        }
    }

    func removeVisibleDeliveryRecords(dedupeKey: String) {
        allDeliveryRecords = allDeliveryRecords.filter { element in
            element.value.dedupeKey != dedupeKey || !isVisible(element.value)
        }
        applyVisibleState()
    }

    func removeVisibleEngagementRecords(dedupeKey: String) {
        allEngagementRecords = allEngagementRecords.filter { element in
            element.value.dedupeKey != dedupeKey || !isVisible(element.value)
        }
        applyVisibleState()
    }

    func bestInsightsByDedupeKey(_ insights: [AIInsight]) -> [String: AIInsight] {
        insights.reduce(into: [String: AIInsight]()) { result, insight in
            guard !insight.evidence.isEmpty,
                  insight.sourcePolicyVersion == AIInsight.currentSourcePolicyVersion
            else { return }
            if let existing = result[insight.dedupeKey] {
                if shouldPrefer(insight, over: existing) {
                    result[insight.dedupeKey] = insight
                }
            } else {
                result[insight.dedupeKey] = insight
            }
        }
    }

    func shouldPrefer(_ candidate: AIInsight, over existing: AIInsight) -> Bool {
        if candidate.isDeleted != existing.isDeleted {
            return candidate.isDeleted
        }
        if candidate.isDeleted {
            return (candidate.deletedAt ?? candidate.createdAt) > (existing.deletedAt ?? existing.createdAt)
        }
        if candidate.userValueScore != existing.userValueScore {
            return candidate.userValueScore > existing.userValueScore
        }
        return candidate.createdAt > existing.createdAt
    }

    func bestDeliveryRecordsByDedupeKey(
        _ records: [InsightDeliveryRecord]
    ) -> [String: InsightDeliveryRecord] {
        records.reduce(into: [String: InsightDeliveryRecord]()) { result, record in
            if let existing = result[record.dedupeKey] {
                result[record.dedupeKey] = InsightDeliveryRecord.merged(local: existing, remote: record)
            } else {
                result[record.dedupeKey] = record
            }
        }
    }

    func bestEngagementRecordsByDedupeKey(
        _ records: [InsightEngagementRecord]
    ) -> [String: InsightEngagementRecord] {
        records.reduce(into: [String: InsightEngagementRecord]()) { result, record in
            if let existing = result[record.dedupeKey] {
                result[record.dedupeKey] = existing.mergedAggregateSnapshot(with: record)
            } else {
                result[record.dedupeKey] = record
            }
        }
    }

    func removeInsightsForDebug(
        dedupeKeys: Set<String>,
        referencingWorkoutIds workoutIds: Set<UUID>,
        shouldPersist: Bool
    ) async -> Bool {
        let keysToRemove = dedupeKeys.union(keysReferencingWorkoutIds(workoutIds))
        guard !keysToRemove.isEmpty else { return true }

        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords
        allInsights.removeAll {
            keysToRemove.contains($0.dedupeKey) && isVisible($0)
        }
        for key in keysToRemove {
            removeVisibleDeliveryRecords(dedupeKey: key)
            removeVisibleEngagementRecords(dedupeKey: key)
        }
        applyVisibleState()

        guard shouldPersist else { return true }
        guard await persist() != nil else {
            allInsights = previousAllInsights
            allDeliveryRecords = previousAllDeliveryRecords
            allEngagementRecords = previousAllEngagementRecords
            applyVisibleState()
            return false
        }
        return true
    }

    func keysReferencingWorkoutIds(_ workoutIds: Set<UUID>) -> Set<String> {
        guard !workoutIds.isEmpty else { return [] }
        return Set(
            recentInsights
                .filter { insight in
                    insight.evidence.contains { evidence in
                        guard let workoutId = evidence.workoutId else { return false }
                        return workoutIds.contains(workoutId)
                    }
                }
                .map(\.dedupeKey)
        )
    }
}
