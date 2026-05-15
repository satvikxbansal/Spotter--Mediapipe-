import FirebaseFirestore
import XCTest
@testable import VirtualTrainer

@MainActor
final class FirestoreRepositoryTests: XCTestCase {
    private let accountId = "phase-16d-account"
    private let now = Date(timeIntervalSince1970: 1_779_200_000)

    func testProfileRepositoryReturnsConflictWhenRemoteIsNewerDifferentOperation() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreProfileRepository(database: database)
        let path = try FirestorePathBuilder.profileDocument(uid: accountId)
        let serverProfile = makeProfile(
            updatedAt: now.addingTimeInterval(120),
            operationId: fixedUUID(160_001)
        )
        try database.seed(
            path: path,
            dto: mapToProfileDocument(serverProfile),
            updateTime: now.addingTimeInterval(121)
        )
        let localProfile = makeProfile(
            displayName: "Older Local Athlete",
            updatedAt: now,
            operationId: fixedUUID(160_002)
        )

        let savedProfile = try await repository.saveProfile(
            localProfile,
            operationId: fixedUUID(160_002)
        )

        XCTAssertEqual(savedProfile.syncMetadata.syncState, .conflict)
        XCTAssertEqual(savedProfile.displayName, "Older Local Athlete")
        XCTAssertEqual(database.writeCount(for: path), 0)
    }

    func testProfileRepositoryRetryWithSameOperationIdDoesNotWriteAgain() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreProfileRepository(database: database)
        let path = try FirestorePathBuilder.profileDocument(uid: accountId)
        let operationId = fixedUUID(160_011)
        let profile = makeProfile(updatedAt: now, operationId: operationId)

        _ = try await repository.saveProfile(profile, operationId: operationId)
        _ = try await repository.saveProfile(profile, operationId: operationId)

        XCTAssertEqual(database.writeCount(for: path), 1)
    }

    func testProfileObserverEmitsInitialStateThenRemoteChange() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreProfileRepository(database: database)
        let path = try FirestorePathBuilder.profileDocument(uid: accountId)
        let initialProfile = makeProfile(displayName: "Initial Athlete", updatedAt: now)
        let changedProfile = makeProfile(
            displayName: "Changed Athlete",
            updatedAt: now.addingTimeInterval(90)
        )
        try database.seed(path: path, dto: mapToProfileDocument(initialProfile), updateTime: now)

        let stream = try await repository.observeProfile(accountId: accountId)
        var iterator = stream.makeAsyncIterator()
        let observedInitial = try await nextProfile(from: &iterator)

        try database.seed(
            path: path,
            dto: mapToProfileDocument(changedProfile),
            updateTime: now.addingTimeInterval(90),
            notify: true
        )
        let observedChanged = try await nextProfile(from: &iterator)

        XCTAssertEqual(observedInitial?.displayName, "Initial Athlete")
        XCTAssertEqual(observedChanged?.displayName, "Changed Athlete")
    }

    func testFirebasePartialUsesWorkoutRepositoryAndKeepsTrophyInsightRepositoriesLocal() async {
        let dependencies = AppDependencies.firebasePartial()

        XCTAssertEqual(dependencies.backendMode, .firebase)
        XCTAssertTrue(dependencies.auth is FirebaseAuthRepository)
        XCTAssertTrue(dependencies.profile is FirestoreProfileRepository)
        XCTAssertTrue(dependencies.theme is FirestoreThemeRepository)
        XCTAssertTrue(dependencies.calibration is FirestoreCalibrationRepository)
        XCTAssertTrue(dependencies.plans is FirestorePlanRepository)
        XCTAssertTrue(dependencies.workouts is FirestoreWorkoutRepository)
        XCTAssertTrue(dependencies.trophies is LocalTrophyRepository)
        XCTAssertTrue(dependencies.insights is LocalInsightRepository)
    }

    func testWorkoutRepositoryWritesCompactWorkoutAndDeterministicSetDocuments() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreWorkoutRepository(database: database)
        let operationId = fixedUUID(170_001)
        let summary = makeWorkoutSummary(
            id: fixedUUID(170_002),
            sets: [
                makeSetSummary(exerciseType: .squat, setIndex: 0, formScores: [92, 88]),
                makeSetSummary(exerciseType: .pushup, setIndex: 1, formScores: [84, 81])
            ],
            operationId: operationId
        )

        let saved = try await repository.saveWorkoutSummary(summary, operationId: operationId)

        let workoutPath = try FirestorePathBuilder.workoutDocument(uid: accountId, workoutId: summary.id)
        let firstSetPath = try FirestorePathBuilder.setDocument(
            uid: accountId,
            workoutId: summary.id,
            setId: "squat-set-0"
        )
        let secondSetPath = try FirestorePathBuilder.setDocument(
            uid: accountId,
            workoutId: summary.id,
            setId: "pushup-set-1"
        )

        XCTAssertEqual(saved.syncMetadata.syncState, .synced)
        XCTAssertEqual(saved.exerciseSummaries.count, 2)
        XCTAssertNotNil(database.document(at: workoutPath))
        XCTAssertNotNil(database.document(at: firstSetPath))
        XCTAssertNotNil(database.document(at: secondSetPath))
        XCTAssertEqual(database.document(at: firstSetPath)?.data["operationId"] as? String, operationId.uuidString.lowercased())
        XCTAssertNil(database.document(at: workoutPath)?.data["exerciseSummaries"])
    }

    func testWorkoutRepositoryRetryWithSameOperationIdDoesNotDuplicateSetDocuments() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreWorkoutRepository(database: database)
        let operationId = fixedUUID(170_011)
        let summary = makeWorkoutSummary(
            id: fixedUUID(170_012),
            sets: [
                makeSetSummary(exerciseType: .squat, setIndex: 0, formScores: [90]),
                makeSetSummary(exerciseType: .squat, setIndex: 1, formScores: [91])
            ],
            operationId: operationId
        )

        _ = try await repository.saveWorkoutSummary(summary, operationId: operationId)
        let stateAfterFirstSave = database.snapshot()
        _ = try await repository.saveWorkoutSummary(summary, operationId: operationId)

        XCTAssertEqual(database.snapshot().keys.sorted(), stateAfterFirstSave.keys.sorted())
        XCTAssertEqual(database.documents(in: try FirestorePathBuilder.setsCollection(uid: accountId, workoutId: summary.id)).count, 2)
    }

    func testWorkoutRepositorySoftDeleteOmitsRecentAndLoadWorkout() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreWorkoutRepository(database: database)
        let summary = makeWorkoutSummary(id: fixedUUID(170_021), operationId: fixedUUID(170_022))

        _ = try await repository.saveWorkoutSummary(summary, operationId: fixedUUID(170_022))
        let recentBeforeDelete = try await repository.loadRecentWorkouts(
            accountId: accountId,
            limit: 10,
            since: nil
        )
        XCTAssertEqual(recentBeforeDelete.map(\.id), [summary.id])

        try await repository.deleteWorkout(
            accountId: accountId,
            id: summary.id,
            operationId: fixedUUID(170_023)
        )

        let workoutPath = try FirestorePathBuilder.workoutDocument(uid: accountId, workoutId: summary.id)
        let recentAfterDelete = try await repository.loadRecentWorkouts(
            accountId: accountId,
            limit: 10,
            since: nil
        )
        let loadedAfterDelete = try await repository.loadWorkout(accountId: accountId, id: summary.id)
        XCTAssertNotNil(database.document(at: workoutPath)?.data["deletedAt"])
        XCTAssertTrue(recentAfterDelete.isEmpty)
        XCTAssertNil(loadedAfterDelete)
    }

    func testWorkoutRepositoryObserverEmitsCompactSummariesWithoutSets() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreWorkoutRepository(database: database)
        let stream = try await repository.observeRecentWorkouts(accountId: accountId, limit: 5)
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next() ?? []

        let summary = makeWorkoutSummary(id: fixedUUID(170_031), operationId: fixedUUID(170_032))
        _ = try await repository.saveWorkoutSummary(summary, operationId: fixedUUID(170_032))
        let observed = await iterator.next() ?? []

        XCTAssertTrue(initial.isEmpty)
        XCTAssertEqual(observed.map(\.id), [summary.id])
        XCTAssertEqual(observed.first?.exerciseSummaries.count, 0)
    }

    private func nextProfile(
        from iterator: inout AsyncStream<UserProfile?>.Iterator
    ) async throws -> UserProfile? {
        await iterator.next() ?? nil
    }

    private func makeProfile(
        displayName: String = "Repository Athlete",
        updatedAt: Date,
        operationId: UUID = UUID()
    ) -> UserProfile {
        UserProfile(
            id: fixedUUID(900_001),
            accountId: accountId,
            displayName: displayName,
            genderIdentity: .preferNotToSay,
            age: 33,
            height: 174,
            heightUnit: .metric,
            weight: 70,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .beginner,
            equipment: [.bodyweight, .mat],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            limitations: [.wristSensitive],
            preferredSessionLength: .twentyFive,
            timezoneIdentifier: "UTC",
            onboardingCompletedAt: now.addingTimeInterval(-600),
            createdAt: now.addingTimeInterval(-600),
            updatedAt: updatedAt,
            syncMetadata: SyncMetadata(
                localUpdatedAt: updatedAt,
                lastSyncedAt: nil,
                serverVersion: nil,
                syncState: .pendingUpload,
                pendingOperationId: operationId
            )
        )
    }

    private func makeWorkoutSummary(
        id: UUID,
        sets: [ExerciseSetSummary]? = nil,
        operationId: UUID
    ) -> WorkoutSessionSummary {
        let exerciseSummaries = sets ?? [
            makeSetSummary(exerciseType: .squat, setIndex: 0, formScores: [90, 86])
        ]
        let repEvents = exerciseSummaries.flatMap(\.repQualityEvents)
        let cueEvents = exerciseSummaries.flatMap(\.cueEvents)

        return WorkoutSessionSummary(
            id: id,
            accountId: accountId,
            mode: .plannedWorkout,
            planId: fixedUUID(170_900),
            planTitle: "Firestore Workout Repo",
            title: "Firestore Workout Repo",
            goal: "Sync derived evidence.",
            coach: .good,
            startedAt: now.addingTimeInterval(-600),
            endedAt: now,
            durationSeconds: 600,
            totalReps: repEvents.count,
            totalHoldSeconds: 0,
            averageFormScore: average(repEvents.compactMap(\.formScore).map(Double.init)),
            completionPercent: 1,
            exerciseSummaries: exerciseSummaries,
            topCue: cueEvents.first,
            effortSummary: "Peak effort reached 50%. Solid working intensity.",
            structuredEffortSummary: StructuredEffortSummary.build(
                repQualityEvents: repEvents,
                peakEffort: 0.5
            ),
            createdAt: now.addingTimeInterval(1),
            syncMetadata: SyncMetadata(
                localUpdatedAt: now,
                lastSyncedAt: nil,
                serverVersion: nil,
                syncState: .pendingUpload,
                pendingOperationId: operationId
            )
        )
    }

    private func makeSetSummary(
        exerciseType: ExerciseType,
        setIndex: Int,
        formScores: [Int]
    ) -> ExerciseSetSummary {
        let repEvents = formScores.enumerated().map { index, score in
            RepQualityEvent(
                id: fixedUUID(171_000 + setIndex * 100 + index),
                exerciseType: exerciseType,
                setIndex: setIndex,
                repIndex: index + 1,
                timestamp: now.addingTimeInterval(TimeInterval(index * 4)),
                secondsIntoSet: TimeInterval(index * 4),
                formScore: score,
                formGrade: FormScore.Grade.from(score: score).rawValue,
                phase: RepPhase.up.rawValue,
                cueMessageNearRep: index == 0 ? nil : "Keep the rep smooth.",
                cueSeverityNearRep: index == 0 ? nil : .warning,
                effortAtRep: 0.4 + Double(index) * 0.05
            )
        }
        let cueEvents = [
            CueEvent(
                id: fixedUUID(172_000 + setIndex),
                timestamp: now.addingTimeInterval(5),
                exerciseType: exerciseType,
                cueMessage: "Keep the rep smooth.",
                severity: .warning,
                setIndex: setIndex,
                repIndex: formScores.count,
                secondsIntoSet: 8,
                formScoreAtEvent: formScores.last
            )
        ]
        let qualitySummary = SetQualitySummary.build(
            repQualityEvents: repEvents,
            cueEvents: cueEvents
        )

        return ExerciseSetSummary(
            exerciseType: exerciseType,
            setIndex: setIndex,
            target: .reps(formScores.count),
            achievedReps: formScores.count,
            achievedHoldSeconds: 0,
            averageFormScore: qualitySummary.averageFormScore,
            cueEvents: cueEvents,
            qualitySummary: qualitySummary,
            repQualityEvents: repEvents,
            completionSource: .targetMet,
            completedAt: now.addingTimeInterval(60 + TimeInterval(setIndex)),
            durationSeconds: 60,
            peakEffort: 0.5,
            bestCue: "Strong tempo.",
            worstCue: "Late wobble."
        )
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }
}

