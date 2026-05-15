import Foundation

@MainActor
final class FirestoreTrophyRepository: TrophyRepository {
    private static let observerDebounceNanoseconds: UInt64 = 1_000_000_000

    private let database: any FirestoreDocumentDatabase

    init(database: any FirestoreDocumentDatabase) {
        self.database = database
    }

    func loadTrophyDefinitions() async throws -> [TrophyDefinition] {
        TrophyDefinitionCatalog.all
    }

    func loadTrophyEvents(accountId: String, since: Date?) async throws -> [TrophyUnlockEvent] {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.trophyEventsCollection(uid: uid)
        return try await database.queryDocuments(
            collectionPath: collectionPath,
            filters: activeDocumentFilters(),
            orderBy: "earnedAt",
            descending: false,
            limit: nil
        )
        .compactMap(Self.trophyEvent)
        .filter { event in
            event.accountId == uid && event.syncMetadata.syncState != .conflict
        }
        .filter { event in
            guard let since else { return true }
            return event.authoritativeEarnedAt >= since
        }
        .sorted(by: Self.isEarlierTrophyEvent)
    }

    @discardableResult
    func saveTrophyEvent(_ event: TrophyUnlockEvent, operationId: UUID) async throws -> TrophyUnlockEvent {
        let uid = try FirestoreRepositorySupport.requiredAccountId(event.accountId ?? "")
        let eventId = operationId.uuidString.lowercased()
        let path = try FirestorePathBuilder.trophyEvent(uid: uid, eventId: eventId)
        let eventToWrite = eventForDocument(event, uid: uid, operationId: operationId)

        let outcome = try await database.runTransaction { transaction in
            if let current = try transaction.getDocument(path: path),
               let currentDocument = try? FirestoreRepositorySupport.decode(
                FirestoreTrophyEventDocument.self,
                from: current
               ) {
                let existingEvent = mapFromTrophyEventDocument(currentDocument)
                if existingEvent.accountId == uid,
                   existingEvent.trophyId == eventToWrite.trophyId,
                   existingEvent.earnedAt == eventToWrite.earnedAt {
                    return FirestoreTrophySaveOutcome.saved(existingEvent)
                }
                throw RepositoryError.conflict(
                    serverVersion: FirestoreRepositorySupport.serverVersion(
                        from: current,
                        serverDate: currentDocument.serverEarnedAt,
                        fallbackDate: currentDocument.earnedAt
                    ),
                    localVersion: eventToWrite.syncMetadata.serverVersion
                )
            }

            var payload = try FirestoreEncodingHelpers.payload(
                from: mapToTrophyEventDocument(eventToWrite)
            )
            payload["deletedAt"] = NSNull()
            payload["serverEarnedAt"] = NSNull()
            try FirestorePrivacyValidator.validate(payload)
            try transaction.setData(payload, path: path, merge: false)
            return FirestoreTrophySaveOutcome.written
        }

        guard let trophyOutcome = outcome as? FirestoreTrophySaveOutcome else {
            throw RepositoryError.backendUnavailable
        }

        switch trophyOutcome {
        case .saved(let savedEvent):
            return savedEvent
        case .written:
            guard let storedDocument = try await database.getDocument(path: path),
                  let savedEvent = Self.trophyEvent(from: storedDocument) else {
                throw RepositoryError.notFound
            }
            return savedEvent
        }
    }

    func loadTrophyProgress(accountId: String) async throws -> [TrophyProgress] {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let events = try await loadTrophyEvents(accountId: uid, since: nil)
        if let cacheProgress = try await cachedProgressIfFresh(uid: uid, events: events) {
            return cacheProgress
        }
        return Self.progressDerivedFromEvents(events, accountId: uid)
    }

