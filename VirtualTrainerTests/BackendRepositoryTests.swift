import XCTest
@testable import VirtualTrainer

@MainActor
final class BackendRepositoryTests: XCTestCase {
    private let accountId = "phase-15-account"
    private let now = Date(timeIntervalSince1970: 1_779_000_000)

    func testLocalAuthRepositoryKeepsStableAnonymousIDAcrossSignOutAndReload() async throws {
        let urls = makeRepositoryURLs()
        let repository = LocalAuthRepository(fileURL: urls.auth)

        let firstAccountId = try await repository.signInAnonymously()
        try await repository.signOut()
        let secondAccountId = try await repository.signInAnonymously()
        let reloadedRepository = LocalAuthRepository(fileURL: urls.auth)

        XCTAssertEqual(secondAccountId, firstAccountId)
        XCTAssertEqual(reloadedRepository.currentAccountId, firstAccountId)
        XCTAssertTrue(firstAccountId.hasPrefix("local-"))
    }

    func testLocalAuthRepositoryRejectsAppleLinkAndSignOutDoesNotDeleteLocalData() async throws {
        let urls = makeRepositoryURLs()
        let authRepository = LocalAuthRepository(fileURL: urls.auth)
        let signedInAccountId = try await authRepository.signInAnonymously()
        let workoutRepository = LocalWorkoutRepository(fileURL: urls.workouts, accountId: signedInAccountId)
        let summary = makeSummary(id: fixedUUID("2011"))

        do {
            _ = try await authRepository.linkAnonymousAccountWithApple(idToken: "local-token", nonce: "local-nonce")
            XCTFail("Local mode should not link identity-provider accounts.")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .backendUnavailable)
        }

        try await workoutRepository.saveWorkoutSummary(summary, operationId: fixedUUID("2012"))
        try await authRepository.signOut()

        let loadedSummary = try await workoutRepository.loadWorkout(accountId: signedInAccountId, id: summary.id)