@MainActor
private final class InMemoryFirestoreDocumentDatabase: FirestoreDocumentDatabase {
    private var documents: [String: FirestoreStoredDocument] = [:]
    private var writeCounts: [String: Int] = [:]
    private var listeners: [String: [UUID: (Result<FirestoreStoredDocument?, Error>) -> Void]] = [:]
    private var queryListeners: [UUID: QueryListener] = [:]
    private var versionCounter = 0

    private struct QueryListener {
        let collectionPath: String
        let filters: [FirestoreQueryFilter]
        let orderBy: String?
        let descending: Bool
        let limit: Int?
        let onChange: (Result<[FirestoreStoredDocument], Error>) -> Void
    }

    func seed<T: Encodable>(
        path: String,
        dto: T,
        updateTime: Date,
        notify: Bool = false
    ) throws {
        let payload = try FirestoreEncodingHelpers.payload(from: dto)
        documents[path] = FirestoreStoredDocument(
            path: path,
            data: normalizeWritePayload(payload, updateTime: updateTime),
            updateTime: updateTime
        )
        if notify {
            notifyListeners(for: path)
        }
    }

    func writeCount(for path: String) -> Int {
        writeCounts[path] ?? 0
    }

    func document(at path: String) -> FirestoreStoredDocument? {
        documents[path]
    }

