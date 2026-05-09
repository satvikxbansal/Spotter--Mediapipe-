import XCTest
@testable import VirtualTrainer

@MainActor
final class LocalWriteJournalTests: XCTestCase {
    func testJournalPersistsAndReloads() async throws {
        let url = temporaryJournalURL()
        let operationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C001") ?? UUID()
        let createdAt = Date(timeIntervalSince1970: 1_778_100_000)
        let journal = LocalWriteJournal(fileURL: url)

        assertFalse(await journal.contains(operationId: operationId))
        assertTrue(
            await journal.record(
                operationId: operationId,
                entityKind: .workout,
                createdAt: createdAt
            )
        )

        let reloaded = LocalWriteJournal(fileURL: url)

        assertTrue(await reloaded.contains(operationId: operationId))
        assertEqual(await reloaded.snapshot().first?.entityKind, .workout)
        assertEqual(await reloaded.snapshot().first?.createdAt, createdAt)
    }

    func testJournalVacuumRemovesOlderEntries() async throws {
        let url = temporaryJournalURL()
        let oldOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C002") ?? UUID()
        let recentOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C003") ?? UUID()
        let oldDate = Date(timeIntervalSince1970: 1_778_100_000)
        let recentDate = Date(timeIntervalSince1970: 1_778_200_000)
        let journal = LocalWriteJournal(fileURL: url)

        assertTrue(await journal.record(operationId: oldOperationId, entityKind: .profile, createdAt: oldDate))
        assertTrue(await journal.record(operationId: recentOperationId, entityKind: .theme, createdAt: recentDate))

        assertEqual(await journal.vacuum(olderThan: recentDate), 1)

        let reloaded = LocalWriteJournal(fileURL: url)
        assertFalse(await reloaded.contains(operationId: oldOperationId))
        assertTrue(await reloaded.contains(operationId: recentOperationId))
    }

    func testJournalKeepsEntriesBounded() async throws {
        let url = temporaryJournalURL()
        let oldestOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C004") ?? UUID()
        let middleOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C005") ?? UUID()
        let newestOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C006") ?? UUID()
        let journal = LocalWriteJournal(fileURL: url, maxEntryCount: 2)

        assertTrue(
            await journal.record(
                operationId: oldestOperationId,
                entityKind: .workout,
                createdAt: Date(timeIntervalSince1970: 1_778_100_000)
            )
        )
        assertTrue(
            await journal.record(
                operationId: middleOperationId,
                entityKind: .insight,
                createdAt: Date(timeIntervalSince1970: 1_778_200_000)
            )
        )
        assertTrue(
            await journal.record(
                operationId: newestOperationId,
                entityKind: .calibration,
                createdAt: Date(timeIntervalSince1970: 1_778_300_000)
            )
        )

        let reloaded = LocalWriteJournal(fileURL: url, maxEntryCount: 2)
        assertEqual(await reloaded.snapshot().count, 2)
        assertFalse(await reloaded.contains(operationId: oldestOperationId))
        assertTrue(await reloaded.contains(operationId: middleOperationId))
        assertTrue(await reloaded.contains(operationId: newestOperationId))
    }

    private func temporaryJournalURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalWriteJournalTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("LocalWriteJournal.json")
    }
}
