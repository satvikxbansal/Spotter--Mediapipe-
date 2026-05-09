import XCTest
@testable import VirtualTrainer

@MainActor
final class InsightStoreTests: XCTestCase {
    func testSelectInsightsDoesNotAdvanceCooldownUntilImpression() async {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let store = InsightStore(fileURL: temporaryInsightURL())
        let profile = makeProfile()
        let insight = makeInsight(
            dedupeKey: "dashboard-repeat",
            score: 100,
            surface: .dashboard,
            now: now
        )

        var selections: [String] = []
        for index in 0..<5 {
            let selection = await store.selectInsights(
                [insight],
                for: .dashboard,
                profile: profile,
                limit: 1,
                now: now.addingTimeInterval(Double(index * 60))
            ).first?.dedupeKey
            if let selection {
                selections.append(selection)
            }
        }

        XCTAssertEqual(selections, Array(repeating: insight.dedupeKey, count: 5))
        XCTAssertNil(store.deliveryRecord(for: insight.dedupeKey))
    }

    func testImpressionAdvancesCooldownForDashboard() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let store = InsightStore(fileURL: temporaryInsightURL())
        let profile = makeProfile()
        let primary = makeInsight(
            dedupeKey: "primary",
            score: 100,
            surface: .dashboard,
            now: now
        )
        let fallback = makeInsight(
            dedupeKey: "fallback",
            score: 70,
            surface: .dashboard,
            now: now
        )

        let firstSelection = await store.selectInsights([primary, fallback], for: .dashboard, profile: profile, limit: 1, now: now).first
        let first = try XCTUnwrap(firstSelection)
        await store.recordImpression(first, on: .dashboard, now: now)
        let second = await store.selectInsights(
            [primary, fallback],
            for: .dashboard,
            profile: profile,
            limit: 1,
            now: now.addingTimeInterval(60)
        ).first

