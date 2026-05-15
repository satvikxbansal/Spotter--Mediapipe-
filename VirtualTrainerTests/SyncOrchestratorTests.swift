import XCTest
@testable import VirtualTrainer

@MainActor
final class SyncOrchestratorTests: XCTestCase {
    private let accountId = "phase-16g-account"
    private let now = Date(timeIntervalSince1970: 1_779_800_000)

    func testLocalModeNoopSyncOperationsSucceed() async throws {
        let orchestrator = SyncOrchestrator(dependencies: .local())

        try await orchestrator.performFullSync()
        try await orchestrator.observeRemote()
        try await orchestrator.enqueueDirtyWrites()

        XCTAssertEqual(orchestrator.backendMode, .local)
        XCTAssertEqual(orchestrator.status, .idle)
        XCTAssertNotNil(orchestrator.lastSyncedAt)
    }

    func testPendingUploadPushesThroughMatchingRepository() async throws {
        let stores = makeStores()
        let repositories = SyncTestRepositories()
        let orchestrator = makeOrchestrator(stores: stores, repositories: repositories)
        let operationId = fixedUUID(16_001)

        let didSaveProfile = await stores.profileStore.saveProfile(
            makeProfile(displayName: "Pending Push"),
            operationId: operationId
        )
        XCTAssertTrue(didSaveProfile)

        try await orchestrator.pushPendingLocal(accountId: accountId)

        XCTAssertEqual(repositories.profile.savedProfiles.count, 1)
        XCTAssertEqual(repositories.profile.savedOperationIds, [operationId])
        XCTAssertEqual(stores.profileStore.pendingUploadCount, 0)
        XCTAssertEqual(orchestrator.status, .idle)
    }

    func testFullSyncDoesNotClobberPendingProfileBeforePush() async throws {
        let stores = makeStores()
        let repositories = SyncTestRepositories()
        let orchestrator = makeOrchestrator(stores: stores, repositories: repositories)
        repositories.profile.profile = makeProfile(
            displayName: "Remote Older",
            syncMetadata: SyncMetadata(
                localUpdatedAt: now.addingTimeInterval(-60),
                lastSyncedAt: now,
                serverVersion: "profile-remote-v1",
                syncState: .synced,
                pendingOperationId: nil
            )
        )

        let didSaveProfile = await stores.profileStore.saveProfile(
            makeProfile(displayName: "Local Pending"),
            operationId: fixedUUID(16_006)
        )
        XCTAssertTrue(didSaveProfile)

        try await orchestrator.performFullSync(accountId: accountId)

        XCTAssertEqual(repositories.profile.savedProfiles.count, 1)
        XCTAssertEqual(repositories.profile.savedProfiles.first?.displayName, "Local Pending")
        XCTAssertEqual(stores.profileStore.profile?.displayName, "Local Pending")
        XCTAssertEqual(stores.profileStore.pendingUploadCount, 0)
    }

    func testFullSyncDoesNotClobberPendingCalibrationBeforePush() async throws {
        let stores = makeStores()
        let repositories = SyncTestRepositories()
        let orchestrator = makeOrchestrator(stores: stores, repositories: repositories)
        repositories.calibration.record = makeCalibrationRecord(
            averageFormScore: 70,
            syncMetadata: SyncMetadata(
                localUpdatedAt: now.addingTimeInterval(-60),
                lastSyncedAt: now,
                serverVersion: "calibration-remote-v1",
                syncState: .synced,
                pendingOperationId: nil
            )
        )

        let didSaveCalibration = await stores.calibrationStore.saveCompleted(
            makeCalibrationRecord(averageFormScore: 94),
            operationId: fixedUUID(16_007)
        )
        XCTAssertTrue(didSaveCalibration)

        try await orchestrator.performFullSync(accountId: accountId)

        XCTAssertEqual(repositories.calibration.savedRecords.count, 1)
        XCTAssertEqual(repositories.calibration.savedRecords.first?.averageFormScore, 94)
        XCTAssertEqual(stores.calibrationStore.record?.averageFormScore, 94)
        XCTAssertEqual(stores.calibrationStore.pendingUploadCount, 0)
    }

