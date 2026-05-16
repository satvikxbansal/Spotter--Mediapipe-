import Foundation

@MainActor
final class FirestoreCalibrationRepository: CalibrationRepository {
    private let database: any FirestoreDocumentDatabase

    init(database: any FirestoreDocumentDatabase) {
        self.database = database
    }

    func loadCalibrationRecord(accountId: String) async throws -> CalibrationRecord? {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let path = try FirestorePathBuilder.calibration(uid: uid)
        guard let storedDocument = try await database.getDocument(path: path) else {
            return nil
        }
        return try Self.calibration(from: storedDocument)
    }

    @discardableResult
    func saveCalibrationRecord(_ record: CalibrationRecord, operationId: UUID) async throws -> CalibrationRecord {
        let uid = try FirestoreRepositorySupport.requiredAccountId(record.accountId ?? "")
        let path = try FirestorePathBuilder.calibration(uid: uid)

        let outcome = try await database.runTransaction { transaction in
            let current = try transaction.getDocument(path: path)
            if let current,
               let currentDocument = try? FirestoreRepositorySupport.decode(
                FirestoreCalibrationDocument.self,
                from: current
               ) {
                if currentDocument.operationId == operationId ||
                    currentDocument.syncMetadata?.pendingOperationId.flatMap(UUID.init(uuidString:)) == operationId {
                    return FirestoreCalibrationSaveOutcome.saved(try Self.calibration(from: current))
                }

                let remoteRecord = mapFromCalibrationDocument(currentDocument)
                let winner = Self.preferredCalibrationRecord(local: record, remote: remoteRecord)
                if winner == remoteRecord {
                    return FirestoreCalibrationSaveOutcome.saved(
                        Self.calibration(
                            remoteRecord,
                            storedDocument: current,
                            serverDate: currentDocument.serverCompletedAt
                        )
                    )
                }
            }

            var recordToWrite = record
            recordToWrite.syncMetadata.pendingOperationId = operationId
            let document = mapToCalibrationDocument(recordToWrite)
            let payload = try FirestoreEncodingHelpers.payload(from: document)
            try transaction.setData(payload, path: path, merge: true)
            return FirestoreCalibrationSaveOutcome.written
        }

        guard let calibrationOutcome = outcome as? FirestoreCalibrationSaveOutcome else {
            throw RepositoryError.backendUnavailable
        }

        switch calibrationOutcome {
        case .saved(let savedRecord):
            return savedRecord
        case .written:
            guard let storedDocument = try await database.getDocument(path: path) else {
                throw RepositoryError.notFound
            }
            var savedRecord = try Self.calibration(from: storedDocument)
            savedRecord.syncMetadata.lastSyncedAt = Date()
            savedRecord.syncMetadata.syncState = .synced
            savedRecord.syncMetadata.pendingOperationId = nil
            return savedRecord
        }
    }

    func observeCalibrationRecord(accountId: String) async throws -> AsyncStream<CalibrationRecord?> {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let path = try FirestorePathBuilder.calibration(uid: uid)

        return AsyncStream { continuation in
            let debouncer = FirestoreObserverDebouncer()
            let listener = database.listenDocument(path: path) { result in
                debouncer.schedule(after: FirestoreRepositorySupport.observerDebounceNanoseconds) {
                    switch result {
                    case .success(let storedDocument):
                        do {
                            let record = try storedDocument.map(Self.calibration(from:))
                            continuation.yield(record)
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

    private nonisolated static func preferredCalibrationRecord(
        local: CalibrationRecord,
        remote: CalibrationRecord
    ) -> CalibrationRecord {
        let localCompleted = local.isSuccessfulCalibration
        let remoteCompleted = remote.isSuccessfulCalibration

        switch (localCompleted, remoteCompleted) {
        case (true, false):
            return local
        case (false, true):
            return remote
        default:
            return local.syncMetadata.localUpdatedAt >= remote.syncMetadata.localUpdatedAt
                ? local
                : remote
        }
    }

    private nonisolated static func calibration(
        from storedDocument: FirestoreStoredDocument
    ) throws -> CalibrationRecord {
        let document = try FirestoreRepositorySupport.decode(
            FirestoreCalibrationDocument.self,
            from: storedDocument
        )
        return calibration(
            mapFromCalibrationDocument(document),
            storedDocument: storedDocument,
            serverDate: document.serverCompletedAt
        )
    }

    private nonisolated static func calibration(
        _ record: CalibrationRecord,
        storedDocument: FirestoreStoredDocument,
        serverDate: Date?
    ) -> CalibrationRecord {
        var updatedRecord = record
        updatedRecord.syncMetadata.serverVersion = FirestoreRepositorySupport.serverVersion(
            from: storedDocument,
            serverDate: serverDate,
            fallbackDate: record.completedAt
        )
        return updatedRecord
    }
}

private enum FirestoreCalibrationSaveOutcome {
    case saved(CalibrationRecord)
    case written
}
