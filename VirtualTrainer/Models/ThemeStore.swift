import Foundation
import Combine

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var selectedTheme: SpotterThemeOption
    @Published var persistenceError: String?

    private let fileURL: URL
    private let defaultTheme: SpotterThemeOption
    private let writeJournal: LocalWriteJournal
    private let decoder = JSONDecoder()
    private let legacyDecoder = JSONDecoder()
    private let persistenceActor: PersistenceActor
    private var currentAccountId: String?
    private var storedEnvelope: ThemeEnvelope?
    private var persistedEnvelope: ThemeEnvelope?
    private var persistenceGeneration = 0
    private var backendMode: BackendMode = .local
    private var themeRepository: (any ThemeRepository)?
    private var themeObservationTask: Task<Void, Never>?

    init(
        fileURL: URL? = nil,
        defaultTheme: SpotterThemeOption = .hyper,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let resolvedFileURL = fileURL ?? Self.defaultThemeURL()
        self.fileURL = resolvedFileURL
        self.defaultTheme = defaultTheme
        self.selectedTheme = defaultTheme
        self.writeJournal = writeJournal ?? LocalWriteJournal(
            fileURL: LocalWriteJournal.defaultJournalURL(alongside: resolvedFileURL),
            persistenceActor: persistenceActor
        )
        self.persistenceActor = persistenceActor
        self.currentAccountId = AccountOwnership.normalizedAccountId(accountId)
        decoder.dateDecodingStrategy = .iso8601
        loadTheme()
    }

    nonisolated deinit {}

    func configureRemoteSync(
        backendMode: BackendMode,
        themeRepository: (any ThemeRepository)?
    ) {
        self.backendMode = backendMode
        self.themeRepository = backendMode == .firebase ? themeRepository : nil
        restartThemeObservationIfNeeded()
    }

    func setCurrentAccountId(_ accountId: String?) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        guard currentAccountId != normalizedAccountId else { return }
        currentAccountId = normalizedAccountId
        applyStoredEnvelope()
        restartThemeObservationIfNeeded()
    }

    @discardableResult
    func updateSelectedTheme(
        _ theme: SpotterThemeOption,
        operationId: UUID? = nil,
        saveRemote: Bool = true,
        recordJournal: Bool = true
    ) async -> Bool {
        let writeOperationId = operationId ?? UUID()

        let shouldPersist = selectedTheme != theme ||
            persistenceError != nil ||
            !FileManager.default.fileExists(atPath: fileURL.path)

        guard shouldPersist else { return true }

        let writeCreatedAt = Date()
        let baseMetadata = storedEnvelope?.syncMetadata
            ?? ThemeEnvelope(selectedTheme: theme, accountId: currentAccountId).syncMetadata
        let nextEnvelope = ThemeEnvelope(
            selectedTheme: theme,
            accountId: currentAccountId,
            syncMetadata: baseMetadata.markedForLocalMutation(
                accountId: currentAccountId,
                operationId: writeOperationId,
                now: writeCreatedAt
            )
        )
        let previousEnvelope = storedEnvelope
        let previousTheme = selectedTheme
        let generation = applyLocalMutation(nextEnvelope)
        if recordJournal, await writeJournal.contains(operationId: writeOperationId) {
            rollbackLocalMutationIfNeeded(
                generation: generation,
                envelope: previousEnvelope,
                selectedTheme: previousTheme
            )
            return true
        }
        guard await persist(nextEnvelope, generation: generation) != nil else { return false }
        if saveRemote {
            guard await saveThemeRemotelyIfNeeded(theme, operationId: writeOperationId) else {
                return false
            }
        }
        if recordJournal {
            await recordWriteOperation(writeOperationId, createdAt: writeCreatedAt)
        }
        return true
    }

    @discardableResult
    func sync(with profile: UserProfile?) async -> Bool {
        guard let profile else { return true }
        if backendMode == .firebase {
            return await applyThemeCache(profile.selectedTheme, accountId: profile.accountId)
        }
        return await updateSelectedTheme(profile.selectedTheme)
    }

    func reload() {
        loadTheme()
    }

    @discardableResult
    func claimLocalDataForAccount(id accountId: String, operationId: UUID? = nil) async -> Bool {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            persistenceError = "Account id is required before local theme data can be claimed."
            return false
        }
        guard let storedEnvelope, storedEnvelope.accountId == nil else { return true }

        let writeOperationId = operationId ?? UUID()

        let writeCreatedAt = Date()
        let nextEnvelope = ThemeEnvelope(
            selectedTheme: storedEnvelope.selectedTheme,
            accountId: normalizedAccountId,
            syncMetadata: storedEnvelope.syncMetadata.markedForLocalMutation(
                accountId: normalizedAccountId,
                operationId: writeOperationId,
                now: writeCreatedAt
            )
        )
        let previousEnvelope = self.storedEnvelope
        let previousTheme = selectedTheme
        let generation = applyLocalMutation(nextEnvelope)
        if await writeJournal.contains(operationId: writeOperationId) {
            rollbackLocalMutationIfNeeded(
                generation: generation,
                envelope: previousEnvelope,
                selectedTheme: previousTheme
            )
            return true
        }
        guard await persist(nextEnvelope, generation: generation) != nil else { return false }
        await recordWriteOperation(writeOperationId, createdAt: writeCreatedAt)
        return true
    }

    private func recordWriteOperation(_ operationId: UUID, createdAt: Date) async {
        _ = await writeJournal.record(
            operationId: operationId,
            entityKind: .theme,
            createdAt: createdAt
        )
    }

    private func restartThemeObservationIfNeeded() {
        themeObservationTask?.cancel()
        themeObservationTask = nil

        guard backendMode == .firebase,
              let themeRepository,
              let currentAccountId else {
            return
        }

        themeObservationTask = Task { [weak self, themeRepository, currentAccountId] in
            do {
                let loadedTheme = try await themeRepository.loadTheme(accountId: currentAccountId)
                _ = await self?.applyThemeCache(loadedTheme, accountId: currentAccountId)

                let stream = try await themeRepository.observeTheme(accountId: currentAccountId)
                for await remoteTheme in stream {
                    _ = await self?.applyThemeCache(remoteTheme, accountId: currentAccountId)
                }
            } catch {
                await self?.setRemoteThemeError(error)
            }
        }
    }

    private func saveThemeRemotelyIfNeeded(
        _ theme: SpotterThemeOption,
        operationId: UUID
    ) async -> Bool {
        guard backendMode == .firebase,
              let themeRepository,
              let currentAccountId else {
            return true
        }

        do {
            try await themeRepository.saveTheme(
                theme,
                accountId: currentAccountId,
                operationId: operationId
            )
            return await applyThemeCache(theme, accountId: currentAccountId)
        } catch {
            persistenceError = "Could not sync theme: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    private func applyThemeCache(
        _ theme: SpotterThemeOption,
        accountId: String?
    ) async -> Bool {
        let envelope = ThemeEnvelope(
            selectedTheme: theme,
            accountId: accountId,
            syncMetadata: SyncMetadata(
                localUpdatedAt: Date(),
                lastSyncedAt: Date(),
                serverVersion: nil,
                syncState: .synced,
                pendingOperationId: nil
            )
        )
        let generation = applyLocalMutation(envelope)
        return await persist(envelope, generation: generation) != nil
    }

    private func setRemoteThemeError(_ error: Error) {
        persistenceError = "Could not observe theme sync: \(error.localizedDescription)"
    }

    private func loadTheme() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            storedEnvelope = nil
            persistedEnvelope = nil
            selectedTheme = defaultTheme
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let envelope = decodeThemeEnvelope(from: data) {
                storedEnvelope = envelope
            } else {
                storedEnvelope = ThemeEnvelope(
                    selectedTheme: try decoder.decode(SpotterThemeOption.self, from: data)
                )
            }
            persistedEnvelope = storedEnvelope
            applyStoredEnvelope()
            persistenceError = nil
        } catch {
            storedEnvelope = nil
            persistedEnvelope = nil
            selectedTheme = defaultTheme
            persistenceError = "Could not load theme: \(error.localizedDescription)"
        }
    }

    private func decodeThemeEnvelope(from data: Data) -> ThemeEnvelope? {
        if let envelope = try? decoder.decode(ThemeEnvelope.self, from: data) {
            return envelope
        }

        return try? legacyDecoder.decode(ThemeEnvelope.self, from: data)
    }

    @discardableResult
    private func persist(_ envelope: ThemeEnvelope, generation: Int) async -> PersistenceWriteOutcome? {
        do {
            let data = try await persistenceActor.encode(
                envelope,
                outputFormatting: [.prettyPrinted, .sortedKeys]
            )
            let outcome = try await persistenceActor.writeLatest(data, to: fileURL, options: [.atomic])
            if outcome == .written {
                persistedEnvelope = envelope
            }
            persistenceError = nil
            return outcome
        } catch {
            rollbackLatestMutationIfNeeded(generation: generation)
            persistenceError = "Could not save theme: \(error.localizedDescription)"
            return nil
        }
    }

    private func applyLocalMutation(_ envelope: ThemeEnvelope) -> Int {
        persistenceGeneration += 1
        storedEnvelope = envelope
        applyStoredEnvelope()
        return persistenceGeneration
    }

    private func rollbackLatestMutationIfNeeded(generation: Int) {
        guard generation == persistenceGeneration else { return }
        storedEnvelope = persistedEnvelope
        applyStoredEnvelope()
    }

    private func rollbackLocalMutationIfNeeded(
        generation: Int,
        envelope previousEnvelope: ThemeEnvelope?,
        selectedTheme previousTheme: SpotterThemeOption
    ) {
        guard generation == persistenceGeneration else { return }
        storedEnvelope = previousEnvelope
        selectedTheme = previousTheme
    }

    private func applyStoredEnvelope() {
        guard let storedEnvelope,
              AccountOwnership.isVisible(
                recordAccountId: storedEnvelope.accountId,
                currentAccountId: currentAccountId
              )
        else {
            selectedTheme = defaultTheme
            return
        }

        selectedTheme = storedEnvelope.selectedTheme
    }

    private static func defaultThemeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("Theme.json")
    }
}

private struct ThemeEnvelope: Codable {
    let selectedTheme: SpotterThemeOption
    let accountId: String?
    var syncMetadata: SyncMetadata

    init(
        selectedTheme: SpotterThemeOption,
        accountId: String? = nil,
        syncMetadata: SyncMetadata? = nil
    ) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        self.selectedTheme = selectedTheme
        self.accountId = normalizedAccountId
        self.syncMetadata = syncMetadata ?? (
            normalizedAccountId == nil
                ? .initialLocalOnly()
                : .initialPendingUpload(operationId: nil)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case selectedTheme
        case accountId
        case syncMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            selectedTheme: try container.decode(SpotterThemeOption.self, forKey: .selectedTheme),
            accountId: try container.decodeIfPresent(String.self, forKey: .accountId),
            syncMetadata: try container.decodeIfPresent(SyncMetadata.self, forKey: .syncMetadata)
                ?? .initialLocalOnly()
        )
    }
}