    func observeTrophyEvents(accountId: String) async throws -> AsyncStream<[TrophyUnlockEvent]> {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.trophyEventsCollection(uid: uid)

        return AsyncStream { continuation in
            var debounceTask: Task<Void, Never>?
            let listener = database.listenCollection(
                collectionPath: collectionPath,
                filters: activeDocumentFilters(),
                orderBy: "earnedAt",
                descending: false,
                limit: nil
            ) { result in
                debounceTask?.cancel()
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.observerDebounceNanoseconds)
                    guard !Task.isCancelled else { return }
                    switch result {
                    case .success(let storedDocuments):
                        let events = storedDocuments
                            .compactMap(Self.trophyEvent)
                            .filter { $0.accountId == uid }
                            .sorted(by: Self.isEarlierTrophyEvent)
                        continuation.yield(events)
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

    private func cachedProgressIfFresh(
        uid: String,
        events: [TrophyUnlockEvent]
    ) async throws -> [TrophyProgress]? {
        let path = try FirestorePathBuilder.trophyProgressCache(uid: uid)
        guard let storedDocument = try await database.getDocument(path: path) else {
            return nil
        }
        let document = try FirestoreRepositorySupport.decode(
            FirestoreTrophyProgressCacheDocument.self,
            from: storedDocument
        )
        guard document.accountId == uid,
              document.deletedAt == nil,
              document.catalogVersion == TrophyDefinitionCatalog.version else {
            return nil
        }
        let latestEventDate = events
            .filter { !$0.isRetracted }
            .map(\.authoritativeEarnedAt)
            .max()
        if let latestEventDate, document.generatedAt < latestEventDate {
            return nil
        }
        return mapFromTrophyProgressCacheDocument(document).progress
    }

    private func eventForDocument(
        _ event: TrophyUnlockEvent,
        uid: String,
        operationId: UUID
    ) -> TrophyUnlockEvent {
        TrophyUnlockEvent(
            id: operationId,
            accountId: uid,
            dedupeKey: event.dedupeKey,
            trophyId: event.trophyId,
            title: event.title,
            subtitle: event.subtitle,
            earnedAt: event.earnedAt,
            serverEarnedAt: event.serverEarnedAt,
            retractedAt: event.retractedAt,
            reason: event.reason,
            celebrationStyle: event.celebrationStyle,
            syncMetadata: event.syncMetadata.markedForLocalMutation(
                accountId: uid,
                operationId: operationId,
                now: event.earnedAt
            )
        )
    }

    private nonisolated static func trophyEvent(
        from storedDocument: FirestoreStoredDocument
    ) -> TrophyUnlockEvent? {
        guard let document = try? FirestoreRepositorySupport.decode(
            FirestoreTrophyEventDocument.self,
            from: storedDocument
        ) else {
            return nil
        }
        var event = mapFromTrophyEventDocument(document)
        event.syncMetadata.serverVersion = FirestoreRepositorySupport.serverVersion(
            from: storedDocument,
            serverDate: document.serverEarnedAt,
            fallbackDate: document.earnedAt
        )
        return event
    }

    private nonisolated static func progressDerivedFromEvents(
        _ events: [TrophyUnlockEvent],
        accountId: String
    ) -> [TrophyProgress] {
        let activeEventsByTrophyId = Dictionary(grouping: events.filter { !$0.isRetracted }, by: \.trophyId)
            .compactMapValues { events in
                events.min(by: isEarlierTrophyEvent)
            }
        let generatedAt = events.map(\.authoritativeEarnedAt).max() ?? Date()

        return TrophyDefinitionCatalog.all.map { definition in
            if definition.isComingSoon {
                return TrophyProgress(
                    trophyId: definition.id,
                    currentValue: 0,
                    targetValue: definition.targetValue,
                    earned: false,
                    earnedAt: nil,
                    lastUpdatedAt: generatedAt,
                    confidence: .unavailable,
                    progressLabel: "Coming Soon",
                    accountId: accountId,
                    syncMetadata: syncedMetadata(accountId: accountId, date: generatedAt)
                )
            }

            if let event = activeEventsByTrophyId[definition.id] {
                let earnedAt = event.authoritativeEarnedAt
                return TrophyProgress(
                    trophyId: definition.id,
                    currentValue: definition.targetValue,
                    targetValue: definition.targetValue,
                    earned: true,
                    earnedAt: earnedAt,
                    lastUpdatedAt: earnedAt,
                    confidence: .exact,
                    progressLabel: "Earned",
                    accountId: accountId,
                    syncMetadata: syncedMetadata(accountId: accountId, date: earnedAt)
                )
            }

            return TrophyProgress(
                trophyId: definition.id,
                currentValue: 0,
                targetValue: definition.targetValue,
                earned: false,
                earnedAt: nil,
                lastUpdatedAt: generatedAt,
                confidence: definition.dataRequirement == .none ? .exact : .estimated,
                progressLabel: "0/\(format(definition.targetValue)) \(definition.unit)",
                accountId: accountId,
                syncMetadata: syncedMetadata(accountId: accountId, date: generatedAt)
            )
        }
    }

    private nonisolated static func syncedMetadata(accountId: String, date: Date) -> SyncMetadata {
        SyncMetadata(
            localUpdatedAt: date,
            lastSyncedAt: date,
            serverVersion: nil,
            syncState: .synced,
            pendingOperationId: nil
        )
    }

    private nonisolated static func isEarlierTrophyEvent(
        _ lhs: TrophyUnlockEvent,
        _ rhs: TrophyUnlockEvent
    ) -> Bool {
        if lhs.authoritativeEarnedAt != rhs.authoritativeEarnedAt {
            return lhs.authoritativeEarnedAt < rhs.authoritativeEarnedAt
        }
        if lhs.earnedAt != rhs.earnedAt {
            return lhs.earnedAt < rhs.earnedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private nonisolated static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

private enum FirestoreTrophySaveOutcome {
    case saved(TrophyUnlockEvent)
    case written
}

private nonisolated func activeDocumentFilters() -> [FirestoreQueryFilter] {
    [FirestoreQueryFilter(field: "deletedAt", value: NSNull())]
}
