import XCTest
@testable import VirtualTrainer

@MainActor
final class SyncMetadataTests: XCTestCase {
    private let accountId = "sync-account"
    private let now = Date(timeIntervalSince1970: 1_778_067_200)

    func testSyncMetadataCodableRoundTrip() throws {
        let operationId = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE"))
        let metadata = SyncMetadata(
            localUpdatedAt: now,
            lastSyncedAt: now.addingTimeInterval(30),
            serverVersion: "server-v1",
            syncState: .pendingUpload,
            pendingOperationId: operationId
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(SyncMetadata.self, from: encoder.encode(metadata))

        XCTAssertEqual(decoded, metadata)
    }

    func testMissingSyncMetadataDecodesAsLocalOnly() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let profile = try decoder.decode(
            UserProfile.self,
            from: try encodedWithoutSyncMetadata(makeProfile(accountId: accountId))
        )
        let summary = try decoder.decode(
            WorkoutSessionSummary.self,
            from: try encodedWithoutSyncMetadata(makeSummary(accountId: accountId))
        )
        let trophyProgress = try decoder.decode(
            TrophyProgress.self,
            from: try encodedWithoutSyncMetadata(makeTrophyProgress(accountId: accountId))
        )
        let trophyEvent = try decoder.decode(
            TrophyUnlockEvent.self,
            from: try encodedWithoutSyncMetadata(makeTrophyUnlockEvent(accountId: accountId))
        )
        let insight = try decoder.decode(
            AIInsight.self,
            from: try encodedWithoutSyncMetadata(makeInsight(accountId: accountId))
        )
        let deliveryRecord = try decoder.decode(
            InsightDeliveryRecord.self,
            from: try encodedWithoutSyncMetadata(
                InsightDeliveryRecord(
                    accountId: accountId,
                    dedupeKey: "delivery",
                    presentedAt: now,
                    surface: .dashboard
                )
            )
        )
        var engagement = InsightEngagementRecord(accountId: accountId, dedupeKey: "engagement")
        engagement.record(.helpful, at: now)
        let engagementRecord = try decoder.decode(
            InsightEngagementRecord.self,
            from: try encodedWithoutSyncMetadata(engagement)
        )
        let calibrationRecord = try decoder.decode(
            CalibrationRecord.self,
            from: try encodedWithoutSyncMetadata(makeCalibrationRecord(accountId: accountId))
        )

        XCTAssertEqual(profile.syncMetadata.syncState, .localOnly)
        XCTAssertEqual(summary.syncMetadata.syncState, .localOnly)
        XCTAssertEqual(trophyProgress.syncMetadata.syncState, .localOnly)
        XCTAssertEqual(trophyEvent.syncMetadata.syncState, .localOnly)
        XCTAssertEqual(insight.syncMetadata.syncState, .localOnly)
        XCTAssertEqual(deliveryRecord.syncMetadata.syncState, .localOnly)
        XCTAssertEqual(engagementRecord.syncMetadata.syncState, .localOnly)
        XCTAssertEqual(calibrationRecord.syncMetadata.syncState, .localOnly)
        XCTAssertNil(summary.serverEndedAt)
        XCTAssertNil(trophyEvent.serverEarnedAt)
        XCTAssertNil(insight.serverCreatedAt)
        XCTAssertNil(calibrationRecord.serverCompletedAt)

        let themeURL = temporaryURL(named: "LegacyTheme.json")
        try XCTUnwrap("""
        {
          "selectedTheme": "warm",
          "accountId": "\(accountId)"
        }
        """.data(using: .utf8)).write(to: themeURL)

        XCTAssertEqual(
            ThemeStore(fileURL: themeURL, defaultTheme: .hyper, accountId: accountId).selectedTheme,
            .warm
        )
    }

