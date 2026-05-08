import Foundation
import Combine

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var selectedTheme: SpotterThemeOption
    @Published var persistenceError: String?

    private let fileURL: URL
    private let defaultTheme: SpotterThemeOption
    private let writeJournal: LocalWriteJournal
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let legacyDecoder = JSONDecoder()
    private var currentAccountId: String?
    private var storedEnvelope: ThemeEnvelope?

    init(
        fileURL: URL? = nil,
        defaultTheme: SpotterThemeOption = .hyper,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil
    ) {
        let resolvedFileURL = fileURL ?? Self.defaultThemeURL()
        self.fileURL = resolvedFileURL
        self.defaultTheme = defaultTheme
        self.selectedTheme = defaultTheme
        self.writeJournal = writeJournal ?? LocalWriteJournal(
            fileURL: LocalWriteJournal.defaultJournalURL(alongside: resolvedFileURL)
        )
        self.currentAccountId = AccountOwnership.normalizedAccountId(accountId)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadTheme()
    }

    nonisolated deinit {}

    func setCurrentAccountId(_ accountId: String?) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        guard currentAccountId != normalizedAccountId else { return }
        currentAccountId = normalizedAccountId
        applyStoredEnvelope()
    }

    @discardableResult
    func updateSelectedTheme(_ theme: SpotterThemeOption, operationId: UUID? = nil) -> Bool {
        let writeOperationId = operationId ?? UUID()
        guard !writeJournal.contains(operationId: writeOperationId) else { return true }

        let previousTheme = selectedTheme
        let previousEnvelope = storedEnvelope
        let shouldPersist = selectedTheme != theme ||
            persistenceError != nil ||
            !FileManager.default.fileExists(atPath: fileURL.path)

        guard shouldPersist else { return true }

        let writeCreatedAt = Date()
        let baseMetadata = storedEnvelope?.syncMetadata
            ?? ThemeEnvelope(selectedTheme: theme, accountId: currentAccountId).syncMetadata
        selectedTheme = theme
        storedEnvelope = ThemeEnvelope(
            selectedTheme: theme,
            accountId: currentAccountId,
            syncMetadata: baseMetadata.markedForLocalMutation(
                accountId: currentAccountId,
                operationId: writeOperationId,
                now: writeCreatedAt
            )
        )
        guard persist() else {
            selectedTheme = previousTheme
            storedEnvelope = previousEnvelope
            return false
        }
        recordWriteOperation(writeOperationId, createdAt: writeCreatedAt)
        return true
    }

    @discardableResult
    func sync(with profile: UserProfile?) -> Bool {
        guard let profile else { return true }
        return updateSelectedTheme(profile.selectedTheme)
    }

    func reload() {
        loadTheme()
    }

    @discardableResult
    func claimLocalDataForAccount(id accountId: String, operationId: UUID? = nil) -> Bool {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            persistenceError = "Account id is required before local theme data can be claimed."
            return false
        }
        guard let storedEnvelope, storedEnvelope.accountId == nil else { return true }

        let writeOperationId = operationId ?? UUID()
        guard !writeJournal.contains(operationId: writeOperationId) else { return true }

        let writeCreatedAt = Date()
        let previousEnvelope = self.storedEnvelope
        let previousTheme = selectedTheme
        self.storedEnvelope = ThemeEnvelope(
            selectedTheme: storedEnvelope.selectedTheme,
            accountId: normalizedAccountId,
            syncMetadata: storedEnvelope.syncMetadata.markedForLocalMutation(
                accountId: normalizedAccountId,
                operationId: writeOperationId,
                now: writeCreatedAt
            )
        )
        applyStoredEnvelope()
        guard persist() else {
            self.storedEnvelope = previousEnvelope
            selectedTheme = previousTheme
            return false
        }
        recordWriteOperation(writeOperationId, createdAt: writeCreatedAt)
        return true
    }

    private func recordWriteOperation(_ operationId: UUID, createdAt: Date) {
        _ = writeJournal.record(
            operationId: operationId,
            entityKind: .theme,
            createdAt: createdAt
        )
    }

    private func loadTheme() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            storedEnvelope = nil
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
            applyStoredEnvelope()
            persistenceError = nil
        } catch {
            storedEnvelope = nil
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
    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let envelope = storedEnvelope ?? ThemeEnvelope(
                selectedTheme: selectedTheme,
                accountId: currentAccountId
            )
            let data = try encoder.encode(envelope)
            try data.write(to: fileURL, options: [.atomic])
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Could not save theme: \(error.localizedDescription)"
            return false
        }
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
