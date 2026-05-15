import FirebaseFirestore
import Foundation

@MainActor
final class FirestoreInsightRepository: InsightRepository {
    private static let observerDebounceNanoseconds: UInt64 = 500_000_000

    private let database: any FirestoreDocumentDatabase

    init(database: any FirestoreDocumentDatabase) {
        self.database = database
    }

    @discardableResult
    func saveInsights(_ insights: [AIInsight], operationId: UUID) async throws -> [AIInsight] {
        guard !insights.isEmpty else { return [] }
        let uid = try Self.requiredSingleAccountId(in: insights)

        let outcome = try await database.runTransaction { transaction in
            var savedInsights: [AIInsight] = []
            for insight in insights {
                let path = try FirestorePathBuilder.insight(uid: uid, dedupeKey: insight.dedupeKey)
                let current = try transaction.getDocument(path: path)
                if let current,
                   let currentDocument = try? FirestoreRepositorySupport.decode(
                    FirestoreInsightDocument.self,
                    from: current
                   ) {
                    let existingInsight = mapFromInsightDocument(currentDocument)
                    if currentDocument.operationId == operationId ||
                        currentDocument.syncMetadata?.pendingOperationId.flatMap(UUID.init(uuidString:)) == operationId {
                        savedInsights.append(existingInsight)
                        continue
                    }
                    guard Self.shouldWrite(candidate: insight, over: existingInsight) else {
                        savedInsights.append(existingInsight)
                        continue
                    }
                }

                let insightToWrite = self.insightForDocument(
                    insight,
                    uid: uid,
                    operationId: operationId
                )
                var payload = try FirestoreEncodingHelpers.payload(
                    from: mapToInsightDocument(insightToWrite)
                )
                if insightToWrite.deletedAt == nil {
                    payload["deletedAt"] = NSNull()
                }
                if insightToWrite.expiresAt == nil {
                    payload["expiresAt"] = NSNull()
                }
                if current != nil {
                    payload.removeValue(forKey: "serverCreatedAt")
                }
                try FirestorePrivacyValidator.validate(payload)
                try transaction.setData(payload, path: path, merge: true)
                savedInsights.append(insightToWrite)
            }
            return FirestoreInsightSaveOutcome.saved(savedInsights)
        }

        let fallback = (outcome as? FirestoreInsightSaveOutcome)?.insights ?? []
        var loadedInsights: [AIInsight] = []
        for insight in insights {
            let path = try FirestorePathBuilder.insight(uid: uid, dedupeKey: insight.dedupeKey)
            if let storedDocument = try await database.getDocument(path: path),
               let loadedInsight = Self.insight(from: storedDocument) {
                loadedInsights.append(loadedInsight)
            }
        }
        return loadedInsights.isEmpty ? fallback : loadedInsights
    }

