import FirebaseFirestore
import Foundation

@MainActor
final class FirestoreWorkoutRepository: WorkoutRepository, WorkoutTombstoneRepository {
    private let database: any FirestoreDocumentDatabase

    init(database: any FirestoreDocumentDatabase) {
        self.database = database
    }

    @discardableResult
    func saveWorkoutSummary(_ summary: WorkoutSessionSummary, operationId: UUID) async throws -> WorkoutSessionSummary {
        let uid = try FirestoreRepositorySupport.requiredAccountId(summary.accountId ?? "")
        guard summary.accountId == uid else {
            throw RepositoryError.accountMissing
        }

        let workoutPath = try FirestorePathBuilder.workoutDocument(uid: uid, workoutId: summary.id)
        if let current = try await database.getDocument(path: workoutPath),
           let currentDocument = try? FirestoreRepositorySupport.decode(
            FirestoreWorkoutDocument.self,
            from: current
           ),
           currentDocument.operationId == operationId {
            return try await loadWorkout(accountId: uid, id: summary.id)
                ?? Self.syncedWorkout(summary, storedDocument: current, serverDate: currentDocument.serverEndedAt)
        }

        var summaryToWrite = summary
        summaryToWrite.syncMetadata.pendingOperationId = operationId
        summaryToWrite.syncMetadata.syncState = .pendingUpload
        let workoutDocument = mapToWorkoutDocument(summaryToWrite, operationId: operationId)
        let workoutPayload = try Self.workoutPayload(from: workoutDocument)
        let setWrites = try summary.exerciseSummaries.map { setSummary in
            let setId = firestoreWorkoutSetDocumentId(for: setSummary)
            let document = mapToWorkoutSetDocument(
                setSummary,
                accountId: uid,
                workoutId: summary.id,
                setId: setId,
                operationId: operationId
            )
            return try FirestoreWorkoutSetWrite(
                path: FirestorePathBuilder.setDocument(
                    uid: uid,
                    workoutId: summary.id,
                    setId: setId
                ),
                payload: Self.setPayload(from: document)
            )
        }

        try await database.commitBatch { batch in
            try batch.setData(workoutPayload, path: workoutPath, merge: true)
            for setWrite in setWrites {
                try batch.setData(setWrite.payload, path: setWrite.path, merge: true)
            }
        }

        return try await loadWorkout(accountId: uid, id: summary.id)
            ?? summary.markedSynced(lastSyncedAt: Date())
    }

    func loadRecentWorkouts(
        accountId: String,
        limit: Int,
        since: Date?
    ) async throws -> [WorkoutSessionSummary] {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.workoutsCollection(uid: uid)
        let documents = try await database.queryDocuments(
            collectionPath: collectionPath,
            filters: Self.activeWorkoutFilters,
            orderBy: "serverEndedAt",
            descending: true,
            limit: max(limit, 0)
        )

        return try Self.recentWorkouts(
            from: documents,
            limit: limit,
            since: since
        )
    }

    func loadRecentWorkoutTombstones(
        accountId: String,
        limit: Int,
        since: Date?
    ) async throws -> [WorkoutSessionSummary] {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.workoutsCollection(uid: uid)
        let documents = try await database.queryDocuments(
            collectionPath: collectionPath,
            filters: [],
            orderBy: nil,
            descending: true,
            limit: nil
        )

        return try Self.recentWorkoutTombstones(
            from: documents,
            limit: limit,
            since: since
        )
    }

    func loadWorkout(accountId: String, id: UUID) async throws -> WorkoutSessionSummary? {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let workoutPath = try FirestorePathBuilder.workoutDocument(uid: uid, workoutId: id)
        guard let storedWorkout = try await database.getDocument(path: workoutPath) else {
            return nil
        }

        let workoutDocument = try FirestoreRepositorySupport.decode(
            FirestoreWorkoutDocument.self,
            from: storedWorkout
        )
        guard workoutDocument.deletedAt == nil else {
            return nil
        }

        let setDocuments = try await database.queryDocuments(
            collectionPath: FirestorePathBuilder.setsCollection(uid: uid, workoutId: id),
            filters: [],
            orderBy: "setIndex",
            descending: false,
            limit: nil
        )
        .compactMap {
            try? FirestoreRepositorySupport.decode(FirestoreWorkoutSetDocument.self, from: $0)
        }

        return Self.syncedWorkout(
            mapFromWorkoutDocument(workoutDocument, sets: setDocuments),
            storedDocument: storedWorkout,
            serverDate: workoutDocument.serverEndedAt
        )
    }

    func deleteWorkout(accountId: String, id: UUID, operationId: UUID) async throws {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let path = try FirestorePathBuilder.workoutDocument(uid: uid, workoutId: id)
        if let current = try await database.getDocument(path: path),
           Self.hasAppliedDeleteOperation(current, operationId: operationId) {
            return
        }

        let payload = try Self.deletePayload(
            accountId: uid,
            workoutId: id,
            operationId: operationId
        )

        try await database.commitBatch { batch in
            try batch.setData(payload, path: path, merge: true)
        }
    }