    func testAccountOwnedMutationsMarkPendingUpload() throws {
        let urls = makeStoreURLs()

        let profileStore = OnboardingStore(fileURL: urls.profile, accountId: accountId)
        profileStore.draft = validDraft()
        profileStore.completeOnboarding()
        XCTAssertEqual(profileStore.profile?.syncMetadata.syncState, .pendingUpload)

        let historyStore = WorkoutHistoryStore(fileURL: urls.history, accountId: accountId)
        let summary = makeSummary()
        XCTAssertTrue(historyStore.addSummary(summary))
        XCTAssertEqual(historyStore.fetchSummary(id: summary.id)?.syncMetadata.syncState, .pendingUpload)
        XCTAssertEqual(historyStore.fetchDirtyOrDeletedSummaries().map(\.id), [summary.id])

        let calibrationStore = CalibrationStore(fileURL: urls.calibration, accountId: accountId)
        XCTAssertTrue(calibrationStore.saveSkipped(at: now))
        XCTAssertEqual(calibrationStore.record?.syncMetadata.syncState, .pendingUpload)

        let insightStore = InsightStore(fileURL: urls.insights, accountId: accountId)
        let insight = makeInsight()
        _ = insightStore.selectInsights([insight], for: .dashboard, profile: makeProfile(), limit: 1, now: now)
        insightStore.recordImpression(insight, on: .dashboard, now: now)
        insightStore.recordEngagement(insight, kind: .opened, now: now)
        XCTAssertEqual(insightStore.recentInsights.first?.syncMetadata.syncState, .pendingUpload)
        XCTAssertEqual(insightStore.deliveryRecord(for: insight.dedupeKey)?.syncMetadata.syncState, .pendingUpload)
        XCTAssertEqual(insightStore.engagementRecord(for: insight.dedupeKey)?.syncMetadata.syncState, .pendingUpload)

        let trophyStore = TrophyStore(fileURL: urls.trophies, accountId: accountId)
        let events = trophyStore.updateAll(
            history: [makeSummary(accountId: accountId)],
            calibrationStatus: .notStarted,
            now: now
        )
        XCTAssertTrue(trophyStore.snapshot.progress.allSatisfy { $0.syncMetadata.syncState == .pendingUpload })
        XCTAssertTrue(events.allSatisfy { $0.syncMetadata.syncState == .pendingUpload })

        let themeStore = ThemeStore(fileURL: urls.theme, defaultTheme: .hyper, accountId: accountId)
        XCTAssertTrue(themeStore.updateSelectedTheme(.spicy))
        XCTAssertEqual(try themeSyncState(at: urls.theme), "pendingUpload")
    }

    func testAccountOwnedMutationsPersistPendingOperationIds() throws {
        let urls = makeStoreURLs()
        let profileOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000D001") ?? UUID()
        let workoutOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000D002") ?? UUID()
        let calibrationOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000D003") ?? UUID()
        let insightOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000D004") ?? UUID()
        let deliveryOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000D005") ?? UUID()
        let engagementOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000D006") ?? UUID()
        let trophyOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000D007") ?? UUID()
        let themeOperationId = UUID(uuidString: "00000000-0000-0000-0000-00000000D008") ?? UUID()

        let profileStore = OnboardingStore(fileURL: urls.profile, accountId: accountId)
        profileStore.draft = validDraft()
        profileStore.completeOnboarding(operationId: profileOperationId)
        XCTAssertEqual(profileStore.profile?.syncMetadata.pendingOperationId, profileOperationId)

        let historyStore = WorkoutHistoryStore(fileURL: urls.history, accountId: accountId)
        let summary = makeSummary()
        XCTAssertTrue(historyStore.addSummary(summary, operationId: workoutOperationId))
        XCTAssertEqual(historyStore.fetchSummary(id: summary.id)?.syncMetadata.pendingOperationId, workoutOperationId)

        let calibrationStore = CalibrationStore(fileURL: urls.calibration, accountId: accountId)
        XCTAssertTrue(calibrationStore.saveSkipped(at: now, operationId: calibrationOperationId))
        XCTAssertEqual(calibrationStore.record?.syncMetadata.pendingOperationId, calibrationOperationId)

        let insightStore = InsightStore(fileURL: urls.insights, accountId: accountId)
        let insight = makeInsight()
        _ = insightStore.selectInsights(
            [insight],
            for: .dashboard,
            profile: makeProfile(),
            limit: 1,
            now: now,
            operationId: insightOperationId
        )
        insightStore.recordImpression(
            insight,
            on: .dashboard,
            now: now,
            operationId: deliveryOperationId
        )
        insightStore.recordEngagement(
            insight,
            kind: .opened,
            now: now,
            operationId: engagementOperationId
        )
        XCTAssertEqual(insightStore.recentInsights.first?.syncMetadata.pendingOperationId, insightOperationId)
        XCTAssertEqual(insightStore.deliveryRecord(for: insight.dedupeKey)?.syncMetadata.pendingOperationId, deliveryOperationId)
        XCTAssertEqual(insightStore.engagementRecord(for: insight.dedupeKey)?.syncMetadata.pendingOperationId, engagementOperationId)

        let trophyStore = TrophyStore(fileURL: urls.trophies, accountId: accountId)
        let events = trophyStore.updateAll(
            history: [makeSummary(accountId: accountId)],
            calibrationStatus: .notStarted,
            now: now,
            operationId: trophyOperationId
        )
        XCTAssertTrue(trophyStore.snapshot.progress.allSatisfy { $0.syncMetadata.pendingOperationId == trophyOperationId })
        XCTAssertTrue(events.allSatisfy { $0.syncMetadata.pendingOperationId == trophyOperationId })

        let themeStore = ThemeStore(fileURL: urls.theme, defaultTheme: .hyper, accountId: accountId)
        XCTAssertTrue(themeStore.updateSelectedTheme(.spicy, operationId: themeOperationId))
        XCTAssertEqual(try themePendingOperationId(at: urls.theme), themeOperationId)
    }