    func loadRecentInsights(accountId: String, limit: Int) async throws -> [AIInsight] {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.insightsCollection(uid: uid)
        let now = Date()
        return try await database.queryDocuments(
            collectionPath: collectionPath,
            filters: activeDocumentFilters(),
            orderBy: "createdAt",
            descending: true,
            limit: nil
        )
        .compactMap(Self.insight)
        .filter { $0.accountId == uid && !$0.isDeleted && !$0.isExpired(now: now) }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.dedupeKey < rhs.dedupeKey
            }
            return lhs.createdAt > rhs.createdAt
        }
        .prefix(max(limit, 0))
        .map { $0 }
    }

    func observeRecentInsights(accountId: String, limit: Int) async throws -> AsyncStream<[AIInsight]> {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.insightsCollection(uid: uid)

        return AsyncStream { continuation in
            var debounceTask: Task<Void, Never>?
            let listener = database.listenCollection(
                collectionPath: collectionPath,
                filters: [],
                orderBy: "createdAt",
                descending: true,
                limit: nil
            ) { result in
                debounceTask?.cancel()
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.observerDebounceNanoseconds)
                    guard !Task.isCancelled else { return }
                    switch result {
                    case .success(let storedDocuments):
                        let now = Date()
                        let insights = storedDocuments
                            .compactMap(Self.insight)
                            .filter { $0.accountId == uid && ($0.isDeleted || !$0.isExpired(now: now)) }
                            .sorted { $0.createdAt > $1.createdAt }
                        continuation.yield(Array(insights.prefix(max(limit, 0))))
                    case .failure:
                        continuation.finish()
                    }
                }
            }
            continuation.onTermination = { _ in
                debounceTask?.cancel()
                listener.remove()
            }
        }
    }

    @discardableResult
    func saveDeliveryRecord(
        _ record: InsightDeliveryRecord,
        operationId: UUID
    ) async throws -> InsightDeliveryRecord {
        let uid = try FirestoreRepositorySupport.requiredAccountId(record.accountId ?? "")
        let path = try FirestorePathBuilder.insightDelivery(uid: uid, dedupeKey: record.dedupeKey)
        let activityDate = latestDate(record.deletedAt, record.lastPresentedAt) ?? record.lastPresentedAt
        let recordToWrite = record.withAccountId(uid, operationId: operationId, now: activityDate)

        let outcome = try await database.runTransaction { transaction in
            let current = try transaction.getDocument(path: path)
            var mergedRecord = recordToWrite
            if let current,
               let currentDocument = try? FirestoreRepositorySupport.decode(
                FirestoreInsightDeliveryDocument.self,
                from: current
               ) {
                let existingRecord = mapFromInsightDeliveryDocument(currentDocument)
                if currentDocument.operationId == operationId ||
                    currentDocument.syncMetadata?.pendingOperationId.flatMap(UUID.init(uuidString:)) == operationId {
                    return FirestoreDeliverySaveOutcome.saved(existingRecord)
                }
                mergedRecord = InsightDeliveryRecord.merged(
                    local: existingRecord,
                    remote: recordToWrite
                )
                if recordToWrite.deletedAt == nil {
                    mergedRecord = mergedRecord.restored(operationId: operationId, now: activityDate)
                }
            }

            var payload = try FirestoreEncodingHelpers.payload(
                from: mapToInsightDeliveryDocument(mergedRecord)
            )
            if mergedRecord.deletedAt == nil {
                payload["deletedAt"] = NSNull()
            }
            try FirestorePrivacyValidator.validate(payload)
            try transaction.setData(payload, path: path, merge: true)
            return FirestoreDeliverySaveOutcome.saved(mergedRecord)
        }

        guard let deliveryOutcome = outcome as? FirestoreDeliverySaveOutcome else {
            throw RepositoryError.backendUnavailable
        }
        return deliveryOutcome.record
    }

    func loadDeliveryRecords(accountId: String) async throws -> [InsightDeliveryRecord] {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.insightDeliveryCollection(uid: uid)
        return try await database.queryDocuments(
            collectionPath: collectionPath,
            filters: [],
            orderBy: "lastPresentedAt",
            descending: true,
            limit: nil
        )
        .compactMap(Self.deliveryRecord)
        .filter { $0.accountId == uid }
    }

    func observeDeliveryRecords(accountId: String) async throws -> AsyncStream<[InsightDeliveryRecord]> {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.insightDeliveryCollection(uid: uid)
        return observeCollection(
            collectionPath: collectionPath,
            orderBy: "lastPresentedAt",
            descending: true,
            mapper: Self.deliveryRecord(from:)
        ) { $0.accountId == uid }
    }

    @discardableResult
    func saveEngagementRecord(
        _ record: InsightEngagementRecord,
        operationId: UUID
    ) async throws -> InsightEngagementRecord {
        let uid = try FirestoreRepositorySupport.requiredAccountId(record.accountId ?? "")
        let path = try FirestorePathBuilder.insightEngagement(uid: uid, dedupeKey: record.dedupeKey)
        let activityDate = latestDate(record.deletedAt, record.latestEngagedAt()) ?? Date()
        let recordToWrite = record.withAccountId(uid, operationId: operationId, now: activityDate)

        let outcome = try await database.runTransaction { transaction in
            let current = try transaction.getDocument(path: path)
            var mergedRecord = recordToWrite
            if let current,
               let currentDocument = try? FirestoreRepositorySupport.decode(
                FirestoreInsightEngagementDocument.self,
                from: current
               ) {
                let existingRecord = mapFromInsightEngagementDocument(currentDocument)
                if currentDocument.operationId == operationId ||
                    currentDocument.syncMetadata?.pendingOperationId.flatMap(UUID.init(uuidString:)) == operationId {
                    return FirestoreEngagementSaveOutcome.saved(existingRecord)
                }
                mergedRecord = existingRecord.merged(with: recordToWrite)
                if recordToWrite.deletedAt == nil {
                    mergedRecord = mergedRecord.restored(operationId: operationId, now: activityDate)
                }
            }

            var payload = try FirestoreEncodingHelpers.payload(
                from: mapToInsightEngagementDocument(mergedRecord)
            )
            if mergedRecord.deletedAt == nil {
                payload["deletedAt"] = NSNull()
            }
            try FirestorePrivacyValidator.validate(payload)
            try transaction.setData(payload, path: path, merge: true)
            return FirestoreEngagementSaveOutcome.saved(mergedRecord)
        }

        guard let engagementOutcome = outcome as? FirestoreEngagementSaveOutcome else {
            throw RepositoryError.backendUnavailable
        }
        return engagementOutcome.record
    }

    func loadEngagementRecords(accountId: String) async throws -> [InsightEngagementRecord] {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.insightEngagementCollection(uid: uid)
        return try await database.queryDocuments(
            collectionPath: collectionPath,
            filters: [],
            orderBy: nil,
            descending: true,
            limit: nil
        )
        .compactMap(Self.engagementRecord)
        .filter { $0.accountId == uid }
    }

    func observeEngagementRecords(accountId: String) async throws -> AsyncStream<[InsightEngagementRecord]> {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.insightEngagementCollection(uid: uid)
        return observeCollection(
            collectionPath: collectionPath,
            orderBy: nil,
            descending: true,
            mapper: Self.engagementRecord(from:)
        ) { $0.accountId == uid }
    }

    func invalidateInsight(accountId: String, dedupeKey: String, operationId: UUID) async throws {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let path = try FirestorePathBuilder.insight(uid: uid, dedupeKey: dedupeKey)
        let now = Date()
        let nowString = FirestoreVersionStrings.string(from: now)
        let payload: [String: Any] = [
            "deletedAt": FieldValue.serverTimestamp(),
            "operationId": operationId.uuidString.lowercased(),
            "syncMetadata": [
                "localUpdatedAt": nowString,
                "lastSyncedAt": NSNull(),
                "serverVersion": NSNull(),
                "syncState": SyncState.pendingUpload.rawValue,
                "pendingOperationId": operationId.uuidString.lowercased()
            ]
        ]
        try FirestorePrivacyValidator.validate(payload)
        try await database.runTransaction { transaction in
            let current = try transaction.getDocument(path: path)
            if let current,
               let currentDocument = try? FirestoreRepositorySupport.decode(
                FirestoreInsightDocument.self,
                from: current
            ),
               currentDocument.operationId == operationId ||
                currentDocument.syncMetadata?.pendingOperationId.flatMap(UUID.init(uuidString:)) == operationId {
                return nil
            }
            var tombstonePayload = payload
            if current == nil {
                tombstonePayload["accountId"] = uid
                tombstonePayload["dedupeKey"] = dedupeKey
            }
            try FirestorePrivacyValidator.validate(tombstonePayload)
            try transaction.setData(tombstonePayload, path: path, merge: true)
            return nil
        }
    }

    private func observeCollection<T>(
        collectionPath: String,
        orderBy: String?,
        descending: Bool,
        mapper: @escaping (FirestoreStoredDocument) -> T?,
        isIncluded: @escaping (T) -> Bool
    ) -> AsyncStream<[T]> {
        AsyncStream { continuation in
            var debounceTask: Task<Void, Never>?
            let listener = database.listenCollection(
                collectionPath: collectionPath,
                filters: [],
                orderBy: orderBy,
                descending: descending,
                limit: nil
            ) { result in
                debounceTask?.cancel()
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.observerDebounceNanoseconds)
                    guard !Task.isCancelled else { return }
                    switch result {
                    case .success(let storedDocuments):
                        continuation.yield(storedDocuments.compactMap(mapper).filter(isIncluded))
                    case .failure:
                        continuation.finish()
                    }
                }
            }
            continuation.onTermination = { _ in
                debounceTask?.cancel()
                listener.remove()
            }
        }
    }

    private nonisolated static func requiredSingleAccountId(in insights: [AIInsight]) throws -> String {
        let accountIds = Set(insights.compactMap { AccountOwnership.normalizedAccountId($0.accountId) })
        guard accountIds.count == 1,
              let uid = accountIds.first else {
            throw RepositoryError.accountMissing
        }
        return uid
    }

    private nonisolated static func shouldWrite(candidate: AIInsight, over existing: AIInsight) -> Bool {
        if candidate.sourcePolicyVersion != existing.sourcePolicyVersion {
            return candidate.sourcePolicyVersion.localizedStandardCompare(
                existing.sourcePolicyVersion
            ) == .orderedDescending
        }
        if candidate.isDeleted != existing.isDeleted {
            return candidate.isDeleted
        }
        if candidate.userValueScore != existing.userValueScore {
            return candidate.userValueScore > existing.userValueScore
        }
        return candidate.createdAt >= existing.createdAt
    }

    private nonisolated static func insight(from storedDocument: FirestoreStoredDocument) -> AIInsight? {
        guard let document = try? FirestoreRepositorySupport.decode(
            FirestoreInsightDocument.self,
            from: storedDocument
        ) else {
            return nil
        }
        var insight = mapFromInsightDocument(document)
        insight.syncMetadata.serverVersion = FirestoreRepositorySupport.serverVersion(
            from: storedDocument,
            serverDate: document.serverCreatedAt,
            fallbackDate: document.createdAt
        )
        return insight
    }

    private nonisolated static func deliveryRecord(
        from storedDocument: FirestoreStoredDocument
    ) -> InsightDeliveryRecord? {
        guard let document = try? FirestoreRepositorySupport.decode(
            FirestoreInsightDeliveryDocument.self,
            from: storedDocument
        ) else {
            return nil
        }
        var record = mapFromInsightDeliveryDocument(document)
        record.syncMetadata.serverVersion = FirestoreRepositorySupport.serverVersion(
            from: storedDocument,
            serverDate: document.serverLastPresentedAt,
            fallbackDate: document.lastPresentedAt
        )
        return record
    }

    private nonisolated static func engagementRecord(
        from storedDocument: FirestoreStoredDocument
    ) -> InsightEngagementRecord? {
        guard let document = try? FirestoreRepositorySupport.decode(
            FirestoreInsightEngagementDocument.self,
            from: storedDocument
        ) else {
            return nil
        }
        var record = mapFromInsightEngagementDocument(document)
        record.syncMetadata.serverVersion = FirestoreRepositorySupport.serverVersion(
            from: storedDocument,
            serverDate: document.serverLastEngagedAt,
            fallbackDate: document.lastEngagementDates.values.max() ?? document.deletedAt ?? Date()
        )
        return record
    }

    private nonisolated func insightForDocument(
        _ insight: AIInsight,
        uid: String,
        operationId: UUID
    ) -> AIInsight {
        insight.withAccountId(uid, operationId: operationId, now: insight.createdAt)
    }
}

private enum FirestoreInsightSaveOutcome {
    case saved([AIInsight])

    var insights: [AIInsight] {
        switch self {
        case .saved(let insights):
            return insights
        }
    }
}

private enum FirestoreDeliverySaveOutcome {
    case saved(InsightDeliveryRecord)

    var record: InsightDeliveryRecord {
        switch self {
        case .saved(let record):
            return record
        }
    }
}

private enum FirestoreEngagementSaveOutcome {
    case saved(InsightEngagementRecord)

    var record: InsightEngagementRecord {
        switch self {
        case .saved(let record):
            return record
        }
    }
}

private nonisolated func activeDocumentFilters() -> [FirestoreQueryFilter] {
    [FirestoreQueryFilter(field: "deletedAt", value: NSNull())]
}

private nonisolated func latestDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
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
