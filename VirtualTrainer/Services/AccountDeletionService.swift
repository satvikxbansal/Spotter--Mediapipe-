import Foundation

nonisolated struct LocalModeDataContainer: Equatable {
    let storageDirectory: URL
    let temporaryDirectory: URL
    let cachesDirectory: URL

    init(
        storageDirectory: URL = LocalModeDataContainer.defaultStorageDirectory(),
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        cachesDirectory: URL = LocalModeDataContainer.defaultCachesDirectory()
    ) {
        self.storageDirectory = storageDirectory
        self.temporaryDirectory = temporaryDirectory
        self.cachesDirectory = cachesDirectory
    }

    static func defaultStorageDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Spotter", isDirectory: true)
    }

    static func defaultCachesDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    var profileURL: URL {
        storageDirectory.appendingPathComponent("UserProfile.json")
    }

    var workoutsURL: URL {
        storageDirectory.appendingPathComponent("WorkoutHistory.json")
    }

    var trophiesURL: URL {
        storageDirectory.appendingPathComponent("TrophyProgress.json")
    }

    var insightsURL: URL {
        storageDirectory.appendingPathComponent("CoachInsights.json")
    }

    var calibrationURL: URL {
        storageDirectory.appendingPathComponent("CalibrationRecord.json")
    }

    var themeURL: URL {
        storageDirectory.appendingPathComponent("Theme.json")
    }

    var plansURL: URL {
        storageDirectory.appendingPathComponent("WorkoutPlans.json")
    }

    var writeJournalURL: URL {
        storageDirectory.appendingPathComponent("LocalWriteJournal.json")
    }

    var generatedExportCacheDirectory: URL {
        temporaryDirectory.appendingPathComponent("SpotterDataExports", isDirectory: true)
    }

    var shareImageCacheDirectory: URL {
        cachesDirectory
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("ShareImages", isDirectory: true)
    }

    var localAccountDeletionURLs: [URL] {
        [
            profileURL,
            workoutsURL,
            trophiesURL,
            insightsURL,
            calibrationURL,
            themeURL,
            plansURL,
            writeJournalURL,
            generatedExportCacheDirectory,
            shareImageCacheDirectory
        ]
    }

    var localStoreFileURLs: [URL] {
        [
            profileURL,
            workoutsURL,
            trophiesURL,
            insightsURL,
            calibrationURL,
            themeURL,
            plansURL,
            writeJournalURL
        ]
    }
}

nonisolated struct AccountDeletionResult: Equatable {
    let deletedURLs: [URL]
    let alreadyMissingURLs: [URL]
    let clientDeletedRemoteDocumentCount: Int
    let cloudFailureMessages: [String]

    var removedItemCount: Int {
        deletedURLs.count
    }

    var cloudDeletionNotice: String? {
        cloudFailureMessages.isEmpty
            ? nil
            : "Some cloud data may take up to 7 days to delete."
    }
}

nonisolated struct AccountDeletionRemoteCleanupResult: Equatable {
    let deletedDocumentCount: Int
    let boundedDocumentLimit: Int
}

@MainActor
protocol AccountDeletionSyncManaging: AnyObject {
    func stopListeners() async throws
}

@MainActor
protocol AccountDeletionContextClearing: AnyObject {
    func clearAccount()
}

@MainActor
protocol AccountDeletionRemoteCleaning: AnyObject {
    func deleteClientAllowedAccountData(accountId: String) async throws -> AccountDeletionRemoteCleanupResult
}

nonisolated protocol AccountDeletionLocalDataCoordinating {
    var localAccountDeletionURLs: [URL] { get }
    func waitForStoreWrites() async
    func wipeLocalData() async throws -> AccountDeletionResult
}