    func testLocalOnlyMutationsRemainLocalOnlyWithoutAccount() throws {
        let urls = makeStoreURLs()

        let profileStore = OnboardingStore(fileURL: urls.profile)
        profileStore.draft = validDraft()
        profileStore.completeOnboarding()
        XCTAssertEqual(profileStore.profile?.syncMetadata.syncState, .localOnly)

        let historyStore = WorkoutHistoryStore(fileURL: urls.history)
        let summary = makeSummary()
        XCTAssertTrue(historyStore.addSummary(summary))
        XCTAssertEqual(historyStore.fetchSummary(id: summary.id)?.syncMetadata.syncState, .localOnly)
        XCTAssertTrue(historyStore.fetchDirtyOrDeletedSummaries().isEmpty)

        let calibrationStore = CalibrationStore(fileURL: urls.calibration)
        XCTAssertTrue(calibrationStore.saveSkipped(at: now))
        XCTAssertEqual(calibrationStore.record?.syncMetadata.syncState, .localOnly)

        let insightStore = InsightStore(fileURL: urls.insights)
        let insight = makeInsight()
        _ = insightStore.selectInsights([insight], for: .dashboard, profile: makeProfile(), limit: 1, now: now)
        insightStore.recordImpression(insight, on: .dashboard, now: now)
        insightStore.recordEngagement(insight, kind: .opened, now: now)
        XCTAssertEqual(insightStore.recentInsights.first?.syncMetadata.syncState, .localOnly)
        XCTAssertEqual(insightStore.deliveryRecord(for: insight.dedupeKey)?.syncMetadata.syncState, .localOnly)
        XCTAssertEqual(insightStore.engagementRecord(for: insight.dedupeKey)?.syncMetadata.syncState, .localOnly)

        let trophyStore = TrophyStore(fileURL: urls.trophies)
        _ = trophyStore.updateAll(
            history: [makeSummary()],
            calibrationStatus: .notStarted,
            now: now
        )
        XCTAssertTrue(trophyStore.snapshot.progress.allSatisfy { $0.syncMetadata.syncState == .localOnly })

        let themeStore = ThemeStore(fileURL: urls.theme, defaultTheme: .hyper)
        XCTAssertTrue(themeStore.updateSelectedTheme(.warm))
        XCTAssertEqual(try themeSyncState(at: urls.theme), "localOnly")
    }

    func testThemeStorePersistsSyncMetadataDatesAsISO8601() throws {
        let urls = makeStoreURLs()
        let themeStore = ThemeStore(fileURL: urls.theme, defaultTheme: .hyper, accountId: accountId)

        XCTAssertTrue(themeStore.updateSelectedTheme(.warm))

        let data = try Data(contentsOf: urls.theme)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metadata = try XCTUnwrap(object["syncMetadata"] as? [String: Any])
        let localUpdatedAt = try XCTUnwrap(metadata["localUpdatedAt"] as? String)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: localUpdatedAt))
    }

    func testThemeStoreLoadsLegacyNumericSyncMetadataDates() throws {
        let url = temporaryURL(named: "LegacyNumericTheme.json")
        try Data("""
        {
          "selectedTheme": "spicy",
          "accountId": "\(accountId)",
          "syncMetadata": {
            "localUpdatedAt": 12345,
            "lastSyncedAt": 12346,
            "serverVersion": "legacy-theme-v1",
            "syncState": "synced",
            "pendingOperationId": null
          }
        }
        """.utf8).write(to: url)

        let themeStore = ThemeStore(fileURL: url, defaultTheme: .hyper, accountId: accountId)

        XCTAssertEqual(themeStore.selectedTheme, .spicy)
        XCTAssertNil(themeStore.persistenceError)
    }

    func testConflictPolicyDocumentExists() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Documentation/SyncConflictResolution.md")
        let contents = try String(contentsOf: url)

        XCTAssertTrue(contents.contains("## UserProfile"))
        XCTAssertTrue(contents.contains("## WorkoutSessionSummary"))
        XCTAssertTrue(contents.contains("## TrophyProgress"))
        XCTAssertTrue(contents.contains("## TrophyUnlockEvent"))
        XCTAssertTrue(contents.contains("## AIInsight"))
        XCTAssertTrue(contents.contains("## InsightDeliveryRecord"))
        XCTAssertTrue(contents.contains("## InsightEngagementRecord"))
        XCTAssertTrue(contents.contains("## CalibrationRecord"))
        XCTAssertTrue(contents.contains("## Theme"))
        XCTAssertTrue(contents.contains("conflict"))
    }
}