    func snapshot() -> [String: FirestoreStoredDocument] {
        documents
    }

    func documents(in collectionPath: String) -> [FirestoreStoredDocument] {
        collectionDocuments(
            collectionPath: collectionPath,
            filters: [],
            orderBy: nil,
            descending: false,
            limit: nil
        )
    }

    func getDocument(path: String) async throws -> FirestoreStoredDocument? {
        documents[path]
    }

    func queryDocuments(
        collectionPath: String,
        filters: [FirestoreQueryFilter],
        orderBy: String?,
        descending: Bool,
        limit: Int?
    ) async throws -> [FirestoreStoredDocument] {
        collectionDocuments(
            collectionPath: collectionPath,
            filters: filters,
            orderBy: orderBy,
            descending: descending,
            limit: limit
        )
    }

    func runTransaction(
        _ update: @escaping (FirestoreRepositoryTransaction) throws -> Any?
    ) async throws -> Any? {
        let transaction = InMemoryFirestoreRepositoryTransaction(documents: documents)
        let result = try update(transaction)
        for write in transaction.writes {
            apply(write)
        }
        return result
    }

    func commitBatch(
        _ update: @escaping (FirestoreRepositoryBatch) throws -> Void
    ) async throws {
        let batch = InMemoryFirestoreRepositoryBatch()
        try update(batch)
        for write in batch.writes {
            apply(write)
        }
    }

