import XCTest
@testable import VirtualTrainer

@MainActor
final class CalibrationStoreTests: XCTestCase {
    func testCompletedStatusPersists() throws {
        let url = temporaryCalibrationURL()
        let store = CalibrationStore(fileURL: url)
        let startedAt = Date(timeIntervalSince1970: 1_776_400_000)
        let completedAt = Date(timeIntervalSince1970: 1_776_400_030)

        XCTAssertTrue(
            store.saveCompleted(
                completedReps: 3,
                startedAt: startedAt,
                completedAt: completedAt,
                visibilityPassed: true,
                averageFormScore: 88
            )
        )

        let reloadedStore = CalibrationStore(fileURL: url)
        let record = try XCTUnwrap(reloadedStore.record)
        XCTAssertEqual(reloadedStore.status, .completed)
        XCTAssertTrue(record.isSuccessfulCalibration)
        XCTAssertEqual(record.exerciseType, .squat)
        XCTAssertEqual(record.targetReps, 3)
        XCTAssertEqual(record.completedReps, 3)
        XCTAssertEqual(record.averageFormScore, 88)
    }

    func testSkippedStatusPersists() throws {
        let url = temporaryCalibrationURL()
        let store = CalibrationStore(fileURL: url)

        XCTAssertTrue(
            store.saveSkipped(
                at: Date(timeIntervalSince1970: 1_776_400_100),
                notes: "Skipped in setup."
            )
        )

        let reloadedStore = CalibrationStore(fileURL: url)
        let record = try XCTUnwrap(reloadedStore.record)
        XCTAssertEqual(reloadedStore.loadStatus(), .skipped)
        XCTAssertEqual(record.status, .skipped)
        XCTAssertFalse(record.isSuccessfulCalibration)
        XCTAssertEqual(record.notes, "Skipped in setup.")
    }

