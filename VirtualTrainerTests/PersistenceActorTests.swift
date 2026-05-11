import XCTest
@testable import VirtualTrainer

final class PersistenceActorTests: XCTestCase {
    func testReadWriteRemoveRoundTrip() async throws {
        let actor = PersistenceActor()
        let url = temporaryPersistenceURL()
        let payload = Data("spotter persistence round trip".utf8)

        try await actor.createDirectoryIfNeeded(for: url)
        try await actor.write(payload, to: url, options: .atomic)

        let reloaded = try await actor.read(from: url)
        XCTAssertEqual(reloaded, payload)

        try await actor.remove(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRapidWritesResolveSafelyWithWrittenPayload() async throws {
        let actor = PersistenceActor()
        let url = temporaryPersistenceURL()
        let firstPayload = Data("first write".utf8)
        let secondPayload = Data("second write".utf8)

        async let firstOutcome = actor.writeLatest(firstPayload, to: url, options: .atomic)
        async let secondOutcome = actor.writeLatest(secondPayload, to: url, options: .atomic)

        let outcomes = try await [firstOutcome, secondOutcome]
        let reloaded = try await actor.read(from: url)
        let payloadsByOutcome = Array(zip([firstPayload, secondPayload], outcomes))
        let writtenPayloads = payloadsByOutcome.compactMap { payload, outcome in
            outcome == .written ? payload : nil
        }

        XCTAssertTrue(writtenPayloads.contains(reloaded))
        XCTAssertTrue(outcomes.contains(.written))
        XCTAssertTrue(outcomes.allSatisfy { $0 == .written || $0 == .superseded })
    }

    func testRapidRepeatedWritesNeverLeavePartialData() async throws {
        let actor = PersistenceActor()
        let url = temporaryPersistenceURL()
        let payloads = (0..<20).map { Data("payload-\($0)".utf8) }

        try await withThrowingTaskGroup(of: PersistenceWriteOutcome.self) { group in
            for payload in payloads {
                group.addTask {
                    try await actor.writeLatest(payload, to: url, options: .atomic)
                }
            }

            for try await outcome in group {
                XCTAssertTrue(outcome == .written || outcome == .superseded)
            }
        }

        let reloaded = try await actor.read(from: url)
        XCTAssertTrue(payloads.contains(reloaded))
    }

    func testRemoveAfterQueuedWritesRemovesPersistedFile() async throws {
        let actor = PersistenceActor()
        let url = temporaryPersistenceURL()
        let payload = Data("delete should remove persisted data".utf8)

        _ = try await actor.writeLatest(payload, to: url, options: .atomic)

        try await actor.removeAfterQueuedWrites(at: url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func temporaryPersistenceURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceActorTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("payload.json")
    }
}
