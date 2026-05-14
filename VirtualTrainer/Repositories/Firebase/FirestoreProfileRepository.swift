import Foundation

@MainActor
final class FirestoreProfileRepository: ProfileRepository {
    private let database: any FirestoreDocumentDatabase

    init(database: any FirestoreDocumentDatabase) {
        self.database = database
    }

    func loadProfile(accountId: String) async throws -> UserProfile? {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let path = try FirestorePathBuilder.profileDocument(uid: uid)
        guard let storedDocument = try await database.getDocument(path: path) else {
            return nil
        }
        return try Self.profile(from: storedDocument)
    }

    @discardableResult
    func saveProfile(_ profile: UserProfile, operationId: UUID) async throws -> UserProfile {
        let uid = try FirestoreRepositorySupport.requiredAccountId(profile.accountId ?? "")
        guard profile.accountId == uid else {
            throw RepositoryError.accountMissing
        }

        let path = try FirestorePathBuilder.profileDocument(uid: uid)
        let outcome = try await database.runTransaction { transaction in
            let current = try transaction.getDocument(path: path)

            if let current,
               let currentDocument = try? FirestoreRepositorySupport.decode(
                FirestoreProfileDocument.self,
                from: current
               ) {
                let currentProfile = mapFromProfileDocument(currentDocument)
                if currentDocument.operationId == operationId ||
                    FirestoreRepositorySupport.operationMatches(
                        currentProfile.syncMetadata.pendingOperationId,
                        operationId
                    ) {
                    return FirestoreProfileSaveOutcome.saved(
                        Self.profile(
                            currentProfile,
                            storedDocument: current,
                            serverDate: currentDocument.serverUpdatedAt
                        )
                    )
                }

                if currentProfile.syncMetadata.localUpdatedAt > profile.syncMetadata.localUpdatedAt,
                   currentProfile.syncMetadata.pendingOperationId != operationId {
                    var conflictedProfile = profile
                    conflictedProfile.syncMetadata.syncState = .conflict
                    conflictedProfile.syncMetadata.serverVersion = FirestoreRepositorySupport.serverVersion(
                        from: current,
                        serverDate: currentDocument.serverUpdatedAt,
                        fallbackDate: currentDocument.updatedAt
                    )
                    return FirestoreProfileSaveOutcome.conflict(conflictedProfile)
                }
            }

            let serverVersion = current.flatMap {
                FirestoreRepositorySupport.serverVersion(
                    from: $0,
                    serverDate: nil,
                    fallbackDate: profile.updatedAt
                )
            }
            var profileToWrite = profile
            profileToWrite.syncMetadata.pendingOperationId = operationId
            profileToWrite.syncMetadata.serverVersion = serverVersion
            let document = mapToProfileDocument(profileToWrite)
            let payload = try FirestoreEncodingHelpers.payload(from: document)
            try transaction.setData(payload, path: path, merge: true)
            return FirestoreProfileSaveOutcome.written
        }

        guard let profileOutcome = outcome as? FirestoreProfileSaveOutcome else {
            throw RepositoryError.backendUnavailable
        }

        switch profileOutcome {
        case .saved(let savedProfile), .conflict(let savedProfile):
            return savedProfile
        case .written:
            guard let storedDocument = try await database.getDocument(path: path) else {
                throw RepositoryError.notFound
            }
            var savedProfile = try Self.profile(from: storedDocument)
            savedProfile.syncMetadata.lastSyncedAt = Date()
            savedProfile.syncMetadata.syncState = .synced
            savedProfile.syncMetadata.pendingOperationId = nil
            savedProfile.syncMetadata.serverVersion = FirestoreRepositorySupport.serverVersion(
                from: storedDocument,
                serverDate: try? FirestoreRepositorySupport
                    .decode(FirestoreProfileDocument.self, from: storedDocument)
                    .serverUpdatedAt,
                fallbackDate: savedProfile.updatedAt
            )
            return savedProfile
        }
    }

    func observeProfile(accountId: String) async throws -> AsyncStream<UserProfile?> {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let path = try FirestorePathBuilder.profileDocument(uid: uid)

        return AsyncStream { continuation in
            var debounceTask: Task<Void, Never>?
            let listener = database.listenDocument(path: path) { result in
                debounceTask?.cancel()
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: FirestoreRepositorySupport.observerDebounceNanoseconds)
                    guard !Task.isCancelled else { return }
                    switch result {
                    case .success(let storedDocument):
                        do {
                            let profile = try storedDocument.map(Self.profile(from:))
                            continuation.yield(profile)
                        } catch {
                            continuation.finish()
                        }
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

    private nonisolated static func profile(from storedDocument: FirestoreStoredDocument) throws -> UserProfile {
        let document = try FirestoreRepositorySupport.decode(
            FirestoreProfileDocument.self,
            from: storedDocument
        )
        return profile(
            mapFromProfileDocument(document),
            storedDocument: storedDocument,
            serverDate: document.serverUpdatedAt
        )
    }

    private nonisolated static func profile(
        _ profile: UserProfile,
        storedDocument: FirestoreStoredDocument,
        serverDate: Date?
    ) -> UserProfile {
        var updatedProfile = profile
        updatedProfile.syncMetadata.serverVersion = FirestoreRepositorySupport.serverVersion(
            from: storedDocument,
            serverDate: serverDate,
            fallbackDate: profile.updatedAt
        )
        return updatedProfile
    }
}

private enum FirestoreProfileSaveOutcome {
    case saved(UserProfile)
    case conflict(UserProfile)
    case written
}