    func testSuccessfulThreeRepCalibrationCreatesCompletedRecord() {
        let startedAt = Date(timeIntervalSince1970: 1_776_400_200)
        let completedAt = Date(timeIntervalSince1970: 1_776_400_240)

        let record = CalibrationRecord.completed(
            completedReps: 3,
            startedAt: startedAt,
            completedAt: completedAt,
            visibilityPassed: true,
            averageFormScore: 91.5
        )

        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.exerciseType, CalibrationDefaults.exerciseType)
        XCTAssertEqual(record.targetReps, CalibrationDefaults.targetReps)
        XCTAssertEqual(record.completedReps, 3)
        XCTAssertTrue(record.visibilityPassed)
        XCTAssertTrue(record.isSuccessfulCalibration)
        XCTAssertEqual(record.averageFormScore, 91.5)
    }

    func testLegacyCalibrationRecordJSONWithoutDeletedAtDecodes() throws {
        let record = CalibrationRecord.completed(
            completedReps: 3,
            startedAt: Date(timeIntervalSince1970: 1_776_400_200),
            completedAt: Date(timeIntervalSince1970: 1_776_400_240),
            visibilityPassed: true,
            averageFormScore: 91.5
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try encoder.encode(record)) as? [String: Any]
        )
        object.removeValue(forKey: "deletedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try decoder.decode(CalibrationRecord.self, from: legacyData)

        XCTAssertNil(decoded.deletedAt)
        XCTAssertFalse(decoded.isDeleted)
        XCTAssertTrue(decoded.isSuccessfulCalibration)
    }

    func testServerCompletedAtSurvivesBackendReadinessCopies() throws {
        let startedAt = Date(timeIntervalSince1970: 1_776_400_210)
        let completedAt = Date(timeIntervalSince1970: 1_776_400_240)
        let serverCompletedAt = Date(timeIntervalSince1970: 1_776_400_260)
        let deletedAt = Date(timeIntervalSince1970: 1_776_400_300)
        let record = CalibrationRecord.completed(
            completedReps: 3,
            startedAt: startedAt,
            completedAt: completedAt,
            serverCompletedAt: serverCompletedAt,
            visibilityPassed: true,
            averageFormScore: 91.5
        )

        let accountClaimed = record.withAccountId("calibration-sync-account")
        let tombstoned = accountClaimed.markedDeleted(at: deletedAt)
        let restored = tombstoned.restored()

        XCTAssertEqual(accountClaimed.serverCompletedAt, serverCompletedAt)
        XCTAssertEqual(tombstoned.serverCompletedAt, serverCompletedAt)
        XCTAssertEqual(restored.serverCompletedAt, serverCompletedAt)
    }

    func testTombstonedCalibrationRecordIsNotCompleted() throws {
        let url = temporaryCalibrationURL()
        let completed = CalibrationRecord.completed(
            completedReps: 3,
            startedAt: Date(timeIntervalSince1970: 1_776_400_250),
            completedAt: Date(timeIntervalSince1970: 1_776_400_280),
            visibilityPassed: true,
            averageFormScore: 90
        ).markedDeleted(at: Date(timeIntervalSince1970: 1_776_400_300))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(completed).write(to: url, options: [.atomic])

        let store = CalibrationStore(fileURL: url)

        XCTAssertEqual(store.status, .notStarted)
        XCTAssertFalse(store.hasCompletedCalibration)
        XCTAssertFalse(store.record?.isSuccessfulCalibration ?? true)
        XCTAssertTrue(store.record?.isDeleted ?? false)
    }

    func testCalibrationDoesNotBreakFreeAnalysisMode() {
        let freeContext = LiveSessionContext.freeAnalysis(
            exerciseType: .pushup,
            coach: .good,
            startsActive: true
        )
        let calibrationContext = LiveSessionContext.calibration(
            exerciseType: .squat,
            targetReps: 3,
            coach: .drill,
            startsActive: true
        )

        XCTAssertEqual(freeContext.mode, .freeAnalysis)
        XCTAssertTrue(freeContext.isFreeAnalysis)
        XCTAssertFalse(freeContext.isCalibration)
        XCTAssertEqual(freeContext.target, .open)

        XCTAssertEqual(calibrationContext.mode, .calibration)
        XCTAssertFalse(calibrationContext.isFreeAnalysis)
        XCTAssertTrue(calibrationContext.isCalibration)
        XCTAssertEqual(calibrationContext.target, .reps(3))
        XCTAssertEqual(calibrationContext.coach, .drill)
    }

    func testCalibrationPersistenceDoesNotPolluteWorkoutHistory() {
        let calibrationStore = CalibrationStore(fileURL: temporaryCalibrationURL())
        let historyStore = WorkoutHistoryStore(fileURL: temporaryHistoryURL())

        XCTAssertTrue(
            calibrationStore.saveCompleted(
                completedReps: 3,
                startedAt: Date(timeIntervalSince1970: 1_776_400_300),
                completedAt: Date(timeIntervalSince1970: 1_776_400_330),
                visibilityPassed: true,
                averageFormScore: nil
            )
        )

        XCTAssertEqual(historyStore.aggregateStats(), .empty)
        XCTAssertTrue(historyStore.fetchRecentSummaries().isEmpty)
    }

    func testMissingCameraPermissionCanPersistFailedCalibration() throws {
        let url = temporaryCalibrationURL()
        let store = CalibrationStore(fileURL: url)

        XCTAssertTrue(
            store.saveFailed(
                startedAt: Date(timeIntervalSince1970: 1_776_400_400),
                completedAt: Date(timeIntervalSince1970: 1_776_400_400),
                notes: "Camera permission was unavailable during calibration."
            )
        )

        let reloadedStore = CalibrationStore(fileURL: url)
        let record = try XCTUnwrap(reloadedStore.record)
        XCTAssertEqual(reloadedStore.status, .failed)
        XCTAssertEqual(record.completedReps, 0)
        XCTAssertFalse(record.visibilityPassed)
        XCTAssertEqual(record.notes, "Camera permission was unavailable during calibration.")
    }

    func testIncompleteCompletedRecordIsRejected() {
        let store = CalibrationStore(fileURL: temporaryCalibrationURL())

        XCTAssertFalse(
            store.saveCompleted(
                completedReps: 2,
                startedAt: Date(timeIntervalSince1970: 1_776_400_500),
                completedAt: Date(timeIntervalSince1970: 1_776_400_530),
                visibilityPassed: true,
                averageFormScore: 80
            )
        )

        XCTAssertEqual(store.status, .notStarted)
        XCTAssertNotNil(store.persistenceError)
    }

    private func temporaryCalibrationURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("CalibrationRecord.json")
    }

    private func temporaryHistoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("WorkoutHistory.json")
    }
}