private extension SyncMetadataTests {
    struct StoreURLs {
        let profile: URL
        let history: URL
        let calibration: URL
        let theme: URL
        let insights: URL
        let trophies: URL
    }

    func makeStoreURLs() -> StoreURLs {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncMetadataTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return StoreURLs(
            profile: directory.appendingPathComponent("UserProfile.json"),
            history: directory.appendingPathComponent("WorkoutHistory.json"),
            calibration: directory.appendingPathComponent("CalibrationRecord.json"),
            theme: directory.appendingPathComponent("Theme.json"),
            insights: directory.appendingPathComponent("CoachInsights.json"),
            trophies: directory.appendingPathComponent("TrophyProgress.json")
        )
    }

    func temporaryURL(named fileName: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncMetadataTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    func validDraft() -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft.displayName = "Sync Athlete"
        draft.genderIdentity = .preferNotToSay
        draft.age = "32"
        draft.height = "175"
        draft.weight = "72"
        draft.primaryGoal = .strength
        draft.fitnessLevel = .beginner
        draft.equipment = [.bodyweight, .mat]
        draft.preferredCoach = .bennett
        draft.selectedTheme = .hyper
        return draft
    }

    func makeProfile(accountId: String? = nil) -> UserProfile {
        UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001") ?? UUID(),
            accountId: accountId,
            displayName: "Sync Athlete",
            genderIdentity: .preferNotToSay,
            age: 32,
            height: 175,
            heightUnit: .metric,
            weight: 72,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .beginner,
            equipment: [.bodyweight, .mat],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }

    func makeSummary(accountId: String? = nil) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A002") ?? UUID(),
            accountId: accountId,
            mode: .plannedWorkout,
            title: "Sync Test Workout",
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

    func makeTrophyProgress(accountId: String? = nil) -> TrophyProgress {
        TrophyProgress(
            trophyId: TrophyDefinitionCatalog.ID.spark,
            currentValue: 1,
            targetValue: 1,
            earned: true,
            earnedAt: now,
            lastUpdatedAt: now,
            confidence: .exact,
            progressLabel: "Earned",
            accountId: accountId
        )
    }

    func makeTrophyUnlockEvent(accountId: String? = nil) -> TrophyUnlockEvent {
        TrophyUnlockEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A003") ?? UUID(),
            accountId: accountId,
            trophyId: TrophyDefinitionCatalog.ID.spark,
            title: "Spark",
            subtitle: "Save your first workout.",
            earnedAt: now,
            reason: "You saved your first workout.",
            celebrationStyle: .standard
        )
    }

    func makeInsight(accountId: String? = nil) -> AIInsight {
        AIInsight(
            accountId: accountId,
            type: .growthCelebration,
            headline: "Sync headline",
            message: "Sync message",
            shortMessage: "Sync short",
            evidence: [
                InsightEvidence(
                    metric: "testMetric",
                    value: "sync",
                    workoutId: UUID(uuidString: "00000000-0000-0000-0000-00000000A004"),
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
            dedupeKey: "sync-insight"
        )
    }

    func makeCalibrationRecord(accountId: String? = nil) -> CalibrationRecord {
        CalibrationRecord.completed(
            accountId: accountId,
            completedReps: 3,
            startedAt: now,
            completedAt: now.addingTimeInterval(30),
            visibilityPassed: true,
            averageFormScore: 90
        )
    }

    func encodedWithoutSyncMetadata<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try encoder.encode(value)) as? [String: Any]
        )
        object.removeValue(forKey: "syncMetadata")
        return try JSONSerialization.data(withJSONObject: object)
    }

    func themeSyncState(at url: URL) throws -> String? {
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metadata = try XCTUnwrap(object["syncMetadata"] as? [String: Any])
        return metadata["syncState"] as? String
    }

    func themePendingOperationId(at url: URL) throws -> UUID? {
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metadata = try XCTUnwrap(object["syncMetadata"] as? [String: Any])
        guard let rawValue = metadata["pendingOperationId"] as? String else { return nil }
        return UUID(uuidString: rawValue)
    }
}