    func observeRecentWorkouts(accountId: String, limit: Int) async throws -> AsyncStream<[WorkoutSessionSummary]> {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.workoutsCollection(uid: uid)

        return AsyncStream { continuation in
            let debouncer = FirestoreObserverDebouncer()
            let listener = database.listenQuery(
                collectionPath: collectionPath,
                filters: Self.activeWorkoutFilters,
                orderBy: "serverEndedAt",
                descending: true,
                limit: max(limit, 0)
            ) { result in
                debouncer.schedule(after: FirestoreRepositorySupport.observerDebounceNanoseconds) {
                    switch result {
                    case .success(let storedDocuments):
                        do {
                            continuation.yield(
                                try Self.recentWorkouts(
                                    from: storedDocuments,
                                    limit: limit,
                                    since: nil
                                )
                            )
                        } catch {
                            continuation.finish()
                        }
                    case .failure:
                        continuation.finish()
                    }
                }
            }
            continuation.onTermination = { _ in
                debouncer.cancel()
                listener.remove()
            }
        }
    }

    private nonisolated static var activeWorkoutFilters: [FirestoreQueryFilter] {
        [FirestoreQueryFilter(field: "deletedAt", value: NSNull())]
    }

    private nonisolated static func workoutPayload(
        from document: FirestoreWorkoutDocument
    ) throws -> [String: Any] {
        var payload = try FirestoreEncodingHelpers.payload(from: document)
        if payload["deletedAt"] == nil {
            payload["deletedAt"] = NSNull()
        }
        try FirestorePrivacyValidator.validate(payload)
        return payload
    }

    private nonisolated static func setPayload(
        from document: FirestoreWorkoutSetDocument
    ) throws -> [String: Any] {
        var payload = try FirestoreEncodingHelpers.payload(from: document)
        if payload["deletedAt"] == nil {
            payload["deletedAt"] = NSNull()
        }
        try FirestorePrivacyValidator.validate(payload)
        return payload
    }

    private nonisolated static func deletePayload(
        accountId: String,
        workoutId: UUID,
        operationId: UUID
    ) throws -> [String: Any] {
        let now = Date()
        let nowString = FirestoreVersionStrings.string(from: now)
        let operationIdString = operationId.uuidString.lowercased()
        let payload: [String: Any] = [
            "accountId": accountId,
            "schemaVersion": FirestoreDTOSchema.currentVersion,
            "workoutId": workoutId.uuidString.lowercased(),
            "deletedAt": FieldValue.serverTimestamp(),
            "operationId": operationIdString,
            "syncMetadata": [
                "localUpdatedAt": nowString,
                "lastSyncedAt": NSNull(),
                "serverVersion": NSNull(),
                "syncState": SyncState.pendingUpload.rawValue,
                "pendingOperationId": operationIdString
            ]
        ]
        try FirestorePrivacyValidator.validate(payload)
        return payload
    }

    private nonisolated static func hasAppliedDeleteOperation(
        _ document: FirestoreStoredDocument,
        operationId: UUID
    ) -> Bool {
        document.data["deletedAt"] != nil &&
            (document.data["operationId"] as? String) == operationId.uuidString.lowercased()
    }

    private nonisolated static func recentWorkouts(
        from storedDocuments: [FirestoreStoredDocument],
        limit: Int,
        since: Date?
    ) throws -> [WorkoutSessionSummary] {
        let summaries = try storedDocuments
            .map { storedDocument in
                let document = try FirestoreRepositorySupport.decode(
                    FirestoreWorkoutDocument.self,
                    from: storedDocument
                )
                return syncedWorkout(
                    mapFromWorkoutDocument(document),
                    storedDocument: storedDocument,
                    serverDate: document.serverEndedAt
                )
            }
            .filter { !$0.isDeleted }
            .filter { summary in
                guard let since else { return true }
                return summary.authoritativeEndedAt >= since
            }
            .sorted {
                if $0.authoritativeEndedAt == $1.authoritativeEndedAt {
                    return $0.createdAt > $1.createdAt
                }
                return $0.authoritativeEndedAt > $1.authoritativeEndedAt
            }
        return Array(summaries.prefix(max(limit, 0)))
    }

    private nonisolated static func recentWorkoutTombstones(
        from storedDocuments: [FirestoreStoredDocument],
        limit: Int,
        since: Date?
    ) throws -> [WorkoutSessionSummary] {
        let summaries = try storedDocuments
            .map { storedDocument in
                let document = try FirestoreRepositorySupport.decode(
                    FirestoreWorkoutDocument.self,
                    from: storedDocument
                )
                return syncedWorkout(
                    mapFromWorkoutDocument(document),
                    storedDocument: storedDocument,
                    serverDate: document.serverEndedAt
                )
            }
            .filter(\.isDeleted)
            .filter { summary in
                guard let since else { return true }
                return summary.authoritativeEndedAt >= since
            }
            .sorted {
                if $0.authoritativeEndedAt == $1.authoritativeEndedAt {
                    return $0.createdAt > $1.createdAt
                }
                return $0.authoritativeEndedAt > $1.authoritativeEndedAt
            }
        return Array(summaries.prefix(max(limit, 0)))
    }

    private nonisolated static func syncedWorkout(
        _ summary: WorkoutSessionSummary,
        storedDocument: FirestoreStoredDocument,
        serverDate: Date?
    ) -> WorkoutSessionSummary {
        summary.markedSynced(
            lastSyncedAt: Date(),
            serverVersion: FirestoreRepositorySupport.serverVersion(
                from: storedDocument,
                serverDate: serverDate,
                fallbackDate: summary.createdAt
            )
        )
    }
}

private struct FirestoreWorkoutSetWrite {
    let path: String
    let payload: [String: Any]
}