        XCTAssertEqual(first.dedupeKey, primary.dedupeKey)
        XCTAssertEqual(second?.dedupeKey, fallback.dedupeKey)
    }

    func testImportantInsightBypassesCooldownAfterImpression() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let store = InsightStore(fileURL: temporaryInsightURL())
        let profile = makeProfile()
        let insight = makeInsight(
            dedupeKey: "important-safety",
            score: 100,
            severity: .important,
            surface: .dashboard,
            now: now
        )

        let firstSelection = await store.selectInsights([insight], for: .dashboard, profile: profile, limit: 1, now: now).first
        let first = try XCTUnwrap(firstSelection)
        await store.recordImpression(first, on: .dashboard, now: now)
        let second = await store.selectInsights(
            [insight],
            for: .dashboard,
            profile: profile,
            limit: 1,
            now: now.addingTimeInterval(60)
        ).first

        XCTAssertEqual(second?.dedupeKey, insight.dedupeKey)
    }

    func testSelectGeneratedInsightsIgnoresOlderStoredInsights() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let store = InsightStore(fileURL: temporaryInsightURL())
        let profile = makeProfile()
        let oldWorkoutId = UUID(uuidString: "00000000-0000-0000-0000-000000001001") ?? UUID()
        let currentWorkoutId = UUID(uuidString: "00000000-0000-0000-0000-000000001002") ?? UUID()
        let olderHighScore = makeInsight(
            dedupeKey: "older-workout-summary",
            score: 140,
            surface: .workoutSummary,
            now: now.addingTimeInterval(-600),
            workoutId: oldWorkoutId
        )
        let currentLowerScore = makeInsight(
            dedupeKey: "current-workout-summary",
            score: 70,
            surface: .workoutSummary,
            now: now,
            workoutId: currentWorkoutId
        )

        _ = await store.selectInsights(
            [olderHighScore],
            for: .workoutSummary,
            profile: profile,
            limit: 1,
            now: now.addingTimeInterval(-600)
        )
        let selectedCandidate = await store.selectGeneratedInsights(
            [currentLowerScore],
            for: .workoutSummary,
            profile: profile,
            limit: 1,
            now: now
        ).first
        let selected = try XCTUnwrap(selectedCandidate)

        XCTAssertEqual(selected.dedupeKey, currentLowerScore.dedupeKey)
        XCTAssertEqual(selected.evidence.first?.workoutId, currentWorkoutId)
    }

    func testEngagementRecordsPersistAcrossStoreReload() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let url = temporaryInsightURL()
        let profile = makeProfile()
        let insight = makeInsight(
            dedupeKey: "engaged",
            score: 100,
            surface: .profile,
            now: now
        )
        let store = InsightStore(fileURL: url)

        _ = await store.selectInsights([insight], for: .profile, profile: profile, limit: 1, now: now)
        await store.recordEngagement(insight, kind: .helpful, now: now)
        await store.recordEngagement(insight, kind: .notHelpful, now: now.addingTimeInterval(1))

        let reloaded = InsightStore(fileURL: url)
        let record = try XCTUnwrap(reloaded.engagementRecord(for: insight.dedupeKey))

        XCTAssertEqual(record.count(for: .helpful), 1)
        XCTAssertEqual(record.count(for: .notHelpful), 1)
        XCTAssertEqual(record.lastEngagedAt(for: .helpful), now)
    }

    func testDeliveryRecordMergeWithOverlappingSurfacesUsesDateBoundsAndMaxCount() async {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let local = InsightDeliveryRecord(
            accountId: "account-a",
            dedupeKey: "merge-delivery",
            firstPresentedAt: now.addingTimeInterval(10),
            lastPresentedAt: now.addingTimeInterval(30),
            presentationCount: 2,
            surfaceLastPresentedAt: [
                InsightSurface.dashboard.rawValue: now.addingTimeInterval(30),
                InsightSurface.profile.rawValue: now.addingTimeInterval(20)
            ]
        )
        let remote = InsightDeliveryRecord(
            accountId: "account-a",
            dedupeKey: "merge-delivery",
            firstPresentedAt: now,
            lastPresentedAt: now.addingTimeInterval(40),
            presentationCount: 5,
            surfaceLastPresentedAt: [
                InsightSurface.dashboard.rawValue: now.addingTimeInterval(35),
                InsightSurface.workoutSummary.rawValue: now.addingTimeInterval(40)
            ]
        )

        let merged = InsightDeliveryRecord.merged(local: local, remote: remote)

        XCTAssertEqual(merged.firstPresentedAt, now)
        XCTAssertEqual(merged.lastPresentedAt, now.addingTimeInterval(40))
        XCTAssertEqual(merged.presentationCount, 5)
        XCTAssertEqual(merged.surfaceLastPresentedAt[InsightSurface.dashboard.rawValue], now.addingTimeInterval(35))
        XCTAssertEqual(merged.surfaceLastPresentedAt[InsightSurface.profile.rawValue], now.addingTimeInterval(20))
        XCTAssertEqual(merged.surfaceLastPresentedAt[InsightSurface.workoutSummary.rawValue], now.addingTimeInterval(40))
    }

    func testEngagementMergeSumsHelpfulAndNotHelpfulCounts() async {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        var local = InsightEngagementRecord(accountId: "account-a", dedupeKey: "merge-engagement")
        local.record(.helpful, at: now)
        local.record(.helpful, at: now.addingTimeInterval(20))
        local.record(.notHelpful, at: now.addingTimeInterval(10))

        var remote = InsightEngagementRecord(accountId: "account-a", dedupeKey: "merge-engagement")
        remote.record(.helpful, at: now.addingTimeInterval(30))
        remote.record(.notHelpful, at: now.addingTimeInterval(40))

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.count(for: .helpful), 3)
        XCTAssertEqual(merged.count(for: .notHelpful), 2)
        XCTAssertEqual(merged.lastEngagedAt(for: .helpful), now.addingTimeInterval(30))
        XCTAssertEqual(merged.lastEngagedAt(for: .notHelpful), now.addingTimeInterval(40))
    }

    func testRemoteDeliveryTombstoneExportsButNoLongerSuppressesSelection() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let accountId = "account-a"
        let store = InsightStore(fileURL: temporaryInsightURL(), accountId: accountId)
        let profile = makeProfile()
        let insight = makeInsight(
            dedupeKey: "remote-delivery-tombstone",
            score: 100,
            surface: .dashboard,
            now: now
        )

        let firstSelection = await store.selectInsights([insight], for: .dashboard, profile: profile, limit: 1, now: now).first
        let first = try XCTUnwrap(firstSelection)
        await store.recordImpression(first, on: .dashboard, now: now)
        let tombstone = try XCTUnwrap(store.deliveryRecord(for: insight.dedupeKey))
            .markedDeleted(at: now.addingTimeInterval(60))

        assertTrue(await store.applyRemoteDeliveryRecords([tombstone]))

        XCTAssertNil(store.deliveryRecord(for: insight.dedupeKey))
        XCTAssertEqual(store.allDeliveryRecordsIncludingTombstones().first?.deletedAt, now.addingTimeInterval(60))
        assertEqual(
            await store.selectInsights([insight], for: .dashboard, profile: profile, limit: 1, now: now.addingTimeInterval(120)).first?.dedupeKey,
            insight.dedupeKey
        )
    }

    func testRemoteEngagementRecordsMergeAndPersistIncludingTombstones() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let accountId = "account-a"
        let url = temporaryInsightURL()
        let store = InsightStore(fileURL: url, accountId: accountId)
        let insight = makeInsight(
            dedupeKey: "remote-engagement",
            score: 100,
            surface: .profile,
            now: now
        )
        await store.recordEngagement(insight, kind: .helpful, now: now)
        var remote = InsightEngagementRecord(accountId: accountId, dedupeKey: insight.dedupeKey)
        remote.record(.helpful, at: now.addingTimeInterval(10))
        remote.record(.notHelpful, at: now.addingTimeInterval(20))

        assertTrue(await store.applyRemoteEngagementRecords([remote]))

        let merged = try XCTUnwrap(store.engagementRecord(for: insight.dedupeKey))
        XCTAssertEqual(merged.count(for: .helpful), 2)
        XCTAssertEqual(merged.count(for: .notHelpful), 1)
        XCTAssertEqual(
            store.allEngagementRecordsIncludingTombstones().map(\.dedupeKey),
            [insight.dedupeKey]
        )

        let reloaded = InsightStore(fileURL: url, accountId: accountId)
        XCTAssertEqual(reloaded.engagementRecord(for: insight.dedupeKey)?.count(for: .helpful), 2)
        XCTAssertEqual(reloaded.engagementRecord(for: insight.dedupeKey)?.count(for: .notHelpful), 1)
    }

    func testLegacySnapshotWithoutEngagementRecordsStillDecodes() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let url = temporaryInsightURL()
        let insight = makeInsight(
            dedupeKey: "legacy",
            score: 100,
            surface: .profile,
            now: now
        )
        let snapshot = PersistedInsightStoreSnapshot(
            sourcePolicyVersion: AIInsight.currentSourcePolicyVersion,
            savedAt: now,
            recentInsights: [insight],
            deliveryRecords: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try encoder.encode(snapshot)) as? [String: Any]
        )
        object.removeValue(forKey: "engagementRecords")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        try legacyData.write(to: url, options: [.atomic])

        let reloaded = InsightStore(fileURL: url)

        XCTAssertNil(reloaded.persistenceError)
        XCTAssertEqual(reloaded.recentInsights.first?.dedupeKey, insight.dedupeKey)
        XCTAssertNil(reloaded.engagementRecord(for: insight.dedupeKey))
    }

    func testFailedSelectDoesNotExposeUnsavedInsights() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let store = InsightStore(fileURL: try unwritableInsightURL())
        let profile = makeProfile()
        let insight = makeInsight(
            dedupeKey: "unwritable-select",
            score: 100,
            surface: .dashboard,
            now: now
        )

        let selected = await store.selectInsights([insight], for: .dashboard, profile: profile, limit: 1, now: now)

        XCTAssertTrue(selected.isEmpty)
        XCTAssertTrue(store.recentInsights.isEmpty)
        XCTAssertTrue(store.insights(for: .dashboard, profile: profile, limit: 1, now: now).isEmpty)
        XCTAssertNotNil(store.persistenceError)
    }

    func testFailedImpressionDoesNotExposeUnsavedDeliveryRecord() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let store = InsightStore(fileURL: try unwritableInsightURL())
        let insight = makeInsight(
            dedupeKey: "unwritable-impression",
            score: 100,
            surface: .dashboard,
            now: now
        )

        await store.recordImpression(insight, on: .dashboard, now: now)

        XCTAssertNil(store.deliveryRecord(for: insight.dedupeKey))
        XCTAssertNotNil(store.persistenceError)
    }

    func testFailedEngagementDoesNotExposeUnsavedEngagementRecord() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let store = InsightStore(fileURL: try unwritableInsightURL())
        let insight = makeInsight(
            dedupeKey: "unwritable-engagement",
            score: 100,
            surface: .profile,
            now: now
        )

        await store.recordEngagement(insight, kind: .helpful, now: now)

        XCTAssertNil(store.engagementRecord(for: insight.dedupeKey))
        XCTAssertNotNil(store.persistenceError)
    }

    func testLegacyAIInsightJSONWithoutDeletedAtDecodes() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let insight = makeInsight(
            dedupeKey: "legacy-ai-insight",
            score: 100,
            surface: .profile,
            now: now
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try encoder.encode(insight)) as? [String: Any]
        )
        object.removeValue(forKey: "deletedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try decoder.decode(AIInsight.self, from: legacyData)

        XCTAssertEqual(decoded.dedupeKey, insight.dedupeKey)
        XCTAssertNil(decoded.deletedAt)
        XCTAssertFalse(decoded.isDeleted)
    }

    func testInvalidateInsightHidesItFromSelectionAndPreservesBehaviorRecords() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let deletedAt = now.addingTimeInterval(60)
        let store = InsightStore(fileURL: temporaryInsightURL())
        let profile = makeProfile()
        let insight = makeInsight(
            dedupeKey: "invalidate-me",
            score: 100,
            surface: .dashboard,
            now: now
        )

        let selectedCandidate = await store.selectInsights([insight], for: .dashboard, profile: profile, limit: 1, now: now).first
        let selected = try XCTUnwrap(selectedCandidate)
        await store.recordImpression(selected, on: .dashboard, now: now)
        await store.recordEngagement(selected, kind: .helpful, now: now)

        assertTrue(await store.invalidateInsight(dedupeKey: insight.dedupeKey, deletedAt: deletedAt))

        assertTrue(
            await store.selectInsights([insight], for: .dashboard, profile: profile, limit: 1, now: now.addingTimeInterval(120)).isEmpty
        )
        XCTAssertEqual(store.recentInsights.first?.deletedAt, deletedAt)
        XCTAssertNotNil(store.deliveryRecord(for: insight.dedupeKey))
        XCTAssertEqual(store.engagementRecord(for: insight.dedupeKey)?.count(for: .helpful), 1)
    }

    func testInvalidateInsightsReferencingWorkoutHidesOnlyDependentInsights() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let store = InsightStore(fileURL: temporaryInsightURL())
        let profile = makeProfile()
        let deletedWorkoutId = UUID(uuidString: "00000000-0000-0000-0000-000000001201") ?? UUID()
        let keptWorkoutId = UUID(uuidString: "00000000-0000-0000-0000-000000001202") ?? UUID()
        let dependent = makeInsight(
            dedupeKey: "dependent",
            score: 120,
            surface: .profile,
            now: now,
            workoutId: deletedWorkoutId
        )
        let independent = makeInsight(
            dedupeKey: "independent",
            score: 80,
            surface: .profile,
            now: now,
            workoutId: keptWorkoutId
        )

        _ = await store.selectInsights([dependent, independent], for: .profile, profile: profile, limit: 2, now: now)

        assertEqual(
            await store.invalidateInsightsReferencingWorkout(id: deletedWorkoutId, deletedAt: now.addingTimeInterval(1)),
            1
        )

        let visible = store.insights(for: .profile, profile: profile, limit: 5, now: now.addingTimeInterval(2))
        XCTAssertEqual(visible.map(\.dedupeKey), [independent.dedupeKey])
        XCTAssertTrue(store.recentInsights.first { $0.dedupeKey == dependent.dedupeKey }?.isDeleted ?? false)
        XCTAssertFalse(store.recentInsights.first { $0.dedupeKey == independent.dedupeKey }?.isDeleted ?? true)
    }

    func testDeletedInsightsAreNotReturnedBySelectionMethods() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let store = InsightStore(fileURL: temporaryInsightURL())
        let profile = makeProfile()
        let insight = makeInsight(
            dedupeKey: "hidden-everywhere",
            score: 100,
            surface: .workoutSummary,
            now: now
        )

        _ = await store.selectInsights([insight], for: .workoutSummary, profile: profile, limit: 1, now: now)
        assertTrue(await store.invalidateInsight(dedupeKey: insight.dedupeKey, deletedAt: now.addingTimeInterval(1)))

        assertTrue(
            await store.selectInsights([insight], for: .workoutSummary, profile: profile, limit: 1, now: now.addingTimeInterval(2)).isEmpty
        )
        assertTrue(
            await store.selectGeneratedInsights([insight], for: .workoutSummary, profile: profile, limit: 1, now: now.addingTimeInterval(3)).isEmpty
        )
        XCTAssertTrue(
            store.insights(for: .workoutSummary, profile: profile, limit: 1, now: now.addingTimeInterval(4)).isEmpty
        )
    }

    func testRemoveInsightsForDebugPhysicallyRemovesOnlyDebugAndSampleReferencedInsights() async throws {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let store = InsightStore(fileURL: temporaryInsightURL())
        let profile = makeProfile()
        let sampleWorkoutId = UUID(uuidString: "00000000-0000-0000-0000-000000001301") ?? UUID()
        let keptWorkoutId = UUID(uuidString: "00000000-0000-0000-0000-000000001302") ?? UUID()
        let explicitDebug = makeInsight(
            dedupeKey: "debug.sample.explicit",
            score: 130,
            surface: .profile,
            now: now
        )
        let generatedFromSampleWorkout = makeInsight(
            dedupeKey: "generated-from-sample",
            score: 120,
            surface: .profile,
            now: now,
            workoutId: sampleWorkoutId
        )
        let independent = makeInsight(
            dedupeKey: "independent",
            score: 80,
            surface: .profile,
            now: now,
            workoutId: keptWorkoutId
        )

        _ = await store.selectInsights(
            [explicitDebug, generatedFromSampleWorkout, independent],
            for: .profile,
            profile: profile,
            limit: 3,
            now: now
        )
        await store.recordImpression(explicitDebug, on: .profile, now: now)
        await store.recordEngagement(generatedFromSampleWorkout, kind: .helpful, now: now)

        assertTrue(
            await store.removeInsightsForDebug(
                dedupeKeys: [explicitDebug.dedupeKey],
                referencingWorkoutIds: [sampleWorkoutId]
            )
        )

        XCTAssertEqual(store.recentInsights.map(\.dedupeKey), [independent.dedupeKey])
        XCTAssertNil(store.deliveryRecord(for: explicitDebug.dedupeKey))
        XCTAssertNil(store.engagementRecord(for: generatedFromSampleWorkout.dedupeKey))

        let selectedAgainCandidate = await store.selectInsights(
            [generatedFromSampleWorkout],
            for: .profile,
            profile: profile,
            limit: 1,
            now: now.addingTimeInterval(60)
        ).first
        let selectedAgain = try XCTUnwrap(selectedAgainCandidate)
        XCTAssertEqual(selectedAgain.dedupeKey, generatedFromSampleWorkout.dedupeKey)
    }

    func testApplyingRewritePreservesDeletedTombstone() async {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let deletedAt = now.addingTimeInterval(60)
        let insight = makeInsight(
            dedupeKey: "rewrite-deleted",
            score: 100,
            surface: .profile,
            now: now
        ).markedDeleted(at: deletedAt)

        let rewritten = insight.applyingRewrite(
            RewriteResult(headline: "Updated headline")
        )

        XCTAssertEqual(rewritten.headline, "Updated headline")
        XCTAssertEqual(rewritten.deletedAt, deletedAt)
        XCTAssertTrue(rewritten.isDeleted)
    }
}

