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

    func testFirebasePartialUsesPhase16GFirestoreRepositories() async {
        let dependencies = AppDependencies.firebasePartial()

        XCTAssertEqual(dependencies.backendMode, .firebase)
        XCTAssertTrue(dependencies.auth is FirebaseAuthRepository)
        XCTAssertTrue(dependencies.profile is FirestoreProfileRepository)
        XCTAssertTrue(dependencies.theme is FirestoreThemeRepository)
        XCTAssertTrue(dependencies.calibration is FirestoreCalibrationRepository)
        XCTAssertTrue(dependencies.plans is FirestorePlanRepository)
        XCTAssertTrue(dependencies.workouts is FirestoreWorkoutRepository)
        XCTAssertTrue(dependencies.trophies is FirestoreTrophyRepository)
        XCTAssertTrue(dependencies.insights is FirestoreInsightRepository)
    }

    func testFirestoreTrophyRepositoryRoundTripsEventsAndDerivesEarliestProgress() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreTrophyRepository(database: database)
        let later = makeTrophyEvent(earnedAt: now.addingTimeInterval(120))
        let earlier = makeTrophyEvent(earnedAt: now)

        _ = try await repository.saveTrophyEvent(later, operationId: fixedUUID(160_101))
        let duplicate = try await repository.saveTrophyEvent(later, operationId: fixedUUID(160_101))
        _ = try await repository.saveTrophyEvent(earlier, operationId: fixedUUID(160_102))

        let events = try await repository.loadTrophyEvents(accountId: accountId, since: nil)
        let progress = try await repository.loadTrophyProgress(accountId: accountId)
        let duplicatePath = try FirestorePathBuilder.trophyEvent(
            uid: accountId,
            eventId: fixedUUID(160_101).uuidString.lowercased()
        )

        XCTAssertEqual(duplicate.earnedAt, later.earnedAt)
        XCTAssertEqual(database.writeCount(for: duplicatePath), 1)
        XCTAssertEqual(events.map(\.earnedAt), [now, now.addingTimeInterval(120)])
        XCTAssertEqual(
            progress.first { $0.trophyId == TrophyDefinitionCatalog.ID.spark }?.earnedAt,
            now
        )
    }

    func testFirestoreInsightRepositoryRoundTripsByDedupeKeyAndPolicyVersionBumpWins() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreInsightRepository(database: database)
        let oldInsight = makeInsight(
            dedupeKey: "policy-bump",
            headline: "Old policy headline",
            sourcePolicyVersion: "phase14.local.deterministic.v1",
            createdAt: now
        )
        let newInsight = makeInsight(
            dedupeKey: "policy-bump",
            headline: "New policy headline",
            sourcePolicyVersion: "phase14.local.deterministic.v2",
            createdAt: now.addingTimeInterval(10)
        )

        _ = try await repository.saveInsights([oldInsight], operationId: fixedUUID(160_201))
        _ = try await repository.saveInsights([newInsight], operationId: fixedUUID(160_202))

        let loaded = try await repository.loadRecentInsights(accountId: accountId, limit: 5)

        XCTAssertEqual(loaded.map(\.dedupeKey), ["policy-bump"])
        XCTAssertEqual(loaded.first?.headline, "New policy headline")
        XCTAssertEqual(loaded.first?.sourcePolicyVersion, "phase14.local.deterministic.v2")
    }

    func testFirestoreInsightPolicyBumpPreservesServerCreatedAt() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreInsightRepository(database: database)
        let dedupeKey = "policy-bump-preserve-server-created"
        let oldInsight = makeInsight(
            dedupeKey: dedupeKey,
            headline: "Old preserved server time",
            sourcePolicyVersion: "phase14.local.deterministic.v1",
            createdAt: now
        )
        let newInsight = makeInsight(
            dedupeKey: dedupeKey,
            headline: "New preserved server time",
            sourcePolicyVersion: "phase14.local.deterministic.v2",
            createdAt: now.addingTimeInterval(10)
        )
        let path = try FirestorePathBuilder.insight(uid: accountId, dedupeKey: dedupeKey)

        _ = try await repository.saveInsights([oldInsight], operationId: fixedUUID(160_211))
        let firstDocument = try await database.getDocument(path: path)
        let firstServerCreatedAt = try XCTUnwrap(firstDocument?.data["serverCreatedAt"] as? String)
        _ = try await repository.saveInsights([newInsight], operationId: fixedUUID(160_212))
        let secondDocument = try await database.getDocument(path: path)
        let secondServerCreatedAt = try XCTUnwrap(secondDocument?.data["serverCreatedAt"] as? String)

        XCTAssertEqual(secondServerCreatedAt, firstServerCreatedAt)
    }

    func testFirestoreInsightDeliveryMergeUsesEarliestLatestAndMaxCount() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreInsightRepository(database: database)
        let first = InsightDeliveryRecord(
            accountId: accountId,
            dedupeKey: "delivery-aggregate",
            firstPresentedAt: now.addingTimeInterval(20),
            lastPresentedAt: now.addingTimeInterval(30),
            presentationCount: 2,
            surfaceLastPresentedAt: [
                InsightSurface.dashboard.rawValue: now.addingTimeInterval(30)
            ]
        )
        let second = InsightDeliveryRecord(
            accountId: accountId,
            dedupeKey: "delivery-aggregate",
            firstPresentedAt: now,
            lastPresentedAt: now.addingTimeInterval(60),
            presentationCount: 1,
            surfaceLastPresentedAt: [
                InsightSurface.dashboard.rawValue: now.addingTimeInterval(40),
                InsightSurface.profile.rawValue: now.addingTimeInterval(60)
            ]
        )

        _ = try await repository.saveDeliveryRecord(first, operationId: fixedUUID(160_301))
        let merged = try await repository.saveDeliveryRecord(second, operationId: fixedUUID(160_302))

        XCTAssertEqual(merged.firstPresentedAt, now)
        XCTAssertEqual(merged.lastPresentedAt, now.addingTimeInterval(60))
        XCTAssertEqual(merged.presentationCount, 2)
        XCTAssertEqual(merged.surfaceLastPresentedAt[InsightSurface.dashboard.rawValue], now.addingTimeInterval(40))
        XCTAssertEqual(merged.surfaceLastPresentedAt[InsightSurface.profile.rawValue], now.addingTimeInterval(60))
    }

    func testFirestoreInsightEngagementMergeSumsCountsAndKeepsMaxDates() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreInsightRepository(database: database)
        var first = InsightEngagementRecord(accountId: accountId, dedupeKey: "engagement-aggregate")
        first.record(.helpful, at: now)
        first.record(.opened, at: now.addingTimeInterval(5))
        var second = InsightEngagementRecord(accountId: accountId, dedupeKey: "engagement-aggregate")
        second.record(.helpful, at: now.addingTimeInterval(20))
        second.record(.notHelpful, at: now.addingTimeInterval(30))

        _ = try await repository.saveEngagementRecord(first, operationId: fixedUUID(160_401))
        let merged = try await repository.saveEngagementRecord(second, operationId: fixedUUID(160_402))

        XCTAssertEqual(merged.count(for: .helpful), 2)
        XCTAssertEqual(merged.count(for: .opened), 1)
        XCTAssertEqual(merged.count(for: .notHelpful), 1)
        XCTAssertEqual(merged.lastEngagedAt(for: .helpful), now.addingTimeInterval(20))
        XCTAssertEqual(merged.lastEngagedAt(for: .notHelpful), now.addingTimeInterval(30))
    }

    func testFirestoreInsightInvalidationHidesInsightFromRecentLoads() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreInsightRepository(database: database)
        let insight = makeInsight(dedupeKey: "invalidated-remote")

        _ = try await repository.saveInsights([insight], operationId: fixedUUID(160_501))
        try await repository.invalidateInsight(
            accountId: accountId,
            dedupeKey: insight.dedupeKey,
            operationId: fixedUUID(160_502)
        )

        let loaded = try await repository.loadRecentInsights(accountId: accountId, limit: 5)

        XCTAssertFalse(loaded.contains { $0.dedupeKey == insight.dedupeKey })
    }

    func testFirestoreInsightInvalidationWritesTombstoneWhenDocumentIsMissing() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let repository = FirestoreInsightRepository(database: database)
        let dedupeKey = "missing-invalidated-remote"

        try await repository.invalidateInsight(
            accountId: accountId,
            dedupeKey: dedupeKey,
            operationId: fixedUUID(160_503)
        )

        let loaded = try await repository.loadRecentInsights(accountId: accountId, limit: 5)
        let path = try FirestorePathBuilder.insight(uid: accountId, dedupeKey: dedupeKey)
        let tombstone = try await database.getDocument(path: path)

        XCTAssertFalse(loaded.contains { $0.dedupeKey == dedupeKey })
        XCTAssertEqual(tombstone?.data["accountId"] as? String, accountId)
        XCTAssertEqual(tombstone?.data["dedupeKey"] as? String, dedupeKey)
        XCTAssertNotNil(tombstone?.data["deletedAt"])
    }

    func testPrivacyValidatorRejectsForbiddenKeysInInsightPayloads() throws {
        let document = mapToInsightDocument(makeInsight(dedupeKey: "privacy-reject"))
        var payload = try FirestoreEncodingHelpers.payload(from: document)
        payload["rawPoseTimeline"] = [["x": 0.2, "y": 0.4]]

        XCTAssertThrowsError(try FirestorePrivacyValidator.validate(payload))
    }

    func testRepositoryWritePayloadsMatchPublishedDTOKeysAndPrivacyBoundary() async throws {
        let database = InMemoryFirestoreDocumentDatabase()
        let profileRepository = FirestoreProfileRepository(database: database)
        let themeRepository = FirestoreThemeRepository(database: database)
        let calibrationRepository = FirestoreCalibrationRepository(database: database)
        let planRepository = FirestorePlanRepository(database: database)
        let workoutRepository = FirestoreWorkoutRepository(database: database)
        let trophyRepository = FirestoreTrophyRepository(database: database)
        let insightRepository = FirestoreInsightRepository(database: database)

        let profile = makeProfile(updatedAt: now, operationId: fixedUUID(160_701))
        _ = try await profileRepository.saveProfile(profile, operationId: fixedUUID(160_701))
        try await themeRepository.saveTheme(.spicy, accountId: accountId, operationId: fixedUUID(160_702))

        let calibration = makeCalibrationRecord(operationId: fixedUUID(160_703))
        _ = try await calibrationRepository.saveCalibrationRecord(calibration, operationId: fixedUUID(160_703))

        let firstPlan = makePlan(id: fixedUUID(160_704), title: "Payload Plan A")
        let secondPlan = makePlan(id: fixedUUID(160_705), title: "Payload Plan B")
        _ = try await planRepository.saveActivePlan(firstPlan, accountId: accountId, operationId: fixedUUID(160_706))
        _ = try await planRepository.saveActivePlan(secondPlan, accountId: accountId, operationId: fixedUUID(160_707))

        let workout = makeWorkoutSummary(
            id: fixedUUID(160_708),
            sets: [
                makeSetSummary(exerciseType: .squat, setIndex: 0, formScores: [90, 86]),
                makeSetSummary(exerciseType: .pushup, setIndex: 1, formScores: [85])
            ],
            operationId: fixedUUID(160_709)
        )
        _ = try await workoutRepository.saveWorkoutSummary(workout, operationId: fixedUUID(160_709))
        try await workoutRepository.deleteWorkout(
            accountId: accountId,
            id: workout.id,
            operationId: fixedUUID(160_710)
        )

        _ = try await trophyRepository.saveTrophyEvent(
            makeTrophyEvent(earnedAt: now.addingTimeInterval(25)),
            operationId: fixedUUID(160_711)
        )

        let insight = makeInsight(dedupeKey: "payload-boundary")
        _ = try await insightRepository.saveInsights([insight], operationId: fixedUUID(160_712))

        let delivery = InsightDeliveryRecord(
            accountId: accountId,
            dedupeKey: insight.dedupeKey,
            firstPresentedAt: now,
            lastPresentedAt: now.addingTimeInterval(30),
            presentationCount: 1,
            surfaceLastPresentedAt: [InsightSurface.dashboard.rawValue: now.addingTimeInterval(30)]
        )
        _ = try await insightRepository.saveDeliveryRecord(delivery, operationId: fixedUUID(160_713))

        var engagement = InsightEngagementRecord(accountId: accountId, dedupeKey: insight.dedupeKey)
        engagement.record(.opened, at: now.addingTimeInterval(45))
        _ = try await insightRepository.saveEngagementRecord(engagement, operationId: fixedUUID(160_714))

        try await insightRepository.invalidateInsight(
            accountId: accountId,
            dedupeKey: "payload-boundary-missing",
            operationId: fixedUUID(160_715)
        )

        let writes = database.appliedWrites
        assertRepositoryWriteCoverage(writes)

        for write in writes {
            try assertNoForbiddenKeys(in: write.payload, context: write.path)
            assertNoUnexpectedKeys(
                in: write.payload,
                allowedKeys: allowedTopLevelKeys(forFirestorePath: write.path),
                context: "\(write.kind.description) \(write.path)"
            )
        }
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

    private func makeTrophyEvent(earnedAt: Date) -> TrophyUnlockEvent {
        TrophyUnlockEvent(
            accountId: accountId,
            trophyId: TrophyDefinitionCatalog.ID.spark,
            title: "The Spark",
            subtitle: "First workout complete",
            earnedAt: earnedAt,
            reason: "Repository sync test unlock.",
            celebrationStyle: .standard,
            syncMetadata: SyncMetadata(
                localUpdatedAt: earnedAt,
                lastSyncedAt: nil,
                serverVersion: nil,
                syncState: .pendingUpload,
                pendingOperationId: nil
            )
        )
    }

    private func makeCalibrationRecord(operationId: UUID) -> CalibrationRecord {
        CalibrationRecord(
            id: fixedUUID(160_803),
            accountId: accountId,
            status: .completed,
            exerciseType: CalibrationDefaults.exerciseType,
            targetReps: CalibrationDefaults.targetReps,
            completedReps: CalibrationDefaults.targetReps,
            startedAt: now.addingTimeInterval(-90),
            completedAt: now.addingTimeInterval(-30),
            visibilityPassed: true,
            averageFormScore: 92,
            notes: "Repository privacy payload fixture.",
            syncMetadata: SyncMetadata(
                localUpdatedAt: now.addingTimeInterval(-30),
                lastSyncedAt: nil,
                serverVersion: nil,
                syncState: .pendingUpload,
                pendingOperationId: operationId
            )
        )
    }

    private func makePlan(id: UUID, title: String) -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: id,
            title: title,
            subtitle: "Repository payload fixture",
            goal: "Keep sync private.",
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
                                PlannedSet(setIndex: 1, target: .reps(10)),
                                PlannedSet(setIndex: 2, target: .reps(10))
                            ],
                            restSeconds: 45,
                            coachingFocus: "Depth and control.",
                            cameraPosition: .front,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: now,
            planReason: "Stable repository payload fixture.",
            source: .generatedLocal
        )
    }

    private func assertRepositoryWriteCoverage(
        _ writes: [InMemoryFirestoreDocumentDatabase.AppliedWrite],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            writes.count,
            15,
            "Unexpected repository write count.\n\(writeCoverageSummary(writes))",
            file: file,
            line: line
        )

        XCTAssertTrue(
            writes.contains {
                isSetWrite($0, merge: true) &&
                    $0.path.hasSuffix("/profile/current") &&
                    $0.payload["profileId"] != nil
            },
            "Missing full profile save payload.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            writes.contains {
                isSetWrite($0, merge: true) &&
                    $0.path.hasSuffix("/profile/current") &&
                    $0.payload["selectedTheme"] != nil &&
                    $0.payload["profileId"] == nil
            },
            "Missing profile-backed theme patch payload.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            writes.contains {
                isSetWrite($0, merge: true) &&
                    $0.path.hasSuffix("/calibration/status") &&
                    $0.payload["calibrationId"] != nil
            },
            "Missing calibration save payload.",
            file: file,
            line: line
        )

        let planSetWrites = writes.filter {
            isSetWrite($0, merge: true) &&
                $0.path.contains("/plans/") &&
                $0.payload["planId"] != nil &&
                $0.payload["active"] as? Bool == true
        }
        XCTAssertEqual(planSetWrites.count, 2, "Expected two active plan save payloads.", file: file, line: line)
        XCTAssertTrue(
            writes.contains {
                isUpdateWrite($0) &&
                    $0.path.contains("/plans/") &&
                    $0.payload.keys.sorted() == ["active"] &&
                    $0.payload["active"] as? Bool == false
            },
            "Missing inactive-plan update payload.",
            file: file,
            line: line
        )

        XCTAssertTrue(
            writes.contains {
                isSetWrite($0, merge: true) &&
                    isWorkoutDocumentPath($0.path) &&
                    $0.payload["workoutId"] != nil
            },
            "Missing workout summary save payload.",
            file: file,
            line: line
        )
        let setWrites = writes.filter {
            isSetWrite($0, merge: true) &&
                $0.path.contains("/sets/") &&
                $0.payload["setId"] != nil
        }
        XCTAssertEqual(setWrites.count, 2, "Expected two workout set save payloads.", file: file, line: line)
        XCTAssertTrue(
            writes.contains {
                isUpdateWrite($0) &&
                    isWorkoutDocumentPath($0.path) &&
                    $0.payload["deletedAt"] != nil &&
                    $0.payload["workoutId"] == nil
            },
            "Missing workout tombstone update payload.",
            file: file,
            line: line
        )

        XCTAssertTrue(
            writes.contains {
                isSetWrite($0, merge: false) &&
                    $0.path.contains("/trophyEvents/") &&
                    $0.payload["eventId"] != nil
            },
            "Missing trophy event append payload.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            writes.contains {
                isSetWrite($0, merge: true) &&
                    $0.path.contains("/insights/") &&
                    $0.payload["insightId"] != nil
            },
            "Missing full insight save payload.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            writes.contains {
                isSetWrite($0, merge: true) &&
                    $0.path.contains("/insights/") &&
                    $0.payload["deletedAt"] != nil &&
                    $0.payload["insightId"] == nil
            },
            "Missing insight tombstone payload.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            writes.contains {
                isSetWrite($0, merge: true) &&
                    $0.path.contains("/insightDelivery/") &&
                    $0.payload["firstPresentedAt"] != nil
            },
            "Missing insight delivery payload.",
            file: file,
            line: line
        )
        XCTAssertTrue(
            writes.contains {
                isSetWrite($0, merge: true) &&
                    $0.path.contains("/insightEngagement/") &&
                    $0.payload["engagementCounts"] != nil
            },
            "Missing insight engagement payload.",
            file: file,
            line: line
        )
    }

    private func isSetWrite(
        _ write: InMemoryFirestoreDocumentDatabase.AppliedWrite,
        merge expectedMerge: Bool
    ) -> Bool {
        guard case .set(let merge) = write.kind else { return false }
        return merge == expectedMerge
    }

    private func isUpdateWrite(_ write: InMemoryFirestoreDocumentDatabase.AppliedWrite) -> Bool {
        guard case .update = write.kind else { return false }
        return true
    }

    private func isWorkoutDocumentPath(_ path: String) -> Bool {
        path.contains("/workouts/") && !path.contains("/sets/")
    }

    private func writeCoverageSummary(
        _ writes: [InMemoryFirestoreDocumentDatabase.AppliedWrite]
    ) -> String {
        writes
            .map { write in
                "\(write.kind.description) \(write.path) keys=\(write.payload.keys.sorted().joined(separator: ","))"
            }
            .joined(separator: "\n")
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

    private func makeInsight(
        dedupeKey: String,
        headline: String = "Keep the streak specific",
        sourcePolicyVersion: String = AIInsight.currentSourcePolicyVersion,
        createdAt: Date? = nil
    ) -> AIInsight {
        let createdAt = createdAt ?? now
        return AIInsight(
            accountId: accountId,
            type: .consistency,
            headline: headline,
            message: "You trained twice this week, so keep the next block short and repeatable.",
            shortMessage: "Keep the next block repeatable.",
            evidence: [
                InsightEvidence(
                    metric: "weeklyConsistency",
                    value: "2 sessions",
                    comparison: "up from 1",
                    confidence: 0.9
                )
            ],
            recommendedAction: .continuePlan,
            severity: .positive,
            emotionalIntent: .reinforceConsistency,
            userValueScore: 80,
            confidence: 0.9,
            surfaces: [.dashboard, .profile],
            createdAt: createdAt,
            sourcePolicyVersion: sourcePolicyVersion,
            expiresAt: createdAt.addingTimeInterval(86_400),
            dedupeKey: dedupeKey,
            syncMetadata: SyncMetadata(
                localUpdatedAt: createdAt,
                lastSyncedAt: nil,
                serverVersion: nil,
                syncState: .pendingUpload,
                pendingOperationId: nil
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

    private func assertNoForbiddenKeys(
        in payload: [String: Any],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try FirestorePrivacyValidator.validate(payload)
        let forbiddenKeys: Set<String> = [
            "rawvideo",
            "videoframe",
            "cameraframe",
            "faceimage",
            "rawposestream",
            "rawposetimeline",
            "rawlandmarks",
            "rawfaceblendshapestream",
            "biometricfacedata",
            "imagedata",
            "pixelbuffer",
            "apikey",
            "privatekey",
            "serviceaccount"
        ]
        let offendingKeys = allPayloadKeys(in: payload)
            .map(normalizedPayloadKey)
            .filter { forbiddenKeys.contains($0) }

        XCTAssertTrue(
            offendingKeys.isEmpty,
            "Forbidden Firestore payload keys \(offendingKeys) in \(context)",
            file: file,
            line: line
        )
    }

    private func assertNoUnexpectedKeys(
        in value: Any,
        allowedKeys: Set<String>,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let dictionary = value as? [String: Any] {
            let actualKeys = Set(dictionary.keys)
            let unexpectedKeys = actualKeys.subtracting(allowedKeys)
            XCTAssertTrue(
                unexpectedKeys.isEmpty,
                "Unexpected Firestore payload keys \(unexpectedKeys.sorted()) in \(context)",
                file: file,
                line: line
            )

            for (key, nestedValue) in dictionary where !dynamicMapPayloadKeys.contains(key) {
                guard let childKeys = childPublishedKeys(forPayloadKey: key) else { continue }
                assertNoUnexpectedKeys(
                    in: nestedValue,
                    allowedKeys: childKeys,
                    context: "\(context).\(key)",
                    file: file,
                    line: line
                )
            }
            return
        }

        if let array = value as? [Any] {
            for (index, element) in array.enumerated() {
                assertNoUnexpectedKeys(
                    in: element,
                    allowedKeys: allowedKeys,
                    context: "\(context)[\(index)]",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func allowedTopLevelKeys(forFirestorePath path: String) -> Set<String> {
        if path.hasSuffix("/profile/current") {
            return publishedKeys(of: mapToProfileDocument(makeProfile(updatedAt: now)))
        }
        if path.hasSuffix("/calibration/status") {
            return publishedKeys(of: mapToCalibrationDocument(makeCalibrationRecord(operationId: fixedUUID(160_821))))
        }
        if path.contains("/workouts/") && path.contains("/sets/") {
            return publishedKeys(
                of: mapToWorkoutSetDocument(
                    makeSetSummary(exerciseType: .squat, setIndex: 0, formScores: [90]),
                    accountId: accountId,
                    workoutId: fixedUUID(160_822),
                    setId: "squat-set-0",
                    operationId: fixedUUID(160_823)
                )
            )
        }
        if path.contains("/workouts/") {
            return publishedKeys(
                of: mapToWorkoutDocument(
                    makeWorkoutSummary(id: fixedUUID(160_824), operationId: fixedUUID(160_825))
                )
            )
        }
        if path.contains("/trophyEvents/") {
            return publishedKeys(of: mapToTrophyEventDocument(makeTrophyEvent(earnedAt: now)))
        }
        if path.contains("/insights/") {
            return publishedKeys(of: mapToInsightDocument(makeInsight(dedupeKey: "published-keys")))
        }
        if path.contains("/insightDelivery/") {
            return publishedKeys(
                of: mapToInsightDeliveryDocument(
                    InsightDeliveryRecord(
                        accountId: accountId,
                        dedupeKey: "published-delivery",
                        firstPresentedAt: now,
                        lastPresentedAt: now,
                        presentationCount: 1,
                        surfaceLastPresentedAt: [InsightSurface.dashboard.rawValue: now]
                    )
                )
            )
        }
        if path.contains("/insightEngagement/") {
            var record = InsightEngagementRecord(accountId: accountId, dedupeKey: "published-engagement")
            record.record(.opened, at: now)
            return publishedKeys(of: mapToInsightEngagementDocument(record))
        }
        if path.contains("/plans/") {
            return publishedKeys(
                of: mapToPlanDocument(
                    makePlan(id: fixedUUID(160_826), title: "Published Keys Plan"),
                    accountId: accountId,
                    active: true,
                    savedAt: now,
                    operationId: fixedUUID(160_827)
                )
            )
        }

        XCTFail("No DTO key allowlist registered for Firestore path \(path)")
        return []
    }

    private func childPublishedKeys(forPayloadKey key: String) -> Set<String>? {
        switch key {
        case "syncMetadata":
            return publishedKeys(
                of: FirestoreSyncMetadataFields(
                    localUpdatedAt: now,
                    lastSyncedAt: now,
                    serverVersion: "version",
                    syncState: SyncState.synced.rawValue,
                    pendingOperationId: fixedUUID(160_841).uuidString.lowercased()
                )
            )
        case "topCueSummary", "cueEvents":
            return publishedKeys(
                of: FirestoreCueEventDTO(
                    id: fixedUUID(160_842).uuidString.lowercased(),
                    timestamp: now,
                    exerciseType: ExerciseType.squat.rawValue,
                    cueMessage: "Keep the rep smooth.",
                    severity: CoachCue.Severity.warning.rawValue,
                    setIndex: 0,
                    repIndex: 1,
                    secondsIntoSet: 4,
                    formScoreAtEvent: 86,
                    metricKey: "kneeAngle",
                    metricValue: 88
                )
            )
        case "target":
            return publishedKeys(of: FirestoreWorkoutTargetDTO(kind: "reps", value: 10))
        case "qualitySummary":
            return publishedKeys(
                of: FirestoreSetQualitySummaryDTO(
                    totalScoredReps: 1,
                    goodFormReps: 1,
                    excellentFormReps: 0,
                    minFormScore: 86,
                    maxFormScore: 86,
                    averageFormScore: 86,
                    firstHalfAverageFormScore: 86,
                    secondHalfAverageFormScore: 86,
                    breakdownRepIndex: nil,
                    improvementRepIndex: nil,
                    highSeverityCueCount: 0,
                    mostRepeatedCue: nil,
                    qualityTrend: SetQualityTrend.stable.rawValue
                )
            )
        case "repQualityEvents":
            return publishedKeys(
                of: FirestoreRepQualityEventDTO(
                    id: fixedUUID(160_843).uuidString.lowercased(),
                    exerciseType: ExerciseType.squat.rawValue,
                    setIndex: 0,
                    repIndex: 1,
                    timestamp: now,
                    secondsIntoSet: 4,
                    formScore: 86,
                    formGrade: FormScore.Grade.B.rawValue,
                    phase: RepPhase.up.rawValue,
                    cueMessageNearRep: "Keep the rep smooth.",
                    cueSeverityNearRep: CoachCue.Severity.warning.rawValue,
                    effortAtRep: 0.5
                )
            )
        case "structuredEffortSummary":
            return publishedKeys(
                of: FirestoreStructuredEffortSummaryDTO(
                    averageEffort: 0.4,
                    peakEffort: 0.5,
                    trend: EffortTrend.steady.rawValue,
                    source: EffortSource.faceBlendshapeProxy.rawValue
                )
            )
        case "evidence":
            return publishedKeys(
                of: FirestoreInsightEvidenceDTO(
                    id: "evidence",
                    metric: "weeklyConsistency",
                    value: "2 sessions",
                    comparison: "up from 1",
                    workoutId: fixedUUID(160_844).uuidString.lowercased(),
                    exerciseType: ExerciseType.squat.rawValue,
                    setIndex: 0,
                    repIndex: 1,
                    signalId: "signal",
                    confidence: 0.9
                )
            )
        case "blocks":
            return publishedKeys(
                of: FirestoreWorkoutBlockDTO(
                    title: "Main",
                    type: WorkoutBlockType.main.rawValue,
                    exercises: []
                )
            )
        case "exercises":
            return publishedKeys(
                of: FirestorePlannedExerciseDTO(
                    exerciseType: ExerciseType.squat.rawValue,
                    sets: [],
                    restSeconds: 45,
                    coachingFocus: "Depth and control.",
                    cameraPosition: CameraPosition.front.rawValue,
                    allowSwap: true
                )
            )
        case "sets":
            return publishedKeys(
                of: FirestorePlannedSetDTO(
                    setIndex: 1,
                    target: FirestoreWorkoutTargetDTO(kind: "reps", value: 10)
                )
            )
        case "progress":
            return publishedKeys(
                of: FirestoreTrophyProgressDTO(
                    trophyId: TrophyDefinitionCatalog.ID.spark,
                    currentValue: 1,
                    targetValue: 1,
                    earned: true,
                    earnedAt: now,
                    lastUpdatedAt: now,
                    confidence: TrophyProgressConfidence.exact.rawValue,
                    progressLabel: "Earned",
                    accountId: accountId,
                    syncMetadata: nil
                )
            )
        default:
            return nil
        }
    }

    private var dynamicMapPayloadKeys: Set<String> {
        [
            "surfaceLastPresentedAt",
            "engagementCounts",
            "lastEngagementDates"
        ]
    }

    private func publishedKeys(of dto: Any) -> Set<String> {
        Set(
            Mirror(reflecting: dto).children.compactMap { child in
                child.label.map(publishedPayloadKeyName)
            }
        )
    }

    private func publishedPayloadKeyName(_ label: String) -> String {
        switch label {
        case "topCue":
            return "topCueSummary"
        default:
            return label
        }
    }

    private func allPayloadKeys(in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, nestedValue in
                [key] + allPayloadKeys(in: nestedValue)
            }
        }
        if let array = value as? [Any] {
            return array.flatMap(allPayloadKeys)
        }
        return []
    }

    private func normalizedPayloadKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

@MainActor
private final class InMemoryFirestoreDocumentDatabase: FirestoreDocumentDatabase {
    private var documents: [String: FirestoreStoredDocument] = [:]
    private var writeCounts: [String: Int] = [:]
    private var listeners: [String: [UUID: (Result<FirestoreStoredDocument?, Error>) -> Void]] = [:]
    private var queryListeners: [UUID: QueryListener] = [:]
    private var versionCounter = 0
    private(set) var appliedWrites: [AppliedWrite] = []

    struct AppliedWrite {
        enum Kind: CustomStringConvertible {
            case set(merge: Bool)
            case update

            var description: String {
                switch self {
                case .set(let merge):
                    return merge ? "setData(merge: true)" : "setData(merge: false)"
                case .update:
                    return "updateData"
                }
            }
        }

        let path: String
        let payload: [String: Any]
        let kind: Kind
    }

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

    func listenCollection(
        collectionPath: String,
        filters: [FirestoreQueryFilter],
        orderBy: String?,
        descending: Bool,
        limit: Int?,
        onChange: @escaping (Result<[FirestoreStoredDocument], Error>) -> Void
    ) -> FirestoreListenerHandle {
        let id = UUID()
        let listenerKey = collectionPath
        listeners[listenerKey, default: [:]][id] = { [weak self] _ in
            guard let self else { return }
            do {
                let documents = try self.queryDocumentsSync(
                    collectionPath: collectionPath,
                    filters: filters,
                    orderBy: orderBy,
                    descending: descending,
                    limit: limit
                )
                onChange(.success(documents))
            } catch {
                onChange(.failure(error))
            }
        }
        do {
            let documents = try queryDocumentsSync(
                collectionPath: collectionPath,
                filters: filters,
                orderBy: orderBy,
                descending: descending,
                limit: limit
            )
            onChange(.success(documents))
        } catch {
            onChange(.failure(error))
        }
        return InMemoryFirestoreListenerHandle { [weak self] in
            self?.listeners[listenerKey]?.removeValue(forKey: id)
        }
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
            self.appliedWrites.append(AppliedWrite(path: write.path, payload: payload, kind: .set(merge: merge)))
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
            self.appliedWrites.append(AppliedWrite(path: write.path, payload: payload, kind: .update))
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
        let collectionPath = path.split(separator: "/").dropLast().joined(separator: "/")
        listeners[collectionPath]?.values.forEach {
            $0(.success(nil))
        }
    }

    private func queryDocumentsSync(
        collectionPath: String,
        filters: [FirestoreQueryFilter],
        orderBy: String?,
        descending: Bool,
        limit: Int?
    ) throws -> [FirestoreStoredDocument] {
        let prefix = collectionPath + "/"
        var matches = documents.values.filter { document in
            guard document.path.hasPrefix(prefix),
                  !document.path.dropFirst(prefix.count).contains("/") else {
                return false
            }
            return filters.allSatisfy { filter in
                guard let value = document.data[filter.field] else { return false }
                return filterValue(value, matches: filter.value)
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
                return filterValue(value, matches: filter.value)
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

    private func filterValue(_ value: Any, matches expectedValue: Any) -> Bool {
        if value is NSNull, expectedValue is NSNull {
            return true
        }
        if let number = value as? NSNumber, let expectedBool = expectedValue as? Bool {
            return number.boolValue == expectedBool
        }
        if let bool = value as? Bool, let expectedNumber = expectedValue as? NSNumber {
            return bool == expectedNumber.boolValue
        }
        return String(describing: value) == String(describing: expectedValue)
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
