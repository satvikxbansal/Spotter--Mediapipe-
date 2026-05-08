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

nonisolated final class LocalWriteJournal {
    private let fileURL: URL
    private let maxEntryCount: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var entries: [LocalWriteJournalEntry] = []

    private(set) var persistenceError: String?

    init(fileURL: URL? = nil, maxEntryCount: Int = 512) {
        self.fileURL = fileURL ?? Self.defaultJournalURL()
        self.maxEntryCount = max(maxEntryCount, 1)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func contains(operationId: UUID) -> Bool {
        load()
        return entries.contains { $0.operationId == operationId }
    }

    @discardableResult
    func record(
        operationId: UUID,
        entityKind: WriteEntityKind,
        createdAt: Date = Date()
    ) -> Bool {
        load()
        guard !entries.contains(where: { $0.operationId == operationId }) else { return true }

        let previousEntries = entries
        entries.append(
            LocalWriteJournalEntry(
                operationId: operationId,
                entityKind: entityKind,
                createdAt: createdAt
            )
        )
        entries = bounded(entries)

        guard persist() else {
            entries = previousEntries
            return false
        }
        return true
    }

    @discardableResult
    func vacuum(olderThan cutoff: Date) -> Int {
        load()
        let previousEntries = entries
        let retainedEntries = bounded(entries.filter { $0.createdAt >= cutoff })
        let removedCount = entries.count - retainedEntries.count
        guard removedCount > 0 else { return 0 }

        entries = retainedEntries
        guard persist() else {
            entries = previousEntries
            return 0
        }
        return removedCount
    }

    func snapshot() -> [LocalWriteJournalEntry] {
        load()
        return entries
    }

    static func defaultJournalURL(alongside storeFileURL: URL? = nil) -> URL {
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

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            entries = []
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let snapshot = try? decoder.decode(LocalWriteJournalSnapshot.self, from: data) {
                entries = bounded(snapshot.entries)
            } else {
                entries = bounded(try decoder.decode([LocalWriteJournalEntry].self, from: data))
            }
            persistenceError = nil
        } catch {
            entries = []
            persistenceError = "Could not load local write journal: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let snapshot = LocalWriteJournalSnapshot(entries: entries)
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            persistenceError = nil
            return true
        } catch {
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
