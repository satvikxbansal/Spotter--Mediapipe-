import Foundation
import Combine

@MainActor
final class CalibrationStore: ObservableObject {
    @Published private(set) var record: CalibrationRecord?
    @Published var persistenceError: String?

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultCalibrationURL()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadRecord()
    }

    nonisolated deinit {}

    @discardableResult
    func loadStatus() -> CalibrationStatus {
        loadRecord()
        return status
    }

    @discardableResult
    func saveCompleted(_ completedRecord: CalibrationRecord) -> Bool {
        guard completedRecord.status == .completed else {
            persistenceError = "Calibration completion must use a completed record."
            return false
        }
        guard completedRecord.isSuccessfulCalibration else {
            persistenceError = "Calibration needs target reps and camera visibility before it can be completed."
            return false
        }
        return save(completedRecord)
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
        notes: String? = nil
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
            )
        )
    }

    @discardableResult
    func saveSkipped(
        at date: Date = Date(),
        notes: String? = "Skipped during setup."
    ) -> Bool {
        save(.skipped(at: date, notes: notes))
    }

    @discardableResult
    func saveFailed(_ failedRecord: CalibrationRecord) -> Bool {
        guard failedRecord.status == .failed else {
            persistenceError = "Calibration failure must use a failed record."
            return false
        }
        return save(failedRecord)
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
        notes: String
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
            )
        )
    }

    func resetForDebug() {
        record = nil
        persistenceError = nil
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            persistenceError = "Could not reset calibration: \(error.localizedDescription)"
        }
    }

    private func loadRecord() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            record = nil
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            record = try decoder.decode(CalibrationRecord.self, from: data)
            persistenceError = nil
        } catch {
            record = nil
            persistenceError = "Could not load calibration: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func save(_ updatedRecord: CalibrationRecord) -> Bool {
        let previousRecord = record
        record = updatedRecord
        guard persist() else {
            record = previousRecord
            return false
        }
        return true
    }

    @discardableResult
    private func persist() -> Bool {
        guard let record else { return true }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(record)
            try data.write(to: fileURL, options: [.atomic])
            persistenceError = nil
            return true
        } catch {
            persistenceError = "Could not save calibration: \(error.localizedDescription)"
            return false
        }
    }

    private static func defaultCalibrationURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("CalibrationRecord.json")
    }
}