        XCTAssertNil(authRepository.currentAccountId)
        XCTAssertEqual(loadedSummary?.id, summary.id)
    }

    func testLocalProfileRepositorySavesAndLoadsProfile() async throws {
        let urls = makeRepositoryURLs()
        let repository = LocalProfileRepository(fileURL: urls.profile, accountId: accountId)
        let profile = makeProfile()

        let savedProfile = try await repository.saveProfile(profile, operationId: fixedUUID("1001"))
        let loadedProfile = try await repository.loadProfile(accountId: accountId)

        XCTAssertEqual(savedProfile.accountId, accountId)
        XCTAssertEqual(loadedProfile?.displayName, profile.displayName)
        XCTAssertEqual(loadedProfile?.accountId, accountId)
        XCTAssertEqual(loadedProfile?.selectedTheme, .hyper)
    }

    func testLocalWorkoutRepositorySavesLoadsAndDeletesWorkout() async throws {
        let urls = makeRepositoryURLs()
        let repository = LocalWorkoutRepository(fileURL: urls.workouts, accountId: accountId)
        let summary = makeSummary(id: fixedUUID("2001"))

        let savedSummary = try await repository.saveWorkoutSummary(summary, operationId: fixedUUID("2002"))

        let loadedSummary = try await repository.loadWorkout(accountId: accountId, id: summary.id)
        let recentSummaries = try await repository.loadRecentWorkouts(
            accountId: accountId,
            limit: 5,
            since: now.addingTimeInterval(-60)
        )

        XCTAssertEqual(savedSummary.accountId, accountId)
        XCTAssertEqual(loadedSummary?.id, summary.id)
        XCTAssertEqual(loadedSummary?.accountId, accountId)
        XCTAssertEqual(recentSummaries.map(\.id), [summary.id])

        try await repository.deleteWorkout(
            accountId: accountId,
            id: summary.id,
            operationId: fixedUUID("2003")
        )
        try await repository.deleteWorkout(
            accountId: accountId,
            id: summary.id,
            operationId: fixedUUID("2003")
        )

        let deletedSummary = try await repository.loadWorkout(accountId: accountId, id: summary.id)
        let summariesAfterDelete = try await repository.loadRecentWorkouts(
            accountId: accountId,
            limit: 5,
            since: nil
        )

        XCTAssertNil(deletedSummary)
        XCTAssertTrue(summariesAfterDelete.isEmpty)
    }

    func testLocalTrophyRepositoryPersistsUnlockEventLog() async throws {
        let urls = makeRepositoryURLs()
        let repository = LocalTrophyRepository(fileURL: urls.trophies, accountId: accountId)
        let definitions = try await repository.loadTrophyDefinitions()
        let definition = try XCTUnwrap(definitions.first { $0.id == TrophyDefinitionCatalog.ID.spark })
        let event = TrophyUnlockEvent(
            trophyId: definition.id,
            title: definition.title,
            subtitle: definition.subtitle,
            earnedAt: now,
            reason: "Repository test unlock.",
            celebrationStyle: .standard
        )

        let savedEvent = try await repository.saveTrophyEvent(event, operationId: fixedUUID("3001"))

        let events = try await repository.loadTrophyEvents(
            accountId: accountId,
            since: now.addingTimeInterval(-1)
        )
        let progress = try await repository.loadTrophyProgress(accountId: accountId)

        XCTAssertEqual(savedEvent.accountId, accountId)
        XCTAssertEqual(events.map(\.trophyId), [TrophyDefinitionCatalog.ID.spark])
        XCTAssertTrue(progress.first { $0.trophyId == TrophyDefinitionCatalog.ID.spark }?.earned ?? false)
    }

    func testLocalRepositoryObserversEmitAfterLocalWrites() async throws {
        let urls = makeRepositoryURLs()
        let profileRepository = LocalProfileRepository(fileURL: urls.profile, accountId: accountId)
        let workoutRepository = LocalWorkoutRepository(fileURL: urls.workouts, accountId: accountId)
        let trophyRepository = LocalTrophyRepository(fileURL: urls.trophies, accountId: accountId)
        let profile = makeProfile()
        let summary = makeSummary(id: fixedUUID("3101"))
        let trophyEvent = TrophyUnlockEvent(
            trophyId: TrophyDefinitionCatalog.ID.spark,
            title: "Spark",
            subtitle: "First saved workout",
            earnedAt: now,
            reason: "Observer test unlock.",
            celebrationStyle: .standard
        )

        let profileStream = try await profileRepository.observeProfile(accountId: accountId)
        var profileIterator = profileStream.makeAsyncIterator()
        let initialProfile = await profileIterator.next() ?? nil
        XCTAssertNil(initialProfile)

        try await profileRepository.saveProfile(profile, operationId: fixedUUID("3102"))
        let observedProfileCandidate = await profileIterator.next() ?? nil
        let observedProfile = try XCTUnwrap(observedProfileCandidate)

        XCTAssertEqual(observedProfile.displayName, profile.displayName)

        let workoutStream = try await workoutRepository.observeRecentWorkouts(accountId: accountId, limit: 5)
        var workoutIterator = workoutStream.makeAsyncIterator()
        let initialWorkouts = await workoutIterator.next() ?? []
        XCTAssertEqual(initialWorkouts, [])

        try await workoutRepository.saveWorkoutSummary(summary, operationId: fixedUUID("3103"))
        let observedWorkouts = await workoutIterator.next() ?? []

        XCTAssertEqual(observedWorkouts.map(\.id), [summary.id])

        let trophyStream = try await trophyRepository.observeTrophyEvents(accountId: accountId)
        var trophyIterator = trophyStream.makeAsyncIterator()
        let initialTrophyEvents = await trophyIterator.next() ?? []
        XCTAssertEqual(initialTrophyEvents, [])

        try await trophyRepository.saveTrophyEvent(trophyEvent, operationId: fixedUUID("3104"))
        let observedTrophyEvents = await trophyIterator.next() ?? []

        XCTAssertEqual(observedTrophyEvents.map(\.trophyId), [TrophyDefinitionCatalog.ID.spark])
    }

    func testLocalInsightRepositoryPersistsInsightsDeliveryAndEngagement() async throws {
        let urls = makeRepositoryURLs()
        let repository = LocalInsightRepository(fileURL: urls.insights, accountId: accountId)
        let insight = makeInsight(dedupeKey: "phase-15-insight")
        let deliveryRecord = InsightDeliveryRecord(
            dedupeKey: insight.dedupeKey,
            presentedAt: now,
            surface: .dashboard
        )
        var engagementRecord = InsightEngagementRecord(dedupeKey: insight.dedupeKey)
        engagementRecord.record(.helpful, at: now.addingTimeInterval(10))

        let savedInsights = try await repository.saveInsights([insight], operationId: fixedUUID("4001"))
        let savedDeliveryRecord = try await repository.saveDeliveryRecord(deliveryRecord, operationId: fixedUUID("4002"))
        let savedEngagementRecord = try await repository.saveEngagementRecord(engagementRecord, operationId: fixedUUID("4003"))

        let insights = try await repository.loadRecentInsights(accountId: accountId, limit: 5)
        let deliveryRecords = try await repository.loadDeliveryRecords(accountId: accountId)
        let engagementRecords = try await repository.loadEngagementRecords(accountId: accountId)

        XCTAssertEqual(savedInsights.first?.accountId, accountId)
        XCTAssertEqual(savedDeliveryRecord.accountId, accountId)
        XCTAssertEqual(savedEngagementRecord.accountId, accountId)
        XCTAssertEqual(insights.map(\.dedupeKey), [insight.dedupeKey])
        XCTAssertEqual(insights.first?.accountId, accountId)
        XCTAssertEqual(deliveryRecords.first?.dedupeKey, insight.dedupeKey)
        XCTAssertEqual(deliveryRecords.first?.accountId, accountId)
        XCTAssertEqual(engagementRecords.first?.count(for: .helpful), 1)
        XCTAssertEqual(engagementRecords.first?.accountId, accountId)
    }

    func testLocalInsightRepositoryInvalidationIsIdempotentForRetriedOperation() async throws {
        let urls = makeRepositoryURLs()
        let repository = LocalInsightRepository(fileURL: urls.insights, accountId: accountId)
        let insight = makeInsight(dedupeKey: "phase-15-invalidated-insight")
        let operationId = fixedUUID("4011")

        try await repository.saveInsights([insight], operationId: fixedUUID("4010"))
        try await repository.invalidateInsight(
            accountId: accountId,
            dedupeKey: insight.dedupeKey,
            operationId: operationId
        )
        try await repository.invalidateInsight(
            accountId: accountId,
            dedupeKey: insight.dedupeKey,
            operationId: operationId
        )

        let insights = try await repository.loadRecentInsights(accountId: accountId, limit: 5)

        XCTAssertFalse(insights.contains { $0.dedupeKey == insight.dedupeKey })
    }

    func testLocalThemeRepositorySavesAndLoadsTheme() async throws {
        let urls = makeRepositoryURLs()
        let repository = LocalThemeRepository(fileURL: urls.theme, accountId: accountId)

        try await repository.saveTheme(.spicy, accountId: accountId, operationId: fixedUUID("5001"))
        let loadedTheme = try await repository.loadTheme(accountId: accountId)

        XCTAssertEqual(loadedTheme, .spicy)
    }

    func testLocalCalibrationRepositorySavesAndLoadsRecord() async throws {
        let urls = makeRepositoryURLs()
        let repository = LocalCalibrationRepository(fileURL: urls.calibration, accountId: accountId)
        let record = CalibrationRecord.completed(
            completedReps: 3,
            startedAt: now,
            completedAt: now.addingTimeInterval(30),
            visibilityPassed: true,
            averageFormScore: 91
        )

        let savedRecord = try await repository.saveCalibrationRecord(record, operationId: fixedUUID("6001"))
        let loadedRecord = try await repository.loadCalibrationRecord(accountId: accountId)

        XCTAssertEqual(savedRecord.accountId, accountId)
        XCTAssertEqual(loadedRecord?.status, .completed)
        XCTAssertEqual(loadedRecord?.accountId, accountId)
        XCTAssertTrue(loadedRecord?.isSuccessfulCalibration ?? false)
    }

    func testLocalPlanRepositorySavesActivePlanAndHistory() async throws {
        let urls = makeRepositoryURLs()
        let repository = LocalPlanRepository(fileURL: urls.plans)
        let firstPlan = makePlan(id: fixedUUID("7001"), title: "Repository Strength")
        let secondPlan = makePlan(id: fixedUUID("7002"), title: "Repository Mobility")

        _ = try await repository.saveActivePlan(firstPlan, accountId: accountId, operationId: fixedUUID("7003"))
        let savedSecondPlan = try await repository.saveActivePlan(
            secondPlan,
            accountId: accountId,
            operationId: fixedUUID("7004")
        )

        let activePlan = try await repository.loadActivePlan(accountId: accountId)
        let history = try await repository.loadPlanHistory(accountId: accountId, limit: 5)

        XCTAssertEqual(savedSecondPlan.id, secondPlan.id)
        XCTAssertEqual(activePlan?.id, secondPlan.id)
        XCTAssertEqual(history.map(\.id), [secondPlan.id, firstPlan.id])
    }

    func testLocalPlanRepositoryRapidConcurrentSavesKeepHistoryAndOneActivePlan() async throws {
        let urls = makeRepositoryURLs()
        let repository = LocalPlanRepository(fileURL: urls.plans)
        let firstPlan = makePlan(id: fixedUUID("7011"), title: "Repository Strength Burst")
        let secondPlan = makePlan(id: fixedUUID("7012"), title: "Repository Mobility Burst")

        async let firstSave = repository.saveActivePlan(
            firstPlan,
            accountId: accountId,
            operationId: fixedUUID("7013")
        )
        async let secondSave = repository.saveActivePlan(
            secondPlan,
            accountId: accountId,
            operationId: fixedUUID("7014")
        )
        _ = try await (firstSave, secondSave)

        let activePlan = try await repository.loadActivePlan(accountId: accountId)
        let history = try await repository.loadPlanHistory(accountId: accountId, limit: 5)

        XCTAssertTrue([firstPlan.id, secondPlan.id].contains(try XCTUnwrap(activePlan).id))
        XCTAssertEqual(Set(history.map(\.id)), Set([firstPlan.id, secondPlan.id]))
        XCTAssertEqual(history.count, 2)
    }

    func testLocalPlanRepositoryRetriedOperationDoesNotDuplicateHistory() async throws {
        let urls = makeRepositoryURLs()
        let repository = LocalPlanRepository(fileURL: urls.plans)
        let plan = makePlan(id: fixedUUID("7021"), title: "Repository Retry")
        let operationId = fixedUUID("7022")

        try await repository.saveActivePlan(plan, accountId: accountId, operationId: operationId)
        try await repository.saveActivePlan(plan, accountId: accountId, operationId: operationId)

        let history = try await repository.loadPlanHistory(accountId: accountId, limit: 5)

        XCTAssertEqual(history.map(\.id), [plan.id])
    }

    func testSyncOrchestratorLocalModeIsNoopAndAppDependenciesStayLocal() async throws {
        let urls = makeRepositoryURLs()
        let dependencies = AppDependencies(
            backendMode: .local,
            auth: LocalAuthRepository(fileURL: urls.auth),
            profile: LocalProfileRepository(fileURL: urls.profile, accountId: accountId),
            workouts: LocalWorkoutRepository(fileURL: urls.workouts, accountId: accountId),
            trophies: LocalTrophyRepository(fileURL: urls.trophies, accountId: accountId),
            insights: LocalInsightRepository(fileURL: urls.insights, accountId: accountId),
            theme: LocalThemeRepository(fileURL: urls.theme, accountId: accountId),
            calibration: LocalCalibrationRepository(fileURL: urls.calibration, accountId: accountId),
            plans: LocalPlanRepository(fileURL: urls.plans)
        )
        let orchestrator = SyncOrchestrator(dependencies: dependencies)

        try await orchestrator.performFullSync()
        try await orchestrator.observeRemote()
        try await orchestrator.enqueueDirtyWrites()

        XCTAssertEqual(dependencies.backendMode, .local)
        XCTAssertEqual(orchestrator.status, .idle)
    }
}

