import Foundation
import Combine

@MainActor
final class CalibrationStore: ObservableObject {
    @Published private(set) var record: CalibrationRecord?
    @Published var persistenceError: String?

    private let fileURL: URL
    private let writeJournal: LocalWriteJournal
    private let decoder = JSONDecoder()
    private let persistenceActor: PersistenceActor
    private var currentAccountId: String?
    private var storedRecord: CalibrationRecord?
    private var persistedStoredRecord: CalibrationRecord?
    private var persistenceGeneration = 0
    private var backendMode: BackendMode = .local
    private var calibrationRepository: (any CalibrationRepository)?
    private var calibrationObservationTask: Task<Void, Never>?
    private var autoObserveRemote = true

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

    init(
        fileURL: URL? = nil,
        accountId: String? = nil,
        writeJournal: LocalWriteJournal? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        let resolvedFileURL = fileURL ?? Self.defaultCalibrationURL()
        self.fileURL = resolvedFileURL
        self.writeJournal = writeJournal ?? LocalWriteJournal(
            fileURL: LocalWriteJournal.defaultJournalURL(alongside: resolvedFileURL),
            persistenceActor: persistenceActor
        )
        self.persistenceActor = persistenceActor
        self.currentAccountId = AccountOwnership.normalizedAccountId(accountId)
        decoder.dateDecodingStrategy = .iso8601
        loadRecord()
    }

    nonisolated deinit {}

    func configureRemoteSync(
        backendMode: BackendMode,
        calibrationRepository: (any CalibrationRepository)?,
        autoObserve: Bool = true
    ) {
        self.backendMode = backendMode
        self.calibrationRepository = backendMode == .firebase ? calibrationRepository : nil
        self.autoObserveRemote = autoObserve
        restartCalibrationObservationIfNeeded()
    }