    func testConflictSurfacesAndSkipsFurtherWritesForRecord() async throws {
        let stores = makeStores()
        let repositories = SyncTestRepositories()
        let conflictsStore = SyncConflictsStore(fileURL: temporaryURL(named: "Conflicts.json"))
        let orchestrator = makeOrchestrator(
            stores: stores,
            repositories: repositories,
            conflictsStore: conflictsStore
        )

        repositories.profile.saveError = RepositoryError.conflict(
            serverVersion: "server-profile-v2",
            localVersion: "local-profile-v1"
        )
        let didSaveProfile = await stores.profileStore.saveProfile(
            makeProfile(displayName: "Conflicting Push"),
            operationId: fixedUUID(16_011)
        )
        XCTAssertTrue(didSaveProfile)

        try await orchestrator.pushPendingLocal(accountId: accountId)
        try await orchestrator.pushPendingLocal(accountId: accountId)

        XCTAssertEqual(repositories.profile.saveAttemptCount, 1)
        XCTAssertEqual(conflictsStore.events.count, 1)
        XCTAssertEqual(conflictsStore.events.first?.entityKind, .profile)
        XCTAssertEqual(stores.profileStore.profile?.syncMetadata.syncState, .conflict)
        XCTAssertEqual(orchestrator.status, .conflict)
    }

    func testListenerEmissionIsDeduplicatedWhenLocalRecordAlreadySynced() async throws {
        let stores = makeStores()
        let repositories = SyncTestRepositories()
        let orchestrator = makeOrchestrator(stores: stores, repositories: repositories)
        let remoteProfile = makeProfile(
            displayName: "Already Synced",
            syncMetadata: SyncMetadata(
                localUpdatedAt: now,
                lastSyncedAt: now,
                serverVersion: "profile-v1",
                syncState: .synced,
                pendingOperationId: nil
            )
        )

        let didApplyRemoteProfile = await stores.profileStore.applyRemoteProfile(remoteProfile)
        XCTAssertTrue(didApplyRemoteProfile)
        try await orchestrator.startListeners(accountId: accountId)
        repositories.profile.emit(remoteProfile)

        let didApplyListenerEmission = await waitUntil { orchestrator.lastSyncedAt != nil }
        XCTAssertTrue(didApplyListenerEmission)
        XCTAssertEqual(stores.profileStore.profile?.syncMetadata.serverVersion, "profile-v1")
        XCTAssertEqual(stores.profileStore.pendingUploadCount, 0)
        XCTAssertEqual(repositories.profile.savedProfiles.count, 0)
    }

    func testTombstonePushAndPullHidesDeletedWorkoutOnAnotherStore() async throws {
        let storesA = makeStores(named: "DeviceA")
        let storesB = makeStores(named: "DeviceB")
        let repositories = SyncTestRepositories()
        let orchestratorA = makeOrchestrator(stores: storesA, repositories: repositories)
        let orchestratorB = makeOrchestrator(stores: storesB, repositories: repositories)
        let workoutId = fixedUUID(16_021)
        let summary = makeWorkoutSummary(id: workoutId)

        let didSaveWorkout = await storesA.workoutHistoryStore.addSummary(
            summary,
            operationId: fixedUUID(16_022)
        )
        XCTAssertTrue(didSaveWorkout)
        try await orchestratorA.pushPendingLocal(accountId: accountId)
        try await orchestratorB.pullRemote(accountId: accountId)

        XCTAssertEqual(storesB.workoutHistoryStore.fetchSummary(id: workoutId)?.id, workoutId)

        let didDeleteWorkout = await storesB.workoutHistoryStore.deleteSummary(
            id: workoutId,
            deletedAt: now.addingTimeInterval(60),
            operationId: fixedUUID(16_023)
        )
        XCTAssertTrue(didDeleteWorkout)
        try await orchestratorB.pushPendingLocal(accountId: accountId)
        try await orchestratorA.pullRemote(accountId: accountId)

        XCTAssertNotNil(repositories.workout.deletedWorkout(at: workoutId)?.deletedAt)
        XCTAssertNil(storesA.workoutHistoryStore.fetchSummary(id: workoutId))
        XCTAssertEqual(storesA.workoutHistoryStore.fetchDeletedSummaries().map(\.id), [workoutId])
    }

