import XCTest
@testable import VirtualTrainer

@MainActor
final class LocalWriteJournalTests: XCTestCase {
    func testJournalPersistsAndReloads() throws {
        let url = temporaryJournalURL()
        let operationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C001") ?? UUID()
        let createdAt = Date(timeIntervalSince1970: 1_778_100_000)
        let journal = LocalWriteJournal(fileURL: url)

        XCTAssertFalse(journal.contains(operationId: operationId))
        XCTAssertTrue(
            journal.record(
                operationId: operationId,
                entityKind: .workout,
                createdAt: createdAt
            )
        )

        let reloaded = LocalWriteJournal(fileURL: url)

        XCTAssertTrue(reloaded.contains(operationId: operationId))
        XCTAssertEqual(reloaded.snapshot().first?.entityKind, .workout)
        XCTAssertEqual(reloaded.snapshot().first?.createdAt, createdAt)
    }

    func testJournalVacuumRemovesOlderEntries() throws {
        let url = temporaryJournalURL()
        let oldOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C002") ?? UUID()
        let recentOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C003") ?? UUID()
        let oldDate = Date(timeIntervalSince1970: 1_778_100_000)
        let recentDate = Date(timeIntervalSince1970: 1_778_200_000)
        let journal = LocalWriteJournal(fileURL: url)

        XCTAssertTrue(journal.record(operationId: oldOperationId, entityKind: .profile, createdAt: oldDate))
        XCTAssertTrue(journal.record(operationId: recentOperationId, entityKind: .theme, createdAt: recentDate))

        XCTAssertEqual(journal.vacuum(olderThan: recentDate), 1)

        let reloaded = LocalWriteJournal(fileURL: url)
        XCTAssertFalse(reloaded.contains(operationId: oldOperationId))
        XCTAssertTrue(reloaded.contains(operationId: recentOperationId))
    }

    func testJournalKeepsEntriesBounded() throws {
        let url = temporaryJournalURL()
        let oldestOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C004") ?? UUID()
        let middleOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C005") ?? UUID()
        let newestOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000C006") ?? UUID()
        let journal = LocalWriteJournal(fileURL: url, maxEntryCount: 2)

        XCTAssertTrue(
            journal.record(
                operationId: oldestOperationId,
                entityKind: .workout,
                createdAt: Date(timeIntervalSince1970: 1_778_100_000)
            )
        )
        XCTAssertTrue(
            journal.record(
                operationId: middleOperationId,
                entityKind: .insight,
                createdAt: Date(timeIntervalSince1970: 1_778_200_000)
            )
        )
        XCTAssertTrue(
            journal.record(
                operationId: newestOperationId,
                entityKind: .calibration,
                createdAt: Date(timeIntervalSince1970: 1_778_300_000)
            )
        )

        let reloaded = LocalWriteJournal(fileURL: url, maxEntryCount: 2)
        XCTAssertEqual(reloaded.snapshot().count, 2)
        XCTAssertFalse(reloaded.contains(operationId: oldestOperationId))
        XCTAssertTrue(reloaded.contains(operationId: middleOperationId))
        XCTAssertTrue(reloaded.contains(operationId: newestOperationId))
    }

    private func temporaryJournalURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalWriteJournalTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("LocalWriteJournal.json")
    }
}
