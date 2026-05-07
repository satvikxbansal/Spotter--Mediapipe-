import Foundation
import Combine

nonisolated struct InsightDeliveryRecord: Codable, Equatable {
    let dedupeKey: String
    var firstPresentedAt: Date
    var lastPresentedAt: Date
    var presentationCount: Int
    var surfaceLastPresentedAt: [String: Date]

    init(
        dedupeKey: String,
        presentedAt: Date,
        surface: InsightSurface
    ) {
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
}

nonisolated enum InsightEngagementKind: String, Codable, CaseIterable, Hashable {
    case opened
    case dismissed
    case helpful
    case notHelpful
}

nonisolated struct InsightEngagementRecord: Codable, Equatable {
    let dedupeKey: String
    private var engagementCounts: [String: Int]
    private var lastEngagementDates: [String: Date]

    init(
        dedupeKey: String,
        engagementCounts: [String: Int] = [:],
        lastEngagementDates: [String: Date] = [:]
    ) {
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
    private var deliveryRecords: [String: InsightDeliveryRecord] = [:]
    private var engagementRecords: [String: InsightEngagementRecord] = [:]
    private let ranker = InsightRanker()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultInsightURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    nonisolated deinit {}

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
                .filter { !$0.isExpired(now: now) && !$0.evidence.isEmpty && $0.surfaces.contains(surface) }
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
                .filter { !$0.isExpired(now: now) && $0.surfaces.contains(surface) }
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
        if var record = engagementRecords[insight.dedupeKey] {
            record.record(kind, at: now)
            engagementRecords[insight.dedupeKey] = record
        } else {
            var record = InsightEngagementRecord(dedupeKey: insight.dedupeKey)
            record.record(kind, at: now)
            engagementRecords[insight.dedupeKey] = record
        }
        persist()
    }

    func clearForDebug() {
        recentInsights = []
        deliveryRecords = [:]
        engagementRecords = [:]
        persist()
    }
}

private extension InsightStore {
    func fetchCandidates(
        for surface: InsightSurface,
        profile: UserProfile,
        now: Date
    ) -> [AIInsight] {
        recentInsights
            .filter { !$0.isExpired(now: now) && $0.surfaces.contains(surface) }
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
        var byKey = bestInsightsByDedupeKey(recentInsights)
        for insight in insights where !insight.isExpired(now: now) && !insight.evidence.isEmpty {
            if let existing = byKey[insight.dedupeKey] {
                if insight.userValueScore >= existing.userValueScore || insight.createdAt > existing.createdAt {
                    byKey[insight.dedupeKey] = insight
                }
            } else {
                byKey[insight.dedupeKey] = insight
            }
        }

        recentInsights = byKey.values
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.userValueScore > $1.userValueScore
                }
                return $0.createdAt > $1.createdAt
            }
            .prefix(80)
            .map { $0 }
    }

    func expireStale(now: Date) {
        let retainedKeys = Set(
            recentInsights
                .filter { !$0.isExpired(now: now) }
                .map(\.dedupeKey)
        )
        recentInsights = recentInsights.filter { retainedKeys.contains($0.dedupeKey) }
        deliveryRecords = deliveryRecords.filter { retainedKeys.contains($0.key) || $0.value.lastPresentedAt > staleDeliveryCutoff(now: now) }
    }

    func recordPresented(
        _ insight: AIInsight,
        on surface: InsightSurface,
        now: Date
    ) {
        if var record = deliveryRecords[insight.dedupeKey] {
            record.recordPresentation(at: now, surface: surface)
            deliveryRecords[insight.dedupeKey] = record
        } else {
            deliveryRecords[insight.dedupeKey] = InsightDeliveryRecord(
                dedupeKey: insight.dedupeKey,
                presentedAt: now,
                surface: surface
            )
        }
    }

    func recordPresented(
        dedupeKey: String,
        on surface: InsightSurface,
        now: Date
    ) {
        if var record = deliveryRecords[dedupeKey] {
            record.recordPresentation(at: now, surface: surface)
            deliveryRecords[dedupeKey] = record
        } else {
            deliveryRecords[dedupeKey] = InsightDeliveryRecord(
                dedupeKey: dedupeKey,
                presentedAt: now,
                surface: surface
            )
        }
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
            recentInsights = bestInsightsByDedupeKey(snapshot.recentInsights)
                .values
                .sorted { $0.createdAt > $1.createdAt }
            deliveryRecords = bestDeliveryRecordsByDedupeKey(snapshot.deliveryRecords)
            engagementRecords = bestEngagementRecordsByDedupeKey(snapshot.engagementRecords)
            persistenceError = nil
        } catch {
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
                recentInsights: recentInsights,
                deliveryRecords: Array(deliveryRecords.values),
                engagementRecords: Array(engagementRecords.values)
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

    func bestInsightsByDedupeKey(_ insights: [AIInsight]) -> [String: AIInsight] {
        insights.reduce(into: [String: AIInsight]()) { result, insight in
            guard !insight.evidence.isEmpty,
                  insight.sourcePolicyVersion == AIInsight.currentSourcePolicyVersion
            else { return }
            if let existing = result[insight.dedupeKey] {
                if insight.userValueScore > existing.userValueScore ||
                    (insight.userValueScore == existing.userValueScore && insight.createdAt > existing.createdAt) {
                    result[insight.dedupeKey] = insight
                }
            } else {
                result[insight.dedupeKey] = insight
            }
        }
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
}
