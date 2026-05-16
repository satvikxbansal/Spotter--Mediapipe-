import FirebaseFirestore
import Foundation

@MainActor
final class FirestoreThemeRepository: ThemeRepository {
    private let database: any FirestoreDocumentDatabase

    init(database: any FirestoreDocumentDatabase) {
        self.database = database
    }

    func loadTheme(accountId: String) async throws -> SpotterThemeOption {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let path = try FirestorePathBuilder.profileDocument(uid: uid)
        guard let storedDocument = try await database.getDocument(path: path) else {
            throw RepositoryError.notFound
        }
        let document = try FirestoreRepositorySupport.decode(
            FirestoreProfileDocument.self,
            from: storedDocument
        )
        return SpotterThemeOption(rawValue: document.selectedTheme) ?? .hyper
    }

    func saveTheme(_ theme: SpotterThemeOption, accountId: String, operationId: UUID) async throws {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let path = try FirestorePathBuilder.profileDocument(uid: uid)
        let now = Date()

        _ = try await database.runTransaction { transaction in
            guard let current = try transaction.getDocument(path: path) else {
                throw RepositoryError.notFound
            }

            let currentDocument = try FirestoreRepositorySupport.decode(
                FirestoreProfileDocument.self,
                from: current
            )
            if currentDocument.operationId == operationId ||
                currentDocument.syncMetadata?.pendingOperationId.flatMap(UUID.init(uuidString:)) == operationId {
                return nil
            }

            let payload = try Self.themePatchPayload(
                theme: theme,
                operationId: operationId,
                now: now,
                serverVersion: FirestoreRepositorySupport.serverVersion(
                    from: current,
                    serverDate: currentDocument.serverUpdatedAt,
                    fallbackDate: currentDocument.updatedAt
                )
            )
            try transaction.setData(payload, path: path, merge: true)
            return nil
        }
    }

    func observeTheme(accountId: String) async throws -> AsyncStream<SpotterThemeOption> {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let path = try FirestorePathBuilder.profileDocument(uid: uid)

        return AsyncStream { continuation in
            let debouncer = FirestoreObserverDebouncer()
            let listener = database.listenDocument(path: path) { result in
                debouncer.schedule(after: FirestoreRepositorySupport.observerDebounceNanoseconds) {
                    switch result {
                    case .success(let storedDocument):
                        do {
                            guard let storedDocument else { return }
                            let document = try FirestoreRepositorySupport.decode(
                                FirestoreProfileDocument.self,
                                from: storedDocument
                            )
                            continuation.yield(SpotterThemeOption(rawValue: document.selectedTheme) ?? .hyper)
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

    private nonisolated static func themePatchPayload(
        theme: SpotterThemeOption,
        operationId: UUID,
        now: Date,
        serverVersion: String?
    ) throws -> [String: Any] {
        let nowString = FirestoreVersionStrings.string(from: now)
        var syncMetadata: [String: Any] = [
            "localUpdatedAt": nowString,
            "lastSyncedAt": NSNull(),
            "syncState": SyncState.pendingUpload.rawValue,
            "pendingOperationId": operationId.uuidString.lowercased()
        ]
        if let serverVersion {
            syncMetadata["serverVersion"] = serverVersion
        } else {
            syncMetadata["serverVersion"] = NSNull()
        }

        let payload: [String: Any] = [
            "selectedTheme": theme.rawValue,
            "updatedAt": nowString,
            "serverUpdatedAt": FieldValue.serverTimestamp(),
            "syncMetadata": syncMetadata,
            "operationId": operationId.uuidString.lowercased()
        ]
        try FirestorePrivacyValidator.validate(payload)
        return payload
    }
}
