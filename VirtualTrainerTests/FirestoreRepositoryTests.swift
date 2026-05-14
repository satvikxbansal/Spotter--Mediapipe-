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

    func testFirebasePartialKeepsWorkoutTrophyAndInsightRepositoriesLocal() async {
        let dependencies = AppDependencies.firebasePartial()

        XCTAssertEqual(dependencies.backendMode, .firebase)
        XCTAssertTrue(dependencies.auth is FirebaseAuthRepository)
        XCTAssertTrue(dependencies.profile is FirestoreProfileRepository)
        XCTAssertTrue(dependencies.theme is FirestoreThemeRepository)
        XCTAssertTrue(dependencies.calibration is FirestoreCalibrationRepository)
        XCTAssertTrue(dependencies.plans is FirestorePlanRepository)
        XCTAssertTrue(dependencies.workouts is LocalWorkoutRepository)
        XCTAssertTrue(dependencies.trophies is LocalTrophyRepository)
        XCTAssertTrue(dependencies.insights is LocalInsightRepository)
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

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }
}

@MainActor
private final class InMemoryFirestoreDocumentDatabase: FirestoreDocumentDatabase {
    private var documents: [String: FirestoreStoredDocument] = [:]
    private var writeCounts: [String: Int] = [:]
    private var listeners: [String: [UUID: (Result<FirestoreStoredDocument?, Error>) -> Void]] = [:]
    private var versionCounter = 0

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
        let prefix = collectionPath + "/"
        var matches = documents.values.filter { document in
            guard document.path.hasPrefix(prefix),
                  !document.path.dropFirst(prefix.count).contains("/") else {
                return false
            }
            return filters.allSatisfy { filter in
                document.data[filter.field].map { String(describing: $0) == String(describing: filter.value) } ?? false
            }
        }

        if let orderBy {
            matches.sort {
                let lhs = $0.data[orderBy].map(String.init(describing:)) ?? ""
                let rhs = $1.data[orderBy].map(String.init(describing:)) ?? ""
                return descending ? lhs > rhs : lhs < rhs
            }
        }

        if let limit {
            matches = Array(matches.prefix(max(limit, 0)))
        }
        return matches
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
    }

    private func notifyListeners(for path: String) {
        listeners[path]?.values.forEach {
            $0(.success(documents[path]))
        }
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

private final class InMemoryFirestoreListenerHandle: FirestoreListenerHandle {
    private let onRemove: () -> Void

    init(onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
    }

    func remove() {
        onRemove()
    }
}