private extension InsightStoreTests {
    func temporaryInsightURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InsightStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("CoachInsights.json")
    }

    func unwritableInsightURL() throws -> URL {
        let blockedParentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("InsightStoreTests-blocked-\(UUID().uuidString)")
        try Data().write(to: blockedParentURL)
        return blockedParentURL.appendingPathComponent("CoachInsights.json")
    }

    func makeInsight(
        dedupeKey: String,
        score: Double,
        severity: InsightSeverity = .positive,
        surface: InsightSurface,
        now: Date,
        workoutId: UUID? = nil
    ) -> AIInsight {
        AIInsight(
            type: severity == .important ? .safety : .growthCelebration,
            headline: "\(dedupeKey) headline",
            message: "\(dedupeKey) message",
            shortMessage: "\(dedupeKey) short",
            evidence: [
                InsightEvidence(
                    metric: "testMetric",
                    value: dedupeKey,
                    workoutId: workoutId,
                    exerciseType: .squat,
                    confidence: 0.9
                )
            ],
            recommendedAction: severity == .important ? .swapExerciseLater : .continuePlan,
            severity: severity,
            emotionalIntent: severity == .important ? .preventOverreach : .celebrateGrowth,
            userValueScore: score,
            confidence: 0.9,
            surfaces: [surface],
            relatedExerciseType: .squat,
            relatedGoal: .strength,
            createdAt: now,
            expiresAt: now.addingTimeInterval(7 * 24 * 60 * 60),
            dedupeKey: dedupeKey
        )
    }

    func makeProfile() -> UserProfile {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        return UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000008888") ?? UUID(),
            displayName: "Test Athlete",
            genderIdentity: .preferNotToSay,
            age: 30,
            height: 170,
            heightUnit: .metric,
            weight: 70,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .beginner,
            equipment: [.bodyweight],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            preferredSessionLength: .fifteen,
            timezoneIdentifier: "UTC",
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }
}