    func testLiveWorkoutGuardDefersPushUntilWorkoutEnds() async throws {
        let stores = makeStores()
        let repositories = SyncTestRepositories()
        let orchestrator = makeOrchestrator(stores: stores, repositories: repositories)

        let didSaveProfile = await stores.profileStore.saveProfile(
            makeProfile(displayName: "Live Guard"),
            operationId: fixedUUID(16_031)
        )
        XCTAssertTrue(didSaveProfile)

        WorkoutSessionContext.markLiveStarted()
        defer { WorkoutSessionContext.markLiveEnded() }

        try await orchestrator.pushPendingLocal(accountId: accountId)

        XCTAssertEqual(orchestrator.status, .deferred)
        XCTAssertEqual(repositories.profile.savedProfiles.count, 0)

        WorkoutSessionContext.markLiveEnded()

        let didRunDeferredPush = await waitUntil { repositories.profile.savedProfiles.count == 1 }
        XCTAssertTrue(didRunDeferredPush)
        XCTAssertEqual(stores.profileStore.pendingUploadCount, 0)
    }

    func testPendingInsightDeliveryClearsAfterPushAndDoesNotReplay() async throws {
        let stores = makeStores()
        let repositories = SyncTestRepositories()
        let orchestrator = makeOrchestrator(stores: stores, repositories: repositories)
        let insight = makeInsight(dedupeKey: "delivery-sync")

        let didSaveInsight = await stores.insightStore.saveInsights(
            [insight],
            operationId: fixedUUID(16_041)
        )
        XCTAssertTrue(didSaveInsight)
        await stores.insightStore.recordImpression(
            insight,
            on: .dashboard,
            now: now.addingTimeInterval(10),
            operationId: fixedUUID(16_042)
        )
        XCTAssertEqual(stores.insightStore.pendingUploadCount, 2)

        try await orchestrator.pushPendingLocal(accountId: accountId)
        try await orchestrator.pushPendingLocal(accountId: accountId)

        XCTAssertEqual(repositories.insight.savedInsights.count, 1)
        XCTAssertEqual(repositories.insight.savedDeliveryRecords.count, 1)
        XCTAssertEqual(stores.insightStore.pendingUploadCount, 0)
    }

    private func makeOrchestrator(
        stores: SyncTestStores,
        repositories: SyncTestRepositories,
        conflictsStore: SyncConflictsStore? = nil
    ) -> SyncOrchestrator {
        let orchestrator = SyncOrchestrator(
            backendMode: .firebase,
            profileRepository: repositories.profile,
            workoutRepository: repositories.workout,
            trophyRepository: repositories.trophy,
            insightRepository: repositories.insight,
            calibrationRepository: repositories.calibration,
            planRepository: repositories.plan,
            conflictsStore: conflictsStore ?? SyncConflictsStore(fileURL: temporaryURL(named: "Conflicts.json"))
        )
        orchestrator.configure(
            accountIdProvider: { self.accountId },
            profileStore: stores.profileStore,
            calibrationStore: stores.calibrationStore,
            workoutHistoryStore: stores.workoutHistoryStore,
            trophyStore: stores.trophyStore,
            insightStore: stores.insightStore
        )
        return orchestrator
    }

    private func makeStores(named name: String = "Stores") -> SyncTestStores {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotterSyncOrchestratorTests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        return SyncTestStores(
            profileStore: OnboardingStore(
                fileURL: baseURL.appendingPathComponent("UserProfile.json"),
                accountId: accountId
            ),
            calibrationStore: CalibrationStore(
                fileURL: baseURL.appendingPathComponent("Calibration.json"),
                accountId: accountId
            ),
            workoutHistoryStore: WorkoutHistoryStore(
                fileURL: baseURL.appendingPathComponent("WorkoutHistory.json"),
                accountId: accountId
            ),
            trophyStore: TrophyStore(
                fileURL: baseURL.appendingPathComponent("Trophies.json"),
                accountId: accountId
            ),
            insightStore: InsightStore(
                fileURL: baseURL.appendingPathComponent("Insights.json"),
                accountId: accountId
            )
        )
    }

