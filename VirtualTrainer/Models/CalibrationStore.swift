import Foundation
import Combine

@MainActor
final class CalibrationStore: ObservableObject {
    @Published private(set) var record: CalibrationRecord?
    @Published var persistenceError: String?

    private let fileURL: URL
    private let writeJournal: LocalWriteJournal
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var currentAccountId: String?
    private var storedRecord: CalibrationRecord?

    var status: CalibrationStatus {
        guard record?.isDeleted != true else { return .notStarted }
        return record?.status ?? .notStarted
    }

    var shouldShowCalibrationGate: Bool {
        status == .notStarted || status == .failed
    }

    var hasCompletedCalibration: Bool {
        record?.isSuccessfulCalibration ?? false
    }

    init(fileURL: URL? = nil, accountId: String? = nil, writeJournal: LocalWriteJournal? = nil) {
        let resolvedFileURL = fileURL ?? Self.defaultCalibrationURL()
        self.fileURL = resolvedFileURL
        self.writeJournal = writeJournal ?? LocalWriteJournal(
            fileURL: LocalWriteJournal.defaultJournalURL(alongside: resolvedFileURL)
        )
        self.currentAccountId = AccountOwnership.normalizedAccountId(accountId)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadRecord()
    }

    nonisolated deinit {}

    func setCurrentAccountId(_ accountId: String?) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        guard currentAccountId != normalizedAccountId else { return }
        currentAccountId = normalizedAccountId
        applyStoredRecord()
    }

    @discardableResult
    func loadStatus() -> CalibrationStatus {
        loadRecord()
        return status
    }

    @discardableResult
    func saveCompleted(_ completedRecord: CalibrationRecord, operationId: UUID? = nil) -> Bool {
        guard completedRecord.status == .completed else {
            persistenceError = "Calibration completion must use a completed record."
            return false
        }
        guard completedRecord.isSuccessfulCalibration else {
            persistenceError = "Calibration needs target reps and camera visibility before it can be completed."
            return false
        }
        return save(completedRecord, operationId: operationId)
    }

    @discardableResult
    func saveCompleted(
        exerciseType: ExerciseType = CalibrationDefaults.exerciseType,
        targetReps: Int = CalibrationDefaults.targetReps,
        completedReps: Int,
        startedAt: Date,
        completedAt: Date,
        visibilityPassed: Bool,
        averageFormScore: Double?,
        notes: String? = nil,
        operationId: UUID? = nil
    ) -> Bool {
        saveCompleted(
            CalibrationRecord.completed(
                exerciseType: exerciseType,
                targetReps: targetReps,
                completedReps: completedReps,
                startedAt: startedAt,
                completedAt: completedAt,
                visibilityPassed: visibilityPassed,
                averageFormScore: averageFormScore,
                notes: notes
            ),
            operationId: operationId
        )
    }

    @discardableResult
    func saveSkipped(
        at date: Date = Date(),
        notes: String? = "Skipped during setup.",
        operationId: UUID? = nil
    ) -> Bool {
        save(.skipped(at: date, notes: notes), operationId: operationId)
    }

    @discardableResult
    func saveFailed(_ failedRecord: CalibrationRecord, operationId: UUID? = nil) -> Bool {
        guard failedRecord.status == .failed else {
            persistenceError = "Calibration failure must use a failed record."
            return false
        }
        return save(failedRecord, operationId: operationId)
    }

    @discardableResult
    func saveFailed(
        exerciseType: ExerciseType = CalibrationDefaults.exerciseType,
        targetReps: Int = CalibrationDefaults.targetReps,
        completedReps: Int = 0,
        startedAt: Date = Date(),
        completedAt: Date = Date(),
        visibilityPassed: Bool = false,
        averageFormScore: Double? = nil,
        notes: String,
        operationId: UUID? = nil
    ) -> Bool {
        saveFailed(
            CalibrationRecord.failed(
                exerciseType: exerciseType,
                targetReps: targetReps,
                completedReps: completedReps,
                startedAt: startedAt,
                completedAt: completedAt,
                visibilityPassed: visibilityPassed,
                averageFormScore: averageFormScore,
                notes: notes
            ),
            operationId: operationId
        )
    }

    func resetForDebug() {
        record = nil
        storedRecord = nil
        persistenceError = nil
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            persistenceError = "Could not reset calibration: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func claimLocalDataForAccount(id accountId: String, operationId: UUID? = nil) -> Bool {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            persistenceError = "Account id is required before local calibration data can be claimed."
            return false
        }
        guard let storedRecord, storedRecord.accountId == nil else { return true }

        let writeOperationId = operationId ?? UUID()
        return save(
            storedRecord.withAccountId(
                normalizedAccountId,
                operationId: writeOperationId,
                now: storedRecord.completedAt
            ),
            stampWithCurrentAccount: false,
            operationId: writeOperationId
        )
    }

    private func loadRecord() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            storedRecord = nil
            record = nil
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            storedRecord = try decoder.decode(CalibrationRecord.self, from: data)
            applyStoredRecord()
            persistenceError = nil
        } catch {
            storedRecord = nil
            record = nil
            persistenceError = "Could not load calibration: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func save(
        _ updatedRecord: CalibrationRecord,
        stampWithCurrentAccount: Bool = true,
        operationId: UUID? = nil
    ) -> Bool {
        let writeOperationId = operationId ?? UUID()
        guard !writeJournal.contains(operationId: writeOperationId) else { return true }

        let previousRecord = record
        let previousStoredRecord = storedRecord
        let accountStampedRecord = stampWithCurrentAccount
            ? updatedRecord.withAccountId(
                currentAccountId,
                operationId: writeOperationId,
                now: updatedRecord.completedAt
            )
            : updatedRecord
        storedRecord = accountStampedRecord
        applyStoredRecord()
        guard persist() else {
            record = previousRecord
            storedRecord = previousStoredRecord
            return false
        }
        recordWriteOperation(writeOperationId, createdAt: accountStampedRecord.completedAt)
        return true
    }

    private func recordWriteOperation(_ operationId: UUID, createdAt: Date) {
        _ = writeJournal.record(
            operationId: operationId,
            entityKind: .calibration,
            createdAt: createdAt
        )
    }

    @discardableResult
    private func persist() -> Bool {
        guard let storedRecord else { return true }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(storedRecord)
            try data.write(to: fileURL, options: [.atomic])
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Could not save calibration: \(error.localizedDescription)"
            return false
        }
    }

    private func applyStoredRecord() {
        guard let storedRecord,
              AccountOwnership.isVisible(
                recordAccountId: storedRecord.accountId,
                currentAccountId: currentAccountId
              )
        else {
            record = nil
            return
        }

        record = storedRecord
    }

    private static func defaultCalibrationURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("CalibrationRecord.json")
    }
}