    func setCurrentAccountId(_ accountId: String?) {
        let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId)
        guard currentAccountId != normalizedAccountId else { return }
        currentAccountId = normalizedAccountId
        applyStoredRecord()
        restartCalibrationObservationIfNeeded()
    }

    var pendingUploadCount: Int {
        storedRecord?.syncMetadata.syncState == .pendingUpload ? 1 : 0
    }

    func pendingCalibrationRecordForSync() -> CalibrationRecord? {
        storedRecord?.syncMetadata.syncState == .pendingUpload ? storedRecord : nil
    }

    @discardableResult
    func loadStatus() -> CalibrationStatus {
        loadRecord()
        return status
    }

    @discardableResult
    func saveCompleted(_ completedRecord: CalibrationRecord, operationId: UUID? = nil) async -> Bool {
        guard completedRecord.status == .completed else {
            persistenceError = "Calibration completion must use a completed record."
            return false
        }
        guard completedRecord.isSuccessfulCalibration else {
            persistenceError = "Calibration needs target reps and camera visibility before it can be completed."
            return false
        }
        return await save(completedRecord, operationId: operationId)
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
    ) async -> Bool {
        await saveCompleted(
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
    ) async -> Bool {
        await save(.skipped(at: date, notes: notes), operationId: operationId)
    }

    @discardableResult
    func saveFailed(_ failedRecord: CalibrationRecord, operationId: UUID? = nil) async -> Bool {
        guard failedRecord.status == .failed else {
            persistenceError = "Calibration failure must use a failed record."
            return false
        }
        return await save(failedRecord, operationId: operationId)
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
    ) async -> Bool {
        await saveFailed(
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

    @discardableResult
    func saveCalibrationRecord(_ record: CalibrationRecord, operationId: UUID? = nil) async -> Bool {
        await save(record, operationId: operationId)
    }

    func resetForDebug() async {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try await persistenceActor.remove(fileURL)
            }
            record = nil
            storedRecord = nil
            persistedStoredRecord = nil
            persistenceError = nil
        } catch {
            persistenceError = "Could not reset calibration: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func claimLocalDataForAccount(id accountId: String, operationId: UUID? = nil) async -> Bool {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            persistenceError = "Account id is required before local calibration data can be claimed."
            return false
        }
        guard let storedRecord, storedRecord.accountId == nil else { return true }

        let writeOperationId = operationId ?? UUID()
        return await save(
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
            persistedStoredRecord = nil
            record = nil
            persistenceError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            storedRecord = try decoder.decode(CalibrationRecord.self, from: data)
            persistedStoredRecord = storedRecord
            applyStoredRecord()
            persistenceError = nil
        } catch {
            storedRecord = nil
            persistedStoredRecord = nil
            record = nil
            persistenceError = "Could not load calibration: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func save(
        _ updatedRecord: CalibrationRecord,
        stampWithCurrentAccount: Bool = true,
        operationId: UUID? = nil,
        markLocalMutation: Bool = true,
        saveRemote: Bool = true,
        recordJournal: Bool = true
    ) async -> Bool {
        let writeOperationId = operationId ?? UUID()

        let accountStampedRecord = stampWithCurrentAccount && markLocalMutation
            ? updatedRecord.withAccountId(
                currentAccountId,
                operationId: writeOperationId,
                now: updatedRecord.completedAt
            )
            : updatedRecord
        let previousStoredRecord = storedRecord
        let previousVisibleRecord = record
        let generation = applyLocalMutation(accountStampedRecord)
        if recordJournal, await writeJournal.contains(operationId: writeOperationId) {
            rollbackLocalMutationIfNeeded(
                generation: generation,
                storedRecord: previousStoredRecord,
                visibleRecord: previousVisibleRecord
            )
            return true
        }
        guard await persist(accountStampedRecord, generation: generation) != nil else { return false }
        if saveRemote {
            guard await saveCalibrationRemotelyIfNeeded(
                accountStampedRecord,
                operationId: writeOperationId
            ) else {
                return false
            }
        }
        if recordJournal {
            await recordWriteOperation(writeOperationId, createdAt: accountStampedRecord.completedAt)
        }
        return true
    }

    private func recordWriteOperation(_ operationId: UUID, createdAt: Date) async {
        _ = await writeJournal.record(
            operationId: operationId,
            entityKind: .calibration,
            createdAt: createdAt
        )
    }

    private func restartCalibrationObservationIfNeeded() {
        calibrationObservationTask?.cancel()
        calibrationObservationTask = nil

        guard backendMode == .firebase,
              autoObserveRemote,
              let calibrationRepository,
              let currentAccountId else {
            return
        }

        calibrationObservationTask = Task { [weak self, calibrationRepository, currentAccountId] in
            do {
                if let loadedRecord = try await calibrationRepository.loadCalibrationRecord(accountId: currentAccountId) {
                    _ = await self?.applyRemoteCalibrationCache(loadedRecord)
                }

                let stream = try await calibrationRepository.observeCalibrationRecord(accountId: currentAccountId)
                for await remoteRecord in stream {
                    guard let remoteRecord else { continue }
                    _ = await self?.applyRemoteCalibrationCache(remoteRecord)
                }
            } catch {
                self?.setRemoteCalibrationError(error)
            }
        }
    }

    private func saveCalibrationRemotelyIfNeeded(
        _ record: CalibrationRecord,
        operationId: UUID
    ) async -> Bool {
        guard backendMode == .firebase,
              let calibrationRepository,
              AccountOwnership.normalizedAccountId(record.accountId) != nil else {
            return true
        }

        do {
            let savedRecord = try await calibrationRepository.saveCalibrationRecord(
                record,
                operationId: operationId
            )
            return await applyRemoteCalibrationCache(savedRecord, allowReplacingPending: true)
        } catch {
            persistenceError = "Could not sync calibration: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func applyRemoteCalibration(
        _ remoteRecord: CalibrationRecord,
        allowReplacingPending: Bool = false
    ) async -> Bool {
        var syncedRecord = remoteRecord
        syncedRecord.syncMetadata = remoteRecord.syncMetadata.markedSynced(
            serverVersion: remoteRecord.syncMetadata.serverVersion
        )
        if let storedRecord {
            if storedRecord.syncMetadata == syncedRecord.syncMetadata {
                return true
            }
            if !allowReplacingPending,
               storedRecord.syncMetadata.syncState == .pendingUpload ||
                storedRecord.syncMetadata.syncState == .conflict {
                return true
            }
        }
        return await save(
            syncedRecord,
            stampWithCurrentAccount: false,
            operationId: UUID(),
            markLocalMutation: false,
            saveRemote: false,
            recordJournal: false
        )
    }

    @discardableResult
    private func applyRemoteCalibrationCache(
        _ remoteRecord: CalibrationRecord,
        allowReplacingPending: Bool = false
    ) async -> Bool {
        await applyRemoteCalibration(remoteRecord, allowReplacingPending: allowReplacingPending)
    }

    @discardableResult
    func markCalibrationConflict(serverVersion: String?, localVersion: String?) async -> Bool {
        guard var storedRecord else { return false }
        storedRecord.syncMetadata = storedRecord.syncMetadata.markedConflict(
            serverVersion: serverVersion,
            localVersion: localVersion
        )
        let generation = applyLocalMutation(storedRecord)
        return await persist(storedRecord, generation: generation) != nil
    }

    private func setRemoteCalibrationError(_ error: Error) {
        persistenceError = "Could not observe calibration sync: \(error.localizedDescription)"
    }

    @discardableResult
    private func persist(_ record: CalibrationRecord, generation: Int) async -> PersistenceWriteOutcome? {
        do {
            let data = try await persistenceActor.encode(
                record,
                outputFormatting: [.prettyPrinted, .sortedKeys]
            )
            let outcome = try await persistenceActor.writeLatest(data, to: fileURL, options: [.atomic])
            if outcome == .written {
                persistedStoredRecord = record
            }
            persistenceError = nil
            return outcome
        } catch {
            rollbackLatestMutationIfNeeded(generation: generation)
            persistenceError = "Could not save calibration: \(error.localizedDescription)"
            return nil
        }
    }

    private func applyLocalMutation(_ record: CalibrationRecord) -> Int {
        persistenceGeneration += 1
        storedRecord = record
        applyStoredRecord()
        return persistenceGeneration
    }

    private func rollbackLatestMutationIfNeeded(generation: Int) {
        guard generation == persistenceGeneration else { return }
        storedRecord = persistedStoredRecord
        applyStoredRecord()
    }

    private func rollbackLocalMutationIfNeeded(
        generation: Int,
        storedRecord previousStoredRecord: CalibrationRecord?,
        visibleRecord previousVisibleRecord: CalibrationRecord?
    ) {
        guard generation == persistenceGeneration else { return }
        storedRecord = previousStoredRecord
        record = previousVisibleRecord
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
