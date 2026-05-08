import Foundation
import Combine

nonisolated struct InsightDeliveryRecord: Codable, Equatable {
    let accountId: String?
    let dedupeKey: String
    var firstPresentedAt: Date
    var lastPresentedAt: Date
    var presentationCount: Int
    var surfaceLastPresentedAt: [String: Date]

    init(
        accountId: String? = nil,
        dedupeKey: String,
        presentedAt: Date,
        surface: InsightSurface
    ) {
        self.accountId = AccountOwnership.normalizedAccountId(accountId)
        self.dedupeKey = dedupeKey
        self.firstPresentedAt = presentedAt
        self.lastPresentedAt = presentedAt
        self.presentationCount = 1
        self.surfaceLastPresentedAt = [surface.rawValue: presentedAt]
    }

    mutating func recordPresentation(
        at date: Date,
        surface: InsightSurface
    ) {
        lastPresentedAt = date
        presentationCount += 1
        surfaceLastPresentedAt[surface.rawValue] = date
    }

    func withAccountId(_ accountId: String?) -> InsightDeliveryRecord {
        var copy = self
        copy = InsightDeliveryRecord(
            accountId: accountId,
            dedupeKey: dedupeKey,
            presentedAt: firstPresentedAt,
            surface: .dashboard
        )
        copy.firstPresentedAt = firstPresentedAt
        copy.lastPresentedAt = lastPresentedAt
        copy.presentationCount = presentationCount
        copy.surfaceLastPresentedAt = surfaceLastPresentedAt
        return copy
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

    init(
        accountId: String? = nil,
        dedupeKey: String,
        engagementCounts: [String: Int] = [:],
        lastEngagementDates: [String: Date] = [:]
    ) {
        self.accountId = AccountOwnership.normalizedAccountId(accountId)
        self.dedupeKey = dedupeKey
        self.engagementCounts = engagementCounts
        self.lastEngagementDates = lastEngagementDates
    }

    mutating func record(
        _ kind: InsightEngagementKind,
        at date: Date
    ) {
        engagementCounts[kind.rawValue, default: 0] += 1
        lastEngagementDates[kind.rawValue] = date
    }

    func count(for kind: InsightEngagementKind) -> Int {
        engagementCounts[kind.rawValue] ?? 0
    }

    func lastEngagedAt(for kind: InsightEngagementKind) -> Date? {
        lastEngagementDates[kind.rawValue]
    }

    func merged(with other: InsightEngagementRecord) -> InsightEngagementRecord {
        var merged = self
        for (kind, count) in other.engagementCounts {
            merged.engagementCounts[kind, default: 0] += count
        }
        for (kind, date) in other.lastEngagementDates {
            if let existingDate = merged.lastEngagementDates[kind] {
                merged.lastEngagementDates[kind] = max(existingDate, date)
            } else {
                merged.lastEngagementDates[kind] = date
            }
        }
        return merged
    }

    func withAccountId(_ accountId: String?) -> InsightEngagementRecord {
        InsightEngagementRecord(
            accountId: accountId,
            dedupeKey: dedupeKey,
            engagementCounts: engagementCounts,
            lastEngagementDates: lastEngagementDates
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
    private var currentAccountId: String?
    private var allInsights: [AIInsight] = []
    private var allDeliveryRecords: [String: InsightDeliveryRecord] = [:]
    private var allEngagementRecords: [String: InsightEngagementRecord] = [:]
    private var deliveryRecords: [String: InsightDeliveryRecord] = [:]
    private var engagementRecords: [String: InsightEngagementRecord] = [:]
    private let ranker = InsightRanker()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil, accountId: String? = nil) {
        self.fileURL = fileURL ?? Self.defaultInsightURL()
        self.currentAccountId = AccountOwnership.normalizedAccountId(accountId)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    nonisolated deinit {}

    func setCurrentAccountId(_ accountId: String?) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        guard currentAccountId != normalizedAccountId else { return }
        currentAccountId = normalizedAccountId
        applyVisibleState()
    }

    @discardableResult
    func selectInsights(
        _ generatedInsights: [AIInsight],
        for surface: InsightSurface,
        profile: UserProfile,
        limit: Int,
        now: Date = Date()
    ) -> [AIInsight] {
        ingest(generatedInsights, now: now)
        expireStale(now: now)

        let candidates = fetchCandidates(for: surface, profile: profile, now: now)
        let selected = Array(candidates.prefix(max(limit, 0)))
        persist()
        return selected
    }

    @discardableResult
    func selectGeneratedInsights(
        _ generatedInsights: [AIInsight],
        for surface: InsightSurface,
        profile: UserProfile,
        limit: Int,
        now: Date = Date()
    ) -> [AIInsight] {
        ingest(generatedInsights, now: now)
        expireStale(now: now)

        let generatedDedupeKeys = Set(
            generatedInsights
                .filter { !$0.isDeleted && !$0.isExpired(now: now) && !$0.evidence.isEmpty && $0.surfaces.contains(surface) }
                .map(\.dedupeKey)
        )
        let candidates = fetchCandidates(for: surface, profile: profile, now: now)
            .filter { generatedDedupeKeys.contains($0.dedupeKey) }
        let selected = Array(candidates.prefix(max(limit, 0)))
        persist()
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

    func canPresentOnce(
        dedupeKey: String,
        on surface: InsightSurface
    ) -> Bool {
        deliveryRecords[dedupeKey]?.surfaceLastPresentedAt[surface.rawValue] == nil
    }

    func recordImpression(
        _ insight: AIInsight,
        on surface: InsightSurface,
        now: Date = Date()
    ) {
        recordPresented(insight, on: surface, now: now)
        persist()
    }

    func recordPresentation(
        dedupeKey: String,
        on surface: InsightSurface,
        now: Date = Date()
    ) {
        recordPresented(dedupeKey: dedupeKey, on: surface, now: now)
        persist()
    }

    func recordEngagement(
        _ insight: AIInsight,
        kind: InsightEngagementKind,
        now: Date = Date()
    ) {
        let key = storageKey(accountId: currentAccountId, dedupeKey: insight.dedupeKey)
        if var record = allEngagementRecords[key] {
            record.record(kind, at: now)
            allEngagementRecords[key] = record.withAccountId(currentAccountId)
        } else {
            var record = InsightEngagementRecord(
                accountId: currentAccountId,
                dedupeKey: insight.dedupeKey
            )
            record.record(kind, at: now)
            allEngagementRecords[key] = record
        }
        applyVisibleState()
        persist()
    }

    @discardableResult
    func seedInsightsForDebug(
        _ insights: [AIInsight],
        replacingInsightsReferencing workoutIds: Set<UUID> = [],
        now: Date = Date()
    ) -> Bool {
        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords
        let sampleKeys = Set(insights.map(\.dedupeKey))

        _ = removeInsightsForDebug(
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
        guard persist() else {
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
    ) -> Bool {
        removeInsightsForDebug(
            dedupeKeys: dedupeKeys,
            referencingWorkoutIds: workoutIds,
            shouldPersist: true
        )
    }

    @discardableResult
    func invalidateInsight(dedupeKey: String, deletedAt: Date = Date()) -> Bool {
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
            return insight.markedDeleted(at: deletedAt)
        }

        guard didInvalidate else { return false }
        applyVisibleState()
        guard persist() else {
            allInsights = previousAllInsights
            applyVisibleState()
            return false
        }
        return true
    }

    @discardableResult
    func invalidateInsightsReferencingWorkout(id: UUID, deletedAt: Date = Date()) -> Int {
        let previousAllInsights = allInsights
        var invalidatedCount = 0
        allInsights = allInsights.map { insight in
            guard !insight.isDeleted,
                  isVisible(insight),
                  insight.evidence.contains(where: { $0.workoutId == id })
            else { return insight }

            invalidatedCount += 1
            return insight.markedDeleted(at: deletedAt)
        }

        guard invalidatedCount > 0 else { return 0 }
        applyVisibleState()
        guard persist() else {
            allInsights = previousAllInsights
            applyVisibleState()
            return 0
        }
        return invalidatedCount
    }

    func clearForDebug() {
        allInsights.removeAll { isVisible($0) }
        allDeliveryRecords = allDeliveryRecords.filter { !isVisible($0.value) }
        allEngagementRecords = allEngagementRecords.filter { !isVisible($0.value) }
        applyVisibleState()
        persist()
    }

    @discardableResult
    func claimLocalDataForAccount(id accountId: String) -> Bool {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            persistenceError = "Account id is required before local insight data can be claimed."
            return false
        }
        let hasClaimableData = allInsights.contains { $0.accountId == nil } ||
            allDeliveryRecords.values.contains { $0.accountId == nil } ||
            allEngagementRecords.values.contains { $0.accountId == nil }
        guard hasClaimableData else { return true }

        let previousAllInsights = allInsights
        let previousAllDeliveryRecords = allDeliveryRecords
        let previousAllEngagementRecords = allEngagementRecords

        allInsights = dedupedInsightsByStorageKey(
            allInsights.map { insight in
                insight.accountId == nil ? insight.withAccountId(normalizedAccountId) : insight
            }
        )
        allDeliveryRecords = bestDeliveryRecordsByStorageKey(
            allDeliveryRecords.values.map { record in
                record.accountId == nil ? record.withAccountId(normalizedAccountId) : record
            }
        )
        allEngagementRecords = bestEngagementRecordsByStorageKey(
            allEngagementRecords.values.map { record in
                record.accountId == nil ? record.withAccountId(normalizedAccountId) : record
            }
        )
        applyVisibleState()

        guard persist() else {
            allInsights = previousAllInsights
            allDeliveryRecords = previousAllDeliveryRecords
            allEngagementRecords = previousAllEngagementRecords
            applyVisibleState()
            return false
        }
        return true
    }
}

private extension InsightStore {
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
        now: Date
    ) {
        var byKey = bestInsightsByDedupeKey(allInsights.filter { belongsToCurrentAccount($0) })
        for insight in insights where !insight.isExpired(now: now) && !insight.evidence.isEmpty {
            let accountStampedInsight = insight.withAccountId(currentAccountId)
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
            retainedInsightKeys.contains(element.key) ||
                element.value.lastPresentedAt > staleDeliveryCutoff(now: now)
        }
        applyVisibleState()
    }

    func recordPresented(
        _ insight: AIInsight,
        on surface: InsightSurface,
        now: Date
    ) {
        let key = storageKey(accountId: currentAccountId, dedupeKey: insight.dedupeKey)
        if var record = allDeliveryRecords[key] {
            record.recordPresentation(at: now, surface: surface)
            allDeliveryRecords[key] = record.withAccountId(currentAccountId)
        } else {
            allDeliveryRecords[key] = InsightDeliveryRecord(
                accountId: currentAccountId,
                dedupeKey: insight.dedupeKey,
                presentedAt: now,
                surface: surface
            )
        }
        applyVisibleState()
    }

    func recordPresented(
        dedupeKey: String,
        on surface: InsightSurface,
        now: Date
    ) {
        let key = storageKey(accountId: currentAccountId, dedupeKey: dedupeKey)
        if var record = allDeliveryRecords[key] {
            record.recordPresentation(at: now, surface: surface)
            allDeliveryRecords[key] = record.withAccountId(currentAccountId)
        } else {
            allDeliveryRecords[key] = InsightDeliveryRecord(
                accountId: currentAccountId,
                dedupeKey: dedupeKey,
                presentedAt: now,
                surface: surface
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

    @discardableResult
    func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let snapshot = PersistedInsightStoreSnapshot(
                sourcePolicyVersion: AIInsight.currentSourcePolicyVersion,
                savedAt: Date(),
                recentInsights: allInsights,
                deliveryRecords: Array(allDeliveryRecords.values),
                engagementRecords: Array(allEngagementRecords.values)
            )
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Could not save coach insights: \(error.localizedDescription)"
            return false
        }
    }

    static func defaultInsightURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("CoachInsights.json")
    }

    func applyVisibleState() {
        recentInsights = bestInsightsByDedupeKey(allInsights.filter { isVisible($0) })
            .values
            .sorted { $0.createdAt > $1.createdAt }
        deliveryRecords = bestDeliveryRecordsByDedupeKey(
            allDeliveryRecords.values.filter { isVisible($0) }
        )
        engagementRecords = bestEngagementRecordsByDedupeKey(
            allEngagementRecords.values.filter { isVisible($0) }
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
                result[key] = mergedDeliveryRecord(existing, record)
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
                result[key] = existing.merged(with: record)
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
                result[record.dedupeKey] = mergedDeliveryRecord(existing, record)
            } else {
                result[record.dedupeKey] = record
            }
        }
    }

    func mergedDeliveryRecord(
        _ lhs: InsightDeliveryRecord,
        _ rhs: InsightDeliveryRecord
    ) -> InsightDeliveryRecord {
        var merged = lhs
        merged.firstPresentedAt = min(lhs.firstPresentedAt, rhs.firstPresentedAt)
        merged.lastPresentedAt = max(lhs.lastPresentedAt, rhs.lastPresentedAt)
        merged.presentationCount = max(lhs.presentationCount + rhs.presentationCount, 1)
        merged.surfaceLastPresentedAt = lhs.surfaceLastPresentedAt
        for (surface, date) in rhs.surfaceLastPresentedAt {
            if let existingDate = merged.surfaceLastPresentedAt[surface] {
                merged.surfaceLastPresentedAt[surface] = max(existingDate, date)
            } else {
                merged.surfaceLastPresentedAt[surface] = date
            }
        }
        return merged
    }

    func bestEngagementRecordsByDedupeKey(
        _ records: [InsightEngagementRecord]
    ) -> [String: InsightEngagementRecord] {
        records.reduce(into: [String: InsightEngagementRecord]()) { result, record in
            if let existing = result[record.dedupeKey] {
                result[record.dedupeKey] = existing.merged(with: record)
            } else {
                result[record.dedupeKey] = record
            }
        }
    }

    func removeInsightsForDebug(
        dedupeKeys: Set<String>,
        referencingWorkoutIds workoutIds: Set<UUID>,
        shouldPersist: Bool
    ) -> Bool {
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
        guard persist() else {
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
