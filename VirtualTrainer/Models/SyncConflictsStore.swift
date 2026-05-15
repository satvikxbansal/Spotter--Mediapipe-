import Combine
import Foundation

nonisolated struct SyncConflictEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let accountId: String
    let entityKind: WriteEntityKind
    let recordId: String
    let occurredAt: Date
    let serverVersion: String?
    let localVersion: String?
    let message: String

    init(
        id: UUID = UUID(),
        accountId: String,
        entityKind: WriteEntityKind,
        recordId: String,
        occurredAt: Date = Date(),
        serverVersion: String?,
        localVersion: String?,
        message: String
    ) {
        self.id = id
        self.accountId = accountId
        self.entityKind = entityKind
        self.recordId = recordId
        self.occurredAt = occurredAt
        self.serverVersion = serverVersion
        self.localVersion = localVersion
        self.message = message
    }
}

nonisolated struct SyncConflictSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let events: [SyncConflictEvent]

    init(schemaVersion: Int = 1, events: [SyncConflictEvent]) {
        self.schemaVersion = schemaVersion
        self.events = events
    }
}

@MainActor
final class SyncConflictsStore: ObservableObject {
    @Published private(set) var events: [SyncConflictEvent] = []
    @Published var persistenceError: String?

    private let fileURL: URL
    private let maxEventCount: Int
    private let decoder = JSONDecoder()
    private let persistenceActor: PersistenceActor

    init(
        fileURL: URL? = nil,
        maxEventCount: Int = 50,
        persistenceActor: PersistenceActor = .shared
    ) {
        self.fileURL = fileURL ?? Self.defaultConflictsURL()
        self.maxEventCount = max(maxEventCount, 1)
        self.persistenceActor = persistenceActor
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    var count: Int {
        events.count
    }

    @discardableResult
    func record(_ event: SyncConflictEvent) async -> Bool {
        events.removeAll {
            $0.accountId == event.accountId &&
                $0.entityKind == event.entityKind &&
                $0.recordId == event.recordId
        }
        events.insert(event, at: 0)
        events = bounded(events)
        return await persist()
    }

    @discardableResult
    func removeAll() async -> Bool {
        events = []
        return await persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            events = []
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let snapshot = try? decoder.decode(SyncConflictSnapshot.self, from: data) {
                events = bounded(snapshot.events)
            } else {
                events = bounded(try decoder.decode([SyncConflictEvent].self, from: data))
            }
            persistenceError = nil
        } catch {
            events = []
            persistenceError = "Could not load sync conflicts: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func persist() async -> Bool {
        do {
            let data = try await persistenceActor.encode(
                SyncConflictSnapshot(events: events),
                outputFormatting: [.prettyPrinted, .sortedKeys]
            )
            _ = try await persistenceActor.writeLatest(data, to: fileURL, options: [.atomic])
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Could not save sync conflicts: \(error.localizedDescription)"
            return false
        }
    }

    private func bounded(_ candidateEvents: [SyncConflictEvent]) -> [SyncConflictEvent] {
        Array(
            candidateEvents
                .sorted {
                    if $0.occurredAt == $1.occurredAt {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return $0.occurredAt > $1.occurredAt
                }
                .prefix(maxEventCount)
        )
    }

    nonisolated static func defaultConflictsURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("SyncConflicts.json")
    }
}