private extension BackendRepositoryTests {
    struct RepositoryURLs {
        let auth: URL
        let profile: URL
        let workouts: URL
        let trophies: URL
        let insights: URL
        let theme: URL
        let calibration: URL
        let plans: URL
    }

    func makeRepositoryURLs() -> RepositoryURLs {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackendRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return RepositoryURLs(
            auth: directory.appendingPathComponent("LocalAuth.json"),
            profile: directory.appendingPathComponent("UserProfile.json"),
            workouts: directory.appendingPathComponent("WorkoutHistory.json"),
            trophies: directory.appendingPathComponent("TrophyProgress.json"),
            insights: directory.appendingPathComponent("CoachInsights.json"),
            theme: directory.appendingPathComponent("Theme.json"),
            calibration: directory.appendingPathComponent("CalibrationRecord.json"),
            plans: directory.appendingPathComponent("WorkoutPlans.json")
        )
    }

    func makeProfile() -> UserProfile {
        UserProfile(
            id: fixedUUID("9001"),
            displayName: "Repository Athlete",
            genderIdentity: .preferNotToSay,
            age: 31,
            height: 175,
            heightUnit: .metric,
            weight: 72,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .beginner,
            equipment: [.bodyweight, .mat],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            preferredSessionLength: .twentyFive,
            timezoneIdentifier: "UTC",
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    func makeSummary(id: UUID) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            id: id,
            mode: .plannedWorkout,
            title: "Repository Workout",
            goal: "Build clean strength.",
            coach: .good,
            startedAt: now.addingTimeInterval(-600),
            endedAt: now,
            durationSeconds: 600,
            totalReps: 12,
            totalHoldSeconds: 0,
            averageFormScore: 88,
            completionPercent: 1,
            exerciseSummaries: [
                ExerciseSetSummary(
                    exerciseType: .squat,
                    setIndex: 0,
                    target: .reps(12),
                    achievedReps: 12,
                    achievedHoldSeconds: 0,
                    averageFormScore: 88
                )
            ],
            topCue: nil,
            effortSummary: "No face-effort signal was captured for this session.",
            createdAt: now
        )
    }