    private func makeProfile(
        displayName: String,
        syncMetadata: SyncMetadata? = nil
    ) -> UserProfile {
        UserProfile(
            id: fixedUUID(16_101),
            accountId: accountId,
            displayName: displayName,
            genderIdentity: .preferNotToSay,
            age: 31,
            height: 172,
            heightUnit: .metric,
            weight: 72,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .beginner,
            equipment: [.bodyweight, .mat],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            preferredSessionLength: .twentyFive,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now,
            syncMetadata: syncMetadata
        )
    }

    private func makeWorkoutSummary(id: UUID) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            id: id,
            accountId: accountId,
            mode: .freeAnalysis,
            title: "Free Analysis",
            goal: "Keep the movement smooth.",
            coach: .good,
            startedAt: now.addingTimeInterval(-300),
            endedAt: now,
            durationSeconds: 300,
            totalReps: 12,
            totalHoldSeconds: 0,
            averageFormScore: 88,
            completionPercent: 1,
            exerciseSummaries: [],
            topCue: nil,
            effortSummary: "Steady effort.",
            createdAt: now,
            syncMetadata: .initialPendingUpload(operationId: nil, now: now)
        )
    }

    private func makeCalibrationRecord(
        averageFormScore: Double,
        syncMetadata: SyncMetadata? = nil
    ) -> CalibrationRecord {
        CalibrationRecord(
            accountId: accountId,
            status: .completed,
            exerciseType: CalibrationDefaults.exerciseType,
            targetReps: CalibrationDefaults.targetReps,
            completedReps: 3,
            startedAt: now.addingTimeInterval(-30),
            completedAt: now,
            visibilityPassed: true,
            averageFormScore: averageFormScore,
            syncMetadata: syncMetadata
        )
    }

    private func makeInsight(dedupeKey: String) -> AIInsight {
        AIInsight(
            accountId: accountId,
            type: .consistency,
            headline: "\(dedupeKey) headline",
            message: "\(dedupeKey) message",
            shortMessage: "\(dedupeKey) short",
            evidence: [
                InsightEvidence(
                    metric: "syncTest",
                    value: "pending",
                    confidence: 0.9
                )
            ],
            recommendedAction: .continuePlan,
            severity: .positive,
            emotionalIntent: .reinforceConsistency,
            userValueScore: 80,
            confidence: 0.9,
            surfaces: [.dashboard],
            createdAt: now,
            expiresAt: now.addingTimeInterval(86_400),
            dedupeKey: dedupeKey,
            syncMetadata: .initialPendingUpload(operationId: nil, now: now)
        )
    }

    private func temporaryURL(named fileName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotterSyncOrchestratorTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @MainActor @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}

@MainActor
private struct SyncTestStores {
    let profileStore: OnboardingStore
    let calibrationStore: CalibrationStore
    let workoutHistoryStore: WorkoutHistoryStore
    let trophyStore: TrophyStore
    let insightStore: InsightStore
}

@MainActor
private final class SyncTestRepositories {
    let profile = SyncTestProfileRepository()
    let workout = SyncTestWorkoutRepository()
    let trophy = SyncTestTrophyRepository()
    let insight = SyncTestInsightRepository()
    let calibration = SyncTestCalibrationRepository()
    let plan = SyncTestPlanRepository()
}

@MainActor
private final class SyncTestProfileRepository: ProfileRepository {
    var profile: UserProfile?
    var saveError: Error?
    private(set) var savedProfiles: [UserProfile] = []
    private(set) var savedOperationIds: [UUID] = []
    private(set) var saveAttemptCount = 0
    private var continuation: AsyncStream<UserProfile?>.Continuation?
    private var version = 0

