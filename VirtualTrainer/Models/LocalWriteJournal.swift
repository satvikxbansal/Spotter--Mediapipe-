import Foundation

nonisolated struct LocalWriteJournalEntry: Codable, Equatable, Identifiable {
    var id: UUID { operationId }

    let operationId: UUID
    let entityKind: WriteEntityKind
    let createdAt: Date
}

nonisolated struct LocalWriteJournalSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let entries: [LocalWriteJournalEntry]

    init(schemaVersion: Int = 1, entries: [LocalWriteJournalEntry]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }
}

actor LocalWriteJournal {
    private let fileURL: URL
    private let maxEntryCount: Int
    private let decoder = JSONDecoder()
    private let persistenceActor: PersistenceActor
    private var entries: [LocalWriteJournalEntry] = []
    private var persistedEntries: [LocalWriteJournalEntry] = []
    private var hasLoaded = false
    private var persistenceGeneration = 0

    private(set) var persistenceError: String?

    init(
        fileURL: URL? = nil,
        maxEntryCount: Int = 512,
        persistenceActor: PersistenceActor = .shared
    ) {
        self.fileURL = fileURL ?? Self.defaultJournalURL()
        self.maxEntryCount = max(maxEntryCount, 1)
        self.persistenceActor = persistenceActor
        decoder.dateDecodingStrategy = .iso8601
    }

    func contains(operationId: UUID) async -> Bool {
        await loadIfNeeded()
        return entries.contains { $0.operationId == operationId }
    }

    @discardableResult
    func record(
        operationId: UUID,
        entityKind: WriteEntityKind,
        createdAt: Date = Date()
    ) async -> Bool {
        await loadIfNeeded()
        guard !entries.contains(where: { $0.operationId == operationId }) else { return true }

        entries.append(
            LocalWriteJournalEntry(
                operationId: operationId,
                entityKind: entityKind,
                createdAt: createdAt
            )
        )
        entries = bounded(entries)
        let generation = nextPersistenceGeneration()

        return await persist(generation: generation)
    }

    @discardableResult
    func vacuum(olderThan cutoff: Date) async -> Int {
        await loadIfNeeded()
        let retainedEntries = bounded(entries.filter { $0.createdAt >= cutoff })
        let removedCount = entries.count - retainedEntries.count
        guard removedCount > 0 else { return 0 }

        entries = retainedEntries
        let generation = nextPersistenceGeneration()
        return await persist(generation: generation) ? removedCount : 0
    }

    func snapshot() async -> [LocalWriteJournalEntry] {
        await loadIfNeeded()
        return entries
    }

    nonisolated static func defaultJournalURL(alongside storeFileURL: URL? = nil) -> URL {
        if let storeFileURL {
            return storeFileURL
                .deletingLastPathComponent()
                .appendingPathComponent("LocalWriteJournal.json")
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("LocalWriteJournal.json")
    }

    private func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = []
            persistedEntries = []
            persistenceError = nil
            return
        }

        do {
            let data = try await persistenceActor.read(from: fileURL)
            if let snapshot = try? decoder.decode(LocalWriteJournalSnapshot.self, from: data) {
                entries = bounded(snapshot.entries)
            } else {
                entries = bounded(try decoder.decode([LocalWriteJournalEntry].self, from: data))
            }
            persistedEntries = entries
            persistenceError = nil
        } catch {
            entries = []
            persistedEntries = []
            persistenceError = "Could not load local write journal: \(error.localizedDescription)"
        }
    }

    private func nextPersistenceGeneration() -> Int {
        persistenceGeneration += 1
        return persistenceGeneration
    }

    @discardableResult
    private func persist(generation: Int) async -> Bool {
        do {
            let entriesToPersist = entries
            let snapshot = LocalWriteJournalSnapshot(entries: entriesToPersist)
            let data = try await persistenceActor.encode(
                snapshot,
                outputFormatting: [.prettyPrinted, .sortedKeys]
            )
            let outcome = try await persistenceActor.writeLatest(data, to: fileURL, options: [.atomic])
            if outcome == .written {
                persistedEntries = entriesToPersist
            }
            persistenceError = nil
            return true
        } catch {
            if generation == persistenceGeneration {
                entries = persistedEntries
            }
            persistenceError = "Could not save local write journal: \(error.localizedDescription)"
            return false
        }
    }

    private func bounded(_ candidateEntries: [LocalWriteJournalEntry]) -> [LocalWriteJournalEntry] {
        let dedupedEntries = candidateEntries.reduce(into: [UUID: LocalWriteJournalEntry]()) { result, entry in
            if let existing = result[entry.operationId], existing.createdAt >= entry.createdAt {
                return
            }
            result[entry.operationId] = entry
        }

        return Array(
            dedupedEntries.values.sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.operationId.uuidString < $1.operationId.uuidString
                }
                return $0.createdAt > $1.createdAt
            }
            .prefix(maxEntryCount)
        )
    }
}