    func listenDocument(
        path: String,
        onChange: @escaping (Result<FirestoreStoredDocument?, Error>) -> Void
    ) -> FirestoreListenerHandle {
        let id = UUID()
        listeners[path, default: [:]][id] = onChange
        onChange(.success(documents[path]))
        return InMemoryFirestoreListenerHandle { [weak self] in
            self?.listeners[path]?.removeValue(forKey: id)
        }
    }

    func listenQuery(
        collectionPath: String,
        filters: [FirestoreQueryFilter],
        orderBy: String?,
        descending: Bool,
        limit: Int?,
        onChange: @escaping (Result<[FirestoreStoredDocument], Error>) -> Void
    ) -> FirestoreListenerHandle {
        let id = UUID()
        queryListeners[id] = QueryListener(
            collectionPath: collectionPath,
            filters: filters,
            orderBy: orderBy,
            descending: descending,
            limit: limit,
            onChange: onChange
        )
        notifyQueryListener(id)
        return InMemoryFirestoreListenerHandle { [weak self] in
            self?.queryListeners.removeValue(forKey: id)
        }
    }

    private func apply(_ write: InMemoryFirestoreRepositoryTransaction.Write) {
        versionCounter += 1
        let updateTime = Date(timeIntervalSince1970: 1_779_300_000 + TimeInterval(versionCounter))
        switch write.kind {
        case .set(let payload, let merge):
            let existing = merge ? documents[write.path]?.data ?? [:] : [:]
            documents[write.path] = FirestoreStoredDocument(
                path: write.path,
                data: deepMerge(
                    existing,
                    normalizeWritePayload(payload, updateTime: updateTime)
                ),
                updateTime: updateTime
            )
        case .update(let payload):
            let existing = documents[write.path]?.data ?? [:]
            documents[write.path] = FirestoreStoredDocument(
                path: write.path,
                data: deepMerge(
                    existing,
                    normalizeWritePayload(payload, updateTime: updateTime)
                ),
                updateTime: updateTime
            )
        }
        writeCounts[write.path, default: 0] += 1
        notifyListeners(for: write.path)
        notifyQueryListeners()
    }