    func loadProfile(accountId _: String) async throws -> UserProfile? {
        profile
    }

    func saveProfile(_ profile: UserProfile, operationId: UUID) async throws -> UserProfile {
        saveAttemptCount += 1
        if let saveError {
            throw saveError
        }
        let savedProfile = profile.syncedProfile(serverVersion: nextVersion(prefix: "profile"))
        self.profile = savedProfile
        savedProfiles.append(savedProfile)
        savedOperationIds.append(operationId)
        continuation?.yield(savedProfile)
        return savedProfile
    }

    func observeProfile(accountId _: String) async throws -> AsyncStream<UserProfile?> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(profile)
        }
    }

    func emit(_ profile: UserProfile) {
        self.profile = profile
        continuation?.yield(profile)
    }

    private func nextVersion(prefix: String) -> String {
        version += 1
        return "\(prefix)-v\(version)"
    }
}

@MainActor
private final class SyncTestWorkoutRepository: WorkoutRepository, WorkoutTombstoneRepository {
    private var summaries: [UUID: WorkoutSessionSummary] = [:]
    private var continuation: AsyncStream<[WorkoutSessionSummary]>.Continuation?
    private var version = 0

    func saveWorkoutSummary(
        _ summary: WorkoutSessionSummary,
        operationId _: UUID
    ) async throws -> WorkoutSessionSummary {
        let savedSummary = summary.markedSynced(serverVersion: nextVersion())
        summaries[summary.id] = savedSummary
        emitActiveSummaries()
        return savedSummary
    }

    func loadRecentWorkouts(
        accountId _: String,
        limit: Int,
        since: Date?
    ) async throws -> [WorkoutSessionSummary] {
        Array(
            sortedSummaries(includeDeleted: false, since: since)
                .prefix(max(limit, 0))
        )
    }

    func loadRecentWorkoutTombstones(
        accountId _: String,
        limit: Int,
        since: Date?
    ) async throws -> [WorkoutSessionSummary] {
        Array(
            sortedSummaries(includeDeleted: true, since: since)
                .filter(\.isDeleted)
                .prefix(max(limit, 0))
        )
    }

    func loadWorkout(accountId _: String, id: UUID) async throws -> WorkoutSessionSummary? {
        guard let summary = summaries[id], !summary.isDeleted else { return nil }
        return summary
    }

    func deleteWorkout(accountId _: String, id: UUID, operationId: UUID) async throws {
        guard let summary = summaries[id] else {
            throw RepositoryError.notFound
        }
        summaries[id] = summary
            .markedDeleted(at: Date(), operationId: operationId)
            .markedSynced(serverVersion: nextVersion())
        emitActiveSummaries()
    }

    func observeRecentWorkouts(accountId _: String, limit: Int) async throws -> AsyncStream<[WorkoutSessionSummary]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(Array(sortedSummaries(includeDeleted: false, since: nil).prefix(max(limit, 0))))
        }
    }

    func deletedWorkout(at id: UUID) -> WorkoutSessionSummary? {
        summaries[id]
    }

    private func emitActiveSummaries() {
        continuation?.yield(sortedSummaries(includeDeleted: false, since: nil))
    }

    private func sortedSummaries(
        includeDeleted: Bool,
        since: Date?
    ) -> [WorkoutSessionSummary] {
        summaries.values
            .filter { includeDeleted || !$0.isDeleted }
            .filter {
                guard let since else { return true }
                return $0.authoritativeEndedAt >= since
            }
            .sorted {
                if $0.authoritativeEndedAt == $1.authoritativeEndedAt {
                    return $0.createdAt > $1.createdAt
                }
                return $0.authoritativeEndedAt > $1.authoritativeEndedAt
            }
    }

    private func nextVersion() -> String {
        version += 1
        return "workout-v\(version)"
    }
}

@MainActor
private final class SyncTestTrophyRepository: TrophyRepository {
    func loadTrophyDefinitions() async throws -> [TrophyDefinition] {
        TrophyDefinitionCatalog.all
    }