    func makeInsight(dedupeKey: String) -> AIInsight {
        AIInsight(
            type: .growthCelebration,
            headline: "\(dedupeKey) headline",
            message: "\(dedupeKey) message",
            shortMessage: "\(dedupeKey) short",
            evidence: [
                InsightEvidence(
                    metric: "testMetric",
                    value: dedupeKey,
                    workoutId: fixedUUID("9101"),
                    exerciseType: .squat,
                    confidence: 0.9
                )
            ],
            recommendedAction: .continuePlan,
            severity: .positive,
            emotionalIntent: .celebrateGrowth,
            userValueScore: 100,
            confidence: 0.9,
            surfaces: [.dashboard, .profile],
            relatedExerciseType: .squat,
            relatedGoal: .strength,
            createdAt: now,
            expiresAt: now.addingTimeInterval(7 * 24 * 60 * 60),
            dedupeKey: dedupeKey
        )
    }

    func makePlan(id: UUID, title: String) -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: id,
            title: title,
            subtitle: "Repository test plan",
            goal: "Build clean strength.",
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
                            sets: [PlannedSet(setIndex: 1, target: .reps(12))],
                            restSeconds: 45,
                            coachingFocus: "Depth and control.",
                            cameraPosition: .front,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: now,
            planReason: "Stable fixture for repository tests.",
            source: .generatedLocal
        )
    }

    func fixedUUID(_ suffix: String) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-00000000\(suffix)") ?? UUID()
    }
}