    private func notifyListeners(for path: String) {
        listeners[path]?.values.forEach {
            $0(.success(documents[path]))
        }
    }

    private func notifyQueryListeners() {
        for id in queryListeners.keys {
            notifyQueryListener(id)
        }
    }

    private func notifyQueryListener(_ id: UUID) {
        guard let listener = queryListeners[id] else { return }
        listener.onChange(
            .success(
                collectionDocuments(
                    collectionPath: listener.collectionPath,
                    filters: listener.filters,
                    orderBy: listener.orderBy,
                    descending: listener.descending,
                    limit: listener.limit
                )
            )
        )
    }

    private func collectionDocuments(
        collectionPath: String,
        filters: [FirestoreQueryFilter],
        orderBy: String?,
        descending: Bool,
        limit: Int?
    ) -> [FirestoreStoredDocument] {
        let prefix = collectionPath + "/"
        var matches = documents.values.filter { document in
            guard document.path.hasPrefix(prefix),
                  !document.path.dropFirst(prefix.count).contains("/") else {
                return false
            }
            return filters.allSatisfy { filter in
                guard let value = document.data[filter.field] else { return false }
                if value is NSNull, filter.value is NSNull {
                    return true
                }
                return String(describing: value) == String(describing: filter.value)
            }
        }

        if let orderBy {
            matches.sort {
                let lhs = $0.data[orderBy].map { String(describing: $0) } ?? ""
                let rhs = $1.data[orderBy].map { String(describing: $0) } ?? ""
                return descending ? lhs > rhs : lhs < rhs
            }
        }

        if let limit {
            matches = Array(matches.prefix(max(limit, 0)))
        }
        return matches
    }

    private func normalizeWritePayload(_ payload: [String: Any], updateTime: Date) -> [String: Any] {
        payload.reduce(into: [String: Any]()) { result, pair in
            result[pair.key] = normalizeWriteValue(pair.value, updateTime: updateTime)
        }
    }

    private func normalizeWriteValue(_ value: Any, updateTime: Date) -> Any {
        if let dictionary = value as? [String: Any] {
            return normalizeWritePayload(dictionary, updateTime: updateTime)
        }
        if let array = value as? [Any] {
            return array.map { normalizeWriteValue($0, updateTime: updateTime) }
        }
        if value is NSNull {
            return NSNull()
        }
        if String(describing: type(of: value)).contains("FieldValue") {
            return FirestoreVersionStrings.string(from: updateTime)
        }
        return value
    }

    private func deepMerge(_ lhs: [String: Any], _ rhs: [String: Any]) -> [String: Any] {
        rhs.reduce(into: lhs) { result, pair in
            if let lhsNested = result[pair.key] as? [String: Any],
               let rhsNested = pair.value as? [String: Any] {
                result[pair.key] = deepMerge(lhsNested, rhsNested)
            } else {
                result[pair.key] = pair.value
            }
        }
    }
}

private final class InMemoryFirestoreRepositoryTransaction: FirestoreRepositoryTransaction {
    enum WriteKind {
        case set([String: Any], merge: Bool)
        case update([String: Any])
    }

    struct Write {
        let path: String
        let kind: WriteKind
    }

    private let documents: [String: FirestoreStoredDocument]
    private(set) var writes: [Write] = []

    init(documents: [String: FirestoreStoredDocument]) {
        self.documents = documents
    }

    func getDocument(path: String) throws -> FirestoreStoredDocument? {
        documents[path]
    }

    func setData(_ data: [String: Any], path: String, merge: Bool) throws {
        writes.append(Write(path: path, kind: .set(data, merge: merge)))
    }

    func updateData(_ data: [String: Any], path: String) throws {
        writes.append(Write(path: path, kind: .update(data)))
    }
}

private final class InMemoryFirestoreRepositoryBatch: FirestoreRepositoryBatch {
    private(set) var writes: [InMemoryFirestoreRepositoryTransaction.Write] = []

    func setData(_ data: [String: Any], path: String, merge: Bool) throws {
        writes.append(
            InMemoryFirestoreRepositoryTransaction.Write(
                path: path,
                kind: .set(data, merge: merge)
            )
        )
    }

    func updateData(_ data: [String: Any], path: String) throws {
        writes.append(
            InMemoryFirestoreRepositoryTransaction.Write(
                path: path,
                kind: .update(data)
            )
        )
    }
}

private final class InMemoryFirestoreListenerHandle: FirestoreListenerHandle {
    private let onRemove: () -> Void

    init(onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
    }

    func remove() {
        onRemove()
    }
}