    func loadTrophyEvents(accountId _: String, since _: Date?) async throws -> [TrophyUnlockEvent] {
        []
    }

    func saveTrophyEvent(_ event: TrophyUnlockEvent, operationId _: UUID) async throws -> TrophyUnlockEvent {
        event
    }

    func loadTrophyProgress(accountId _: String) async throws -> [TrophyProgress] {
        []
    }

    func observeTrophyEvents(accountId _: String) async throws -> AsyncStream<[TrophyUnlockEvent]> {
        AsyncStream { continuation in
            continuation.yield([])
        }
    }
}

@MainActor
private final class SyncTestInsightRepository: InsightRepository {
    private(set) var savedInsights: [[AIInsight]] = []
    private(set) var savedDeliveryRecords: [InsightDeliveryRecord] = []
    private(set) var savedEngagementRecords: [InsightEngagementRecord] = []

    func saveInsights(_ insights: [AIInsight], operationId _: UUID) async throws -> [AIInsight] {
        savedInsights.append(insights)
        return insights
    }

    func loadRecentInsights(accountId _: String, limit _: Int) async throws -> [AIInsight] {
        []
    }

    func observeRecentInsights(accountId _: String, limit _: Int) async throws -> AsyncStream<[AIInsight]> {
        AsyncStream { continuation in
            continuation.yield([])
        }
    }

    func saveDeliveryRecord(
        _ record: InsightDeliveryRecord,
        operationId _: UUID
    ) async throws -> InsightDeliveryRecord {
        savedDeliveryRecords.append(record)
        return record
    }

    func loadDeliveryRecords(accountId _: String) async throws -> [InsightDeliveryRecord] {
        []
    }

    func observeDeliveryRecords(accountId _: String) async throws -> AsyncStream<[InsightDeliveryRecord]> {
        AsyncStream { continuation in
            continuation.yield([])
        }
    }

    func saveEngagementRecord(
        _ record: InsightEngagementRecord,
        operationId _: UUID
    ) async throws -> InsightEngagementRecord {
        savedEngagementRecords.append(record)
        return record
    }

    func loadEngagementRecords(accountId _: String) async throws -> [InsightEngagementRecord] {
        []
    }

    func observeEngagementRecords(accountId _: String) async throws -> AsyncStream<[InsightEngagementRecord]> {
        AsyncStream { continuation in
            continuation.yield([])
        }
    }

    func invalidateInsight(accountId _: String, dedupeKey _: String, operationId _: UUID) async throws {}
}

@MainActor
private final class SyncTestCalibrationRepository: CalibrationRepository {
    var record: CalibrationRecord?
    private(set) var savedRecords: [CalibrationRecord] = []

    func loadCalibrationRecord(accountId _: String) async throws -> CalibrationRecord? {
        record
    }

    func saveCalibrationRecord(
        _ record: CalibrationRecord,
        operationId _: UUID
    ) async throws -> CalibrationRecord {
        var savedRecord = record
        savedRecord.syncMetadata = record.syncMetadata.markedSynced(serverVersion: "calibration-v1")
        self.record = savedRecord
        savedRecords.append(savedRecord)
        return savedRecord
    }

    func observeCalibrationRecord(accountId _: String) async throws -> AsyncStream<CalibrationRecord?> {
        AsyncStream { continuation in
            continuation.yield(nil)
        }
    }
}

@MainActor
private final class SyncTestPlanRepository: PlanRepository {
    func saveActivePlan(_ plan: WorkoutPlanV2, accountId _: String, operationId _: UUID) async throws -> WorkoutPlanV2 {
        plan
    }

    func loadActivePlan(accountId _: String) async throws -> WorkoutPlanV2? {
        nil
    }

    func loadPlanHistory(accountId _: String, limit _: Int) async throws -> [WorkoutPlanV2] {
        []
    }
}

private extension UserProfile {
    func syncedProfile(serverVersion: String) -> UserProfile {
        var copy = self
        copy.syncMetadata = syncMetadata.markedSynced(serverVersion: serverVersion)
        return copy
    }
}
