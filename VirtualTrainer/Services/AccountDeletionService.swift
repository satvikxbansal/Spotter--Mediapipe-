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
            writeJournalURL,
            generatedExportCacheDirectory,
            shareImageCacheDirectory
        ]
    }
}

nonisolated enum AccountDeletionBackendMode: Equatable {
    case local
    case firebase
}

nonisolated struct AccountDeletionResult: Equatable {
    let deletedURLs: [URL]
    let alreadyMissingURLs: [URL]

    var removedItemCount: Int {
        deletedURLs.count
    }
}

enum AccountDeletionServiceError: Error, LocalizedError {
    case firebaseDeletionNotImplemented

    var errorDescription: String? {
        switch self {
        case .firebaseDeletionNotImplemented:
            return "Firebase account deletion is not wired yet. Local mode deletion is available now."
        }
    }
}

nonisolated struct AccountDeletionService {
    let container: LocalModeDataContainer
    let persistenceActor: PersistenceActor

    init(
        container: LocalModeDataContainer = LocalModeDataContainer(),
        persistenceActor: PersistenceActor = .shared
    ) {
        self.container = container
        self.persistenceActor = persistenceActor
    }

    /// Future Firebase mode should call the auth provider deletion endpoint, remove
    /// remote account-scoped documents through repositories, then run this local
    /// cleanup as the final on-device step. Until that phase exists, only local
    /// account/data deletion is supported.
    func deleteAccountAndData(mode: AccountDeletionBackendMode = .local) async throws -> AccountDeletionResult {
        switch mode {
        case .local:
            return try await deleteLocalAccountAndData()
        case .firebase:
            throw AccountDeletionServiceError.firebaseDeletionNotImplemented
        }
    }

    func deleteLocalAccountAndData() async throws -> AccountDeletionResult {
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
            alreadyMissingURLs: alreadyMissingURLs
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
