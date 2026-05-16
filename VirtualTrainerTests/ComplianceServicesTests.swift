import XCTest
@testable import VirtualTrainer

@MainActor
final class ComplianceServicesTests: XCTestCase {
    func testExportContainsExpectedFilesAndDecodableJSON() async throws {
        let container = makeContainer()
        try await populateLocalData(in: container)

        let result = try await DataExportService(container: container).exportLocalData(
            now: Date(timeIntervalSince1970: 1_778_100_300)
        )

        let expectedFiles: Set<String> = [
            "profile.json",
            "workouts.json",
            "trophies.json",
            "trophyEvents.json",
            "insights.json",
            "insightDelivery.json",
            "insightEngagement.json",
            "calibration.json",
            "theme.json",
            "plans.json",
            "schemaVersions.json",
            "README.txt"
        ]
        XCTAssertEqual(Set(result.fileNames), expectedFiles)
        for fileName in expectedFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: result.archiveURL.appendingPathComponent(fileName).path),
                "Missing \(fileName)"
            )
        }

        let jsonFiles = expectedFiles.filter { $0.hasSuffix(".json") }
        for fileName in jsonFiles {
            let data = try Data(contentsOf: result.archiveURL.appendingPathComponent(fileName))
            _ = try JSONSerialization.jsonObject(with: data)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode(UserProfile.self, from: Data(contentsOf: result.archiveURL.appendingPathComponent("profile.json")))
        _ = try decoder.decode([WorkoutSessionSummary].self, from: Data(contentsOf: result.archiveURL.appendingPathComponent("workouts.json")))
        _ = try decoder.decode([TrophyProgress].self, from: Data(contentsOf: result.archiveURL.appendingPathComponent("trophies.json")))
        _ = try decoder.decode([TrophyUnlockEvent].self, from: Data(contentsOf: result.archiveURL.appendingPathComponent("trophyEvents.json")))
        _ = try decoder.decode([AIInsight].self, from: Data(contentsOf: result.archiveURL.appendingPathComponent("insights.json")))
        _ = try decoder.decode([InsightDeliveryRecord].self, from: Data(contentsOf: result.archiveURL.appendingPathComponent("insightDelivery.json")))
        _ = try decoder.decode([InsightEngagementRecord].self, from: Data(contentsOf: result.archiveURL.appendingPathComponent("insightEngagement.json")))
        _ = try decoder.decode(CalibrationRecord.self, from: Data(contentsOf: result.archiveURL.appendingPathComponent("calibration.json")))
    }

    func testDeleteRemovesExpectedLocalFilesAndCaches() async throws {
        let container = makeContainer()
        try await populateLocalData(in: container)
        try createCacheFixtures(in: container)

        let result = try await AccountDeletionService(container: container).deleteLocalAccountAndData()

        XCTAssertGreaterThanOrEqual(result.removedItemCount, 9)
        for url in container.localAccountDeletionURLs {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "Expected delete to remove \(url.lastPathComponent)")
        }
    }

    func testDeleteIsIdempotentWhenFilesAreAlreadyGone() async throws {
        let container = makeContainer()
        let service = AccountDeletionService(container: container)

        let first = try await service.deleteLocalAccountAndData()
        let second = try await service.deleteLocalAccountAndData()

        XCTAssertEqual(first.removedItemCount, 0)
        XCTAssertEqual(second.removedItemCount, 0)
        XCTAssertEqual(second.alreadyMissingURLs.count, container.localAccountDeletionURLs.count)
    }

    func testFirebaseDeleteStopsListenersWaitsDeletesAuthWipesLocalThenClearsContext() async throws {
        let recorder = AccountDeletionRecorder()
        let localCoordinator = RecordingLocalDeletionCoordinator(recorder: recorder)
        let auth = RecordingDeletionAuthRepository(accountId: "firebase-delete-account", recorder: recorder)
        let sync = RecordingDeletionSyncManager(recorder: recorder)
        let remoteCleaner = RecordingRemoteDeletionCleaner(recorder: recorder)
        let context = RecordingDeletionContext(recorder: recorder)
        let service = AccountDeletionService(localDataCoordinator: localCoordinator)

        let result = try await service.deleteAccountAndData(
            mode: .firebase,
            currentAccountId: "firebase-delete-account",
            authRepository: auth,
            syncOrchestrator: sync,
            remoteCleaner: remoteCleaner,
            accountContext: context
        )

        XCTAssertEqual(
            recorder.events,
            ["stopListeners", "waitForWrites", "auth.delete", "remote.planDelete", "localWipe", "context.clear"]
        )
        XCTAssertEqual(result.removedItemCount, 1)
        XCTAssertEqual(result.clientDeletedRemoteDocumentCount, 2)
        XCTAssertNil(result.cloudDeletionNotice)
    }

    func testFirebaseDeleteContinuesLocalWipeAndReturnsNoticeWhenCloudStepsFail() async throws {
        let recorder = AccountDeletionRecorder()
        let localCoordinator = RecordingLocalDeletionCoordinator(recorder: recorder)
        let auth = RecordingDeletionAuthRepository(
            accountId: "firebase-partial-account",
            recorder: recorder,
            deleteError: RepositoryError.backendUnavailable
        )
        let sync = RecordingDeletionSyncManager(recorder: recorder)
        let remoteCleaner = RecordingRemoteDeletionCleaner(
            recorder: recorder,
            error: RepositoryError.network("temporarily unavailable")
        )
        let context = RecordingDeletionContext(recorder: recorder)
        let service = AccountDeletionService(localDataCoordinator: localCoordinator)

        let result = try await service.deleteAccountAndData(
            mode: .firebase,
            currentAccountId: "firebase-partial-account",
            authRepository: auth,
            syncOrchestrator: sync,
            remoteCleaner: remoteCleaner,
            accountContext: context
        )

        XCTAssertTrue(recorder.events.contains("localWipe"))
        XCTAssertTrue(recorder.events.contains("context.clear"))
        XCTAssertEqual(result.cloudDeletionNotice, "Some cloud data may take up to 7 days to delete.")
        XCTAssertEqual(result.cloudFailureMessages.count, 2)
    }

    func testFirebaseDeleteCanRunAgainAfterAccountIsAlreadyCleared() async throws {
        let recorder = AccountDeletionRecorder()
        let localCoordinator = RecordingLocalDeletionCoordinator(recorder: recorder)
        let auth = RecordingDeletionAuthRepository(accountId: nil, recorder: recorder)
        let service = AccountDeletionService(localDataCoordinator: localCoordinator)

        _ = try await service.deleteAccountAndData(
            mode: .firebase,
            currentAccountId: nil,
            authRepository: auth,
            syncOrchestrator: RecordingDeletionSyncManager(recorder: recorder),
            remoteCleaner: RecordingRemoteDeletionCleaner(recorder: recorder),
            accountContext: RecordingDeletionContext(recorder: recorder)
        )
        _ = try await service.deleteAccountAndData(
            mode: .firebase,
            currentAccountId: nil,
            authRepository: auth,
            syncOrchestrator: RecordingDeletionSyncManager(recorder: recorder),
            remoteCleaner: RecordingRemoteDeletionCleaner(recorder: recorder),
            accountContext: RecordingDeletionContext(recorder: recorder)
        )

        XCTAssertEqual(recorder.events.filter { $0 == "localWipe" }.count, 2)
        XCTAssertFalse(recorder.events.contains("auth.delete"))
        XCTAssertFalse(recorder.events.contains("remote.planDelete"))
    }

    func testDeleteLeavesReloadedAppInOnboardingState() async throws {
        let container = makeContainer()
        let onboardingStore = OnboardingStore(fileURL: container.profileURL)
        onboardingStore.draft = validDraft()
        assertTrue(await onboardingStore.completeOnboarding())
        XCTAssertTrue(onboardingStore.hasCompletedOnboarding)

        _ = try await AccountDeletionService(container: container).deleteLocalAccountAndData()
        await onboardingStore.resetOnboarding()

        XCTAssertFalse(onboardingStore.hasCompletedOnboarding)
        XCTAssertNil(onboardingStore.profile)
        XCTAssertFalse(OnboardingStore(fileURL: container.profileURL).hasCompletedOnboarding)
    }

    func testFirebaseExportWritesLocalAndRemoteJSONFiles() async throws {
        let container = makeContainer()
        try await populateLocalData(in: container)
        let remote = RemoteExportRepositoryFixture(
            accountId: "remote-export-account",
            profile: fullProfileForPIIRegistryAudit(),
            workout: makeSummary(),
            insight: makeInsight(workoutId: fixedUUID(42_001)),
            calibration: CalibrationRecord.completed(
                accountId: "remote-export-account",
                completedReps: 3,
                startedAt: Date(timeIntervalSince1970: 1_778_200_000),
                completedAt: Date(timeIntervalSince1970: 1_778_200_060),
                visibilityPassed: true,
                averageFormScore: 91
            ),
            plan: makePlan()
        )

        let result = try await DataExportService(container: container).exportLocalAndRemoteData(
            accountId: "remote-export-account",
            repositories: remote.repositories,
            now: Date(timeIntervalSince1970: 1_778_200_120)
        )

        let expectedRemoteFiles: Set<String> = [
            "profile.remote.json",
            "workouts.remote.json",
            "trophies.remote.json",
            "trophyEvents.remote.json",
            "insights.remote.json",
            "insightDelivery.remote.json",
            "insightEngagement.remote.json",
            "calibration.remote.json",
            "theme.remote.json",
            "plans.remote.json"
        ]
        XCTAssertTrue(expectedRemoteFiles.isSubset(of: Set(result.fileNames)))
        for fileName in expectedRemoteFiles {
            let data = try Data(contentsOf: result.archiveURL.appendingPathComponent(fileName))
            _ = try JSONSerialization.jsonObject(with: data)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remoteWorkouts = try decoder.decode(
            [WorkoutSessionSummary].self,
            from: Data(contentsOf: result.archiveURL.appendingPathComponent("workouts.remote.json"))
        )
        XCTAssertEqual(remoteWorkouts.first?.exerciseSummaries.count, 1)
        XCTAssertTrue(result.remoteWarnings.isEmpty)
    }

    func testFirebaseExportSucceedsWithReadmeNoteWhenRemoteFetchFails() async throws {
        let container = makeContainer()
        try await populateLocalData(in: container)
        let remote = RemoteExportRepositoryFixture(
            accountId: "remote-export-failure-account",
            profile: fullProfileForPIIRegistryAudit(),
            workout: makeSummary(),
            insight: makeInsight(workoutId: fixedUUID(42_002)),
            calibration: nil,
            plan: makePlan(),
            failingKinds: [.insights]
        )

        let result = try await DataExportService(container: container).exportLocalAndRemoteData(
            accountId: "remote-export-failure-account",
            repositories: remote.repositories,
            now: Date(timeIntervalSince1970: 1_778_200_240)
        )
        let readme = try String(
            contentsOf: result.archiveURL.appendingPathComponent("README.txt"),
            encoding: .utf8
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.archiveURL.appendingPathComponent("insights.remote.json").path))
        XCTAssertTrue(result.remoteWarnings.contains("Remote insights could not be fetched."))
        XCTAssertTrue(readme.contains("Remote fetch notes:"))
        XCTAssertTrue(readme.contains("Remote insights could not be fetched."))
    }

    func testPIIRegistryIncludesCurrentProfileFieldsAndHealthAdjacentDerivedFields() {
        let missingProfileFields = Set(PIIRegistry.currentProfileFieldIDs).subtracting(PIIRegistry.allFieldIDs)
        XCTAssertTrue(missingProfileFields.isEmpty, "Missing registry fields: \(missingProfileFields.sorted())")

        let requiredFields = [
            "displayName",
            "genderIdentity",
            "age",
            "height",
            "weight",
            "timezoneIdentifier",
            "limitations",
            "reminderPreference",
            "accountId",
            "derivedEffortSummaries"
        ]

        for fieldID in requiredFields {
            XCTAssertNotNil(PIIRegistry.entry(for: fieldID), "Missing \(fieldID)")
        }
        XCTAssertNotNil(PIIRegistry.entry(for: "effortSummary"))
        XCTAssertNotNil(PIIRegistry.entry(for: "structuredEffortSummary"))
        XCTAssertNotNil(PIIRegistry.entry(for: "peakEffort"))
    }

    func testPIIRegistryCoversEncodedProfileKeys() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(fullProfileForPIIRegistryAudit())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedKeys = Set(object.keys)
        let registryProfileFields = Set(PIIRegistry.currentProfileFieldIDs)

        XCTAssertEqual(encodedKeys, registryProfileFields)
        XCTAssertTrue(encodedKeys.subtracting(PIIRegistry.allFieldIDs).isEmpty)
    }

    private func populateLocalData(in container: LocalModeDataContainer) async throws {
        let onboardingStore = OnboardingStore(fileURL: container.profileURL)
        onboardingStore.draft = validDraft()
        onboardingStore.draft.limitations = [.kneeSensitive]
        onboardingStore.draft.reminderPreference = .morning
        onboardingStore.draft.timezoneIdentifier = "Asia/Kolkata"
        assertTrue(await onboardingStore.completeOnboarding())

        let historyStore = WorkoutHistoryStore(fileURL: container.workoutsURL)
        let summary = makeSummary()
        assertTrue(await historyStore.addSummary(summary))

        let calibrationStore = CalibrationStore(fileURL: container.calibrationURL)
        assertTrue(
            await calibrationStore.saveCompleted(
                completedReps: 3,
                startedAt: Date(timeIntervalSince1970: 1_778_100_000),
                completedAt: Date(timeIntervalSince1970: 1_778_100_060),
                visibilityPassed: true,
                averageFormScore: 88
            )
        )

        let trophyStore = TrophyStore(fileURL: container.trophiesURL)
        await trophyStore.updateAll(
            history: historyStore.summaries,
            calibrationStatus: calibrationStore.status,
            now: Date(timeIntervalSince1970: 1_778_100_120)
        )

        let themeStore = ThemeStore(fileURL: container.themeURL)
        assertTrue(await themeStore.updateSelectedTheme(.warm))

        let insightStore = InsightStore(fileURL: container.insightsURL)
        let profile = try XCTUnwrap(onboardingStore.profile)
        let insight = makeInsight(workoutId: summary.id)
        _ = await insightStore.selectInsights(
            [insight],
            for: .profile,
            profile: profile,
            limit: 1,
            now: Date(timeIntervalSince1970: 1_778_100_180)
        )
        await insightStore.recordPresentation(
            dedupeKey: insight.dedupeKey,
            on: .profile,
            now: Date(timeIntervalSince1970: 1_778_100_181)
        )
        await insightStore.recordEngagement(
            insight,
            kind: .helpful,
            now: Date(timeIntervalSince1970: 1_778_100_182)
        )
    }

    private func createCacheFixtures(in container: LocalModeDataContainer) throws {
        try FileManager.default.createDirectory(
            at: container.generatedExportCacheDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: container.shareImageCacheDirectory,
            withIntermediateDirectories: true
        )
        try Data("export".utf8).write(to: container.generatedExportCacheDirectory.appendingPathComponent("old-export.json"))
        try Data("share".utf8).write(to: container.shareImageCacheDirectory.appendingPathComponent("old-share.png"))
    }

    private func makeContainer() -> LocalModeDataContainer {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComplianceServicesTests-\(UUID().uuidString)", isDirectory: true)
        return LocalModeDataContainer(
            storageDirectory: root.appendingPathComponent("ApplicationSupport", isDirectory: true),
            temporaryDirectory: root.appendingPathComponent("Temporary", isDirectory: true),
            cachesDirectory: root.appendingPathComponent("Caches", isDirectory: true)
        )
    }

    private func validDraft() -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft.displayName = "Compliance Athlete"
        draft.genderIdentity = .preferNotToSay
        draft.age = "34"
        draft.height = "175"
        draft.weight = "72"
        draft.primaryGoal = .strength
        draft.fitnessLevel = .beginner
        draft.equipment = [.bodyweight, .mat]
        return draft
    }

    private func fullProfileForPIIRegistryAudit() -> UserProfile {
        let now = Date(timeIntervalSince1970: 1_778_100_240)
        return UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE") ?? UUID(),
            accountId: "account-audit",
            displayName: "Compliance Athlete",
            genderIdentity: .preferNotToSay,
            age: 34,
            height: 175,
            heightUnit: .metric,
            weight: 72,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .beginner,
            equipment: [.bodyweight, .mat],
            preferredCoach: .bennett,
            selectedTheme: .warm,
            limitations: [.kneeSensitive],
            preferredSessionLength: .twentyFive,
            workoutDaysPerWeek: 3,
            reminderPreference: .morning,
            timezoneIdentifier: "Asia/Kolkata",
            avatarStyle: .strength,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now,
            deletedAt: now.addingTimeInterval(60)
        )
    }

    private func makeSummary() -> WorkoutSessionSummary {
        let startedAt = Date(timeIntervalSince1970: 1_778_100_000)
        let endedAt = Date(timeIntervalSince1970: 1_778_100_420)
        let setSummary = ExerciseSetSummary(
            exerciseType: .squat,
            setIndex: 0,
            achievedReps: 12,
            achievedHoldSeconds: 0,
            averageFormScore: 88,
            cueEvents: [
                CueEvent(
                    timestamp: startedAt.addingTimeInterval(120),
                    exerciseType: .squat,
                    cueMessage: "Keep your knees tracking",
                    severity: .warning,
                    setIndex: 0,
                    repIndex: 6,
                    secondsIntoSet: 120,
                    formScoreAtEvent: 78
                )
            ],
            completedAt: endedAt,
            durationSeconds: 420,
            peakEffort: 0.55
        )

        return WorkoutSessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000C001") ?? UUID(),
            mode: .freeAnalysis,
            title: "Compliance Squat",
            goal: "Check local export",
            coach: .good,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: 420,
            totalReps: 12,
            totalHoldSeconds: 0,
            averageFormScore: 88,
            exerciseSummaries: [setSummary],
            topCue: setSummary.cueEvents.first,
            effortSummary: "Peak effort reached 55%. Solid working intensity.",
            createdAt: endedAt.addingTimeInterval(1)
        )
    }

    private func makePlan() -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: fixedUUID(42_500),
            title: "Compliance Plan",
            subtitle: "Remote export fixture",
            goal: "Keep account exports complete.",
            estimatedMinutes: 7,
            difficulty: .beginner,
            coach: .good,
            blocks: [
                WorkoutBlock(
                    title: "Main",
                    type: .main,
                    exercises: [
                        PlannedExercise(
                            exerciseType: .squat,
                            sets: [
                                PlannedSet(setIndex: 1, target: .reps(10))
                            ],
                            restSeconds: 45,
                            coachingFocus: "Depth and control.",
                            cameraPosition: .front,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: Date(timeIntervalSince1970: 1_778_200_000),
            planReason: "Stable compliance export fixture.",
            source: .generatedLocal
        )
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }

    private func makeInsight(workoutId: UUID) -> AIInsight {
        AIInsight(
            type: .growthCelebration,
            headline: "Squat consistency is building",
            message: "Your squat set stayed controlled enough to keep the next plan steady.",
            shortMessage: "Squat consistency is building.",
            evidence: [
                InsightEvidence(
                    metric: "averageFormScore",
                    value: "88%",
                    workoutId: workoutId,
                    exerciseType: .squat,
                    confidence: 0.9
                )
            ],
            recommendedAction: .continuePlan,
            severity: .positive,
            emotionalIntent: .celebrateGrowth,
            userValueScore: 0.8,
            confidence: 0.9,
            surfaces: [.profile],
            relatedExerciseType: .squat,
            relatedGoal: .strength,
            createdAt: Date(timeIntervalSince1970: 1_778_100_180),
            expiresAt: Date(timeIntervalSince1970: 1_778_100_180 + 7 * 24 * 60 * 60),
            dedupeKey: "compliance-squat-consistency"
        )
    }
}

private final class AccountDeletionRecorder {
    nonisolated(unsafe) private(set) var events: [String] = []

    nonisolated
    func record(_ event: String) {
        events.append(event)
    }
}

private final class RecordingLocalDeletionCoordinator: AccountDeletionLocalDataCoordinating {
    private let recorder: AccountDeletionRecorder
    nonisolated(unsafe) private var didWipe = false

    nonisolated
    var localAccountDeletionURLs: [URL] {
        [FileManager.default.temporaryDirectory.appendingPathComponent("recorded-delete.json")]
    }

    init(recorder: AccountDeletionRecorder) {
        self.recorder = recorder
    }

    nonisolated
    func waitForStoreWrites() async {
        recorder.record("waitForWrites")
    }

    nonisolated
    func wipeLocalData() async throws -> AccountDeletionResult {
        recorder.record("localWipe")
        if didWipe {
            return AccountDeletionResult(
                deletedURLs: [],
                alreadyMissingURLs: localAccountDeletionURLs,
                clientDeletedRemoteDocumentCount: 0,
                cloudFailureMessages: []
            )
        }
        didWipe = true
        return AccountDeletionResult(
            deletedURLs: localAccountDeletionURLs,
            alreadyMissingURLs: [],
            clientDeletedRemoteDocumentCount: 0,
            cloudFailureMessages: []
        )
    }
}

@MainActor
private final class RecordingDeletionSyncManager: AccountDeletionSyncManaging {
    private let recorder: AccountDeletionRecorder

    init(recorder: AccountDeletionRecorder) {
        self.recorder = recorder
    }

    func stopListeners() async throws {
        recorder.record("stopListeners")
    }
}

@MainActor
private final class RecordingDeletionAuthRepository: AuthRepository {
    private let recorder: AccountDeletionRecorder
    private let deleteError: Error?
    private(set) var currentAccountId: String?

    init(
        accountId: String?,
        recorder: AccountDeletionRecorder,
        deleteError: Error? = nil
    ) {
        self.currentAccountId = accountId
        self.recorder = recorder
        self.deleteError = deleteError
    }

    func signInAnonymously() async throws -> String {
        let accountId = currentAccountId ?? "recording-auth-account"
        currentAccountId = accountId
        return accountId
    }

    func linkAnonymousAccountWithApple(idToken: String, nonce: String) async throws -> String {
        throw RepositoryError.backendUnavailable
    }

    func signOut() async throws {
        currentAccountId = nil
    }

    func deleteAccount() async throws {
        recorder.record("auth.delete")
        if let deleteError {
            throw deleteError
        }
        currentAccountId = nil
    }

    func observeAuthChanges() async throws -> AsyncStream<String?> {
        AsyncStream { continuation in
            continuation.yield(currentAccountId)
            continuation.finish()
        }
    }
}

@MainActor
private final class RecordingRemoteDeletionCleaner: AccountDeletionRemoteCleaning {
    private let recorder: AccountDeletionRecorder
    private let error: Error?

    init(recorder: AccountDeletionRecorder, error: Error? = nil) {
        self.recorder = recorder
        self.error = error
    }

    func deleteClientAllowedAccountData(accountId: String) async throws -> AccountDeletionRemoteCleanupResult {
        recorder.record("remote.planDelete")
        if let error {
            throw error
        }
        return AccountDeletionRemoteCleanupResult(deletedDocumentCount: 2, boundedDocumentLimit: 50)
    }
}

@MainActor
private final class RecordingDeletionContext: AccountDeletionContextClearing {
    private let recorder: AccountDeletionRecorder

    init(recorder: AccountDeletionRecorder) {
        self.recorder = recorder
    }

    func clearAccount() {
        recorder.record("context.clear")
    }
}

@MainActor
private final class RemoteExportRepositoryFixture:
    ProfileRepository,
    WorkoutRepository,
    TrophyRepository,
    InsightRepository,
    ThemeRepository,
    CalibrationRepository,
    PlanRepository {

    enum FailingKind: Hashable {
        case insights
    }

    private let accountId: String
    private let profile: UserProfile
    private let workout: WorkoutSessionSummary
    private let insight: AIInsight
    private let calibration: CalibrationRecord?
    private let plan: WorkoutPlanV2
    private let failingKinds: Set<FailingKind>

    var repositories: RemoteDataExportRepositories {
        RemoteDataExportRepositories(
            profile: self,
            workouts: self,
            trophies: self,
            insights: self,
            theme: self,
            calibration: self,
            plans: self
        )
    }

    init(
        accountId: String,
        profile: UserProfile,
        workout: WorkoutSessionSummary,
        insight: AIInsight,
        calibration: CalibrationRecord?,
        plan: WorkoutPlanV2,
        failingKinds: Set<FailingKind> = []
    ) {
        self.accountId = accountId
        self.profile = profile
        self.workout = workout
        self.insight = insight
        self.calibration = calibration
        self.plan = plan
        self.failingKinds = failingKinds
    }

    func loadProfile(accountId: String) async throws -> UserProfile? {
        profile
    }

    @discardableResult
    func saveProfile(_ profile: UserProfile, operationId: UUID) async throws -> UserProfile {
        profile
    }

    func observeProfile(accountId: String) async throws -> AsyncStream<UserProfile?> {
        AsyncStream { continuation in
            continuation.yield(profile)
            continuation.finish()
        }
    }

    @discardableResult
    func saveWorkoutSummary(_ summary: WorkoutSessionSummary, operationId: UUID) async throws -> WorkoutSessionSummary {
        summary
    }

    func loadRecentWorkouts(accountId: String, limit: Int, since: Date?) async throws -> [WorkoutSessionSummary] {
        [workout]
    }

    func loadWorkout(accountId: String, id: UUID) async throws -> WorkoutSessionSummary? {
        workout.id == id ? workout : nil
    }

    func deleteWorkout(accountId: String, id: UUID, operationId: UUID) async throws {}

    func observeRecentWorkouts(accountId: String, limit: Int) async throws -> AsyncStream<[WorkoutSessionSummary]> {
        AsyncStream { continuation in
            continuation.yield([workout])
            continuation.finish()
        }
    }

    func loadTrophyDefinitions() async throws -> [TrophyDefinition] {
        TrophyDefinitionCatalog.all
    }

    func loadTrophyEvents(accountId: String, since: Date?) async throws -> [TrophyUnlockEvent] {
        [
            TrophyUnlockEvent(
                accountId: accountId,
                trophyId: TrophyDefinitionCatalog.ID.spark,
                title: "The Spark",
                subtitle: "First workout complete",
                earnedAt: Date(timeIntervalSince1970: 1_778_200_200),
                reason: "Remote export fixture.",
                celebrationStyle: .standard
            )
        ]
    }

    @discardableResult
    func saveTrophyEvent(_ event: TrophyUnlockEvent, operationId: UUID) async throws -> TrophyUnlockEvent {
        event
    }

    func loadTrophyProgress(accountId: String) async throws -> [TrophyProgress] {
        [
            TrophyProgress(
                trophyId: TrophyDefinitionCatalog.ID.spark,
                currentValue: 1,
                targetValue: 1,
                earned: true,
                earnedAt: Date(timeIntervalSince1970: 1_778_200_200),
                lastUpdatedAt: Date(timeIntervalSince1970: 1_778_200_200),
                confidence: .exact,
                progressLabel: "Earned",
                accountId: accountId
            )
        ]
    }

    func observeTrophyEvents(accountId: String) async throws -> AsyncStream<[TrophyUnlockEvent]> {
        AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    @discardableResult
    func saveInsights(_ insights: [AIInsight], operationId: UUID) async throws -> [AIInsight] {
        insights
    }

    func loadRecentInsights(accountId: String, limit: Int) async throws -> [AIInsight] {
        if failingKinds.contains(.insights) {
            throw RepositoryError.network("remote insights unavailable")
        }
        return [insight]
    }

    func observeRecentInsights(accountId: String, limit: Int) async throws -> AsyncStream<[AIInsight]> {
        AsyncStream { continuation in
            continuation.yield([insight])
            continuation.finish()
        }
    }

    @discardableResult
    func saveDeliveryRecord(_ record: InsightDeliveryRecord, operationId: UUID) async throws -> InsightDeliveryRecord {
        record
    }

    func loadDeliveryRecords(accountId: String) async throws -> [InsightDeliveryRecord] {
        [
            InsightDeliveryRecord(
                accountId: accountId,
                dedupeKey: insight.dedupeKey,
                firstPresentedAt: Date(timeIntervalSince1970: 1_778_200_210),
                lastPresentedAt: Date(timeIntervalSince1970: 1_778_200_210),
                presentationCount: 1,
                surfaceLastPresentedAt: [InsightSurface.profile.rawValue: Date(timeIntervalSince1970: 1_778_200_210)]
            )
        ]
    }

    func observeDeliveryRecords(accountId: String) async throws -> AsyncStream<[InsightDeliveryRecord]> {
        AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    @discardableResult
    func saveEngagementRecord(_ record: InsightEngagementRecord, operationId: UUID) async throws -> InsightEngagementRecord {
        record
    }

    func loadEngagementRecords(accountId: String) async throws -> [InsightEngagementRecord] {
        var record = InsightEngagementRecord(accountId: accountId, dedupeKey: insight.dedupeKey)
        record.record(.opened, at: Date(timeIntervalSince1970: 1_778_200_220))
        return [record]
    }

    func observeEngagementRecords(accountId: String) async throws -> AsyncStream<[InsightEngagementRecord]> {
        AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }

    func invalidateInsight(accountId: String, dedupeKey: String, operationId: UUID) async throws {}

    func loadTheme(accountId: String) async throws -> SpotterThemeOption {
        .warm
    }

    func saveTheme(_ theme: SpotterThemeOption, accountId: String, operationId: UUID) async throws {}

    func observeTheme(accountId: String) async throws -> AsyncStream<SpotterThemeOption> {
        AsyncStream { continuation in
            continuation.yield(.warm)
            continuation.finish()
        }
    }

    func loadCalibrationRecord(accountId: String) async throws -> CalibrationRecord? {
        calibration
    }

    @discardableResult
    func saveCalibrationRecord(_ record: CalibrationRecord, operationId: UUID) async throws -> CalibrationRecord {
        record
    }

    func observeCalibrationRecord(accountId: String) async throws -> AsyncStream<CalibrationRecord?> {
        AsyncStream { continuation in
            continuation.yield(calibration)
            continuation.finish()
        }
    }

    @discardableResult
    func saveActivePlan(_ plan: WorkoutPlanV2, accountId: String, operationId: UUID) async throws -> WorkoutPlanV2 {
        plan
    }

    func loadActivePlan(accountId: String) async throws -> WorkoutPlanV2? {
        plan
    }

    func loadPlanHistory(accountId: String, limit: Int) async throws -> [WorkoutPlanV2] {
        [plan]
    }
}