nonisolated struct AccountDeletionService {
    private let localDataCoordinator: any AccountDeletionLocalDataCoordinating

    init(
        container: LocalModeDataContainer = LocalModeDataContainer(),
        persistenceActor: PersistenceActor = .shared
    ) {
        self.localDataCoordinator = FileAccountDeletionLocalDataCoordinator(
            container: container,
            persistenceActor: persistenceActor
        )
    }

    init(localDataCoordinator: any AccountDeletionLocalDataCoordinating) {
        self.localDataCoordinator = localDataCoordinator
    }

    @MainActor
    func deleteAccountAndData(
        mode: BackendMode = .local,
        currentAccountId: String? = nil,
        authRepository: (any AuthRepository)? = nil,
        syncOrchestrator: (any AccountDeletionSyncManaging)? = nil,
        remoteCleaner: (any AccountDeletionRemoteCleaning)? = nil,
        accountContext: (any AccountDeletionContextClearing)? = nil
    ) async throws -> AccountDeletionResult {
        switch mode {
        case .local, .supabase:
            let result = try await deleteLocalAccountAndData()
            accountContext?.clearAccount()
            return result
        case .firebase:
            return try await deleteFirebaseAccountAndData(
                currentAccountId: currentAccountId ?? authRepository?.currentAccountId,
                authRepository: authRepository,
                syncOrchestrator: syncOrchestrator,
                remoteCleaner: remoteCleaner,
                accountContext: accountContext
            )
        }
    }

    func deleteLocalAccountAndData() async throws -> AccountDeletionResult {
        try await localDataCoordinator.wipeLocalData()
    }

    @MainActor
    private func deleteFirebaseAccountAndData(
        currentAccountId: String?,
        authRepository: (any AuthRepository)?,
        syncOrchestrator: (any AccountDeletionSyncManaging)?,
        remoteCleaner: (any AccountDeletionRemoteCleaning)?,
        accountContext: (any AccountDeletionContextClearing)?
    ) async throws -> AccountDeletionResult {
        var cloudFailures: [String] = []
        let uid = AccountOwnership.normalizedAccountId(authRepository?.currentAccountId)
            ?? AccountOwnership.normalizedAccountId(currentAccountId)

        do {
            try await syncOrchestrator?.stopListeners()
        } catch {
            cloudFailures.append("Sync listeners could not be stopped before deletion.")
        }

        await localDataCoordinator.waitForStoreWrites()

        var remoteDocumentDeleteCount = 0
        if let uid, let remoteCleaner {
            do {
                let cleanup = try await remoteCleaner.deleteClientAllowedAccountData(accountId: uid)
                remoteDocumentDeleteCount = cleanup.deletedDocumentCount
            } catch {
                cloudFailures.append("Client-allowed Firestore cleanup could not be completed immediately.")
            }
        }

        if uid != nil {
            do {
                try await authRepository?.deleteAccount()
            } catch {
                cloudFailures.append("Firebase Auth account deletion could not be completed immediately.")
            }
        }

        let localResult = try await localDataCoordinator.wipeLocalData()
        accountContext?.clearAccount()

        return AccountDeletionResult(
            deletedURLs: localResult.deletedURLs,
            alreadyMissingURLs: localResult.alreadyMissingURLs,
            clientDeletedRemoteDocumentCount: remoteDocumentDeleteCount,
            cloudFailureMessages: cloudFailures
        )
    }
}

extension SyncOrchestrator: AccountDeletionSyncManaging {}
extension AccountContext: AccountDeletionContextClearing {}

nonisolated struct FileAccountDeletionLocalDataCoordinator: AccountDeletionLocalDataCoordinating {
    let container: LocalModeDataContainer
    let persistenceActor: PersistenceActor

    var localAccountDeletionURLs: [URL] {
        container.localAccountDeletionURLs
    }

    func waitForStoreWrites() async {
        for url in uniqueURLs(container.localStoreFileURLs) {
            await persistenceActor.waitForWrites(to: url)
        }
    }

    func wipeLocalData() async throws -> AccountDeletionResult {
        var deletedURLs: [URL] = []
        var alreadyMissingURLs: [URL] = []

        for url in uniqueURLs(container.localAccountDeletionURLs) {
            if url.standardizedFileURL.path == container.writeJournalURL.standardizedFileURL.path {
                await Task.yield()
            }
            if try await removeIfPresent(url) {
                deletedURLs.append(url)
            } else {
                alreadyMissingURLs.append(url)
            }
        }

        await Task.yield()
        _ = try await removeIfPresent(container.writeJournalURL)

        return AccountDeletionResult(
            deletedURLs: deletedURLs,
            alreadyMissingURLs: alreadyMissingURLs,
            clientDeletedRemoteDocumentCount: 0,
            cloudFailureMessages: []
        )
    }

    private func removeIfPresent(_ url: URL) async throws -> Bool {
        await persistenceActor.waitForWrites(to: url)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        do {
            try await persistenceActor.removeAfterQueuedWrites(at: url)
            return true
        } catch {
            if isNoSuchFileError(error) || !FileManager.default.fileExists(atPath: url.path) {
                return false
            }
            throw error
        }
    }

    private func isNoSuchFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seenPaths: Set<String> = []
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            guard !seenPaths.contains(path) else { return false }
            seenPaths.insert(path)
            return true
        }
    }
}

@MainActor
final class FirestoreAccountDeletionRemoteCleaner: AccountDeletionRemoteCleaning {
    private let database: any FirestoreDocumentDatabase
    private let planDeleteLimit: Int

    init(
        database: (any FirestoreDocumentDatabase)? = nil,
        planDeleteLimit: Int = 50
    ) {
        self.database = database ?? FirebaseFirestoreDocumentDatabase()
        self.planDeleteLimit = planDeleteLimit
    }

    func deleteClientAllowedAccountData(accountId: String) async throws -> AccountDeletionRemoteCleanupResult {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.plansCollection(uid: uid)
        let documents = try await database.queryDocuments(
            collectionPath: collectionPath,
            filters: [],
            orderBy: "savedAt",
            descending: true,
            limit: planDeleteLimit
        )

        guard !documents.isEmpty else {
            return AccountDeletionRemoteCleanupResult(
                deletedDocumentCount: 0,
                boundedDocumentLimit: planDeleteLimit
            )
        }

        try await database.commitBatch { batch in
            for document in documents {
                try batch.deleteDocument(path: document.path)
            }
        }

        return AccountDeletionRemoteCleanupResult(
            deletedDocumentCount: documents.count,
            boundedDocumentLimit: planDeleteLimit
        )
    }
}
