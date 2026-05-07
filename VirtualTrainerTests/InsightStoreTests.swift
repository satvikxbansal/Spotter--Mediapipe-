import XCTest
@testable import VirtualTrainer

@MainActor
final class InsightStoreTests: XCTestCase {
    func testSelectInsightsDoesNotAdvanceCooldownUntilImpression() {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        let store = InsightStore(fileURL: temporaryInsightURL())
        let profile = makeProfile()
        let insight = makeInsight(
            dedupeKey: "dashboard-repeat",
            score: 100,
            surface: .dashboard,
            now: now
        )

        let selections = (0..<5).compactMap { index in
            store.selectInsights(
                [insight],
                for: .dashboard,
                profile: profile,
                limit: 1,
                now: now.addingTimeInterval(Double(index * 60))
            ).first?.dedupeKey
        }

        XCTAssertEqual(selections, Array(repeating: insight.dedupeKey, count: 5))
        XCTAssertNil(store.deliveryRecord(for: insight.dedupeKey))
    }

    func testImpressionAdvancesCooldownForDashboard() throws {
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

        let first = try XCTUnwrap(
            store.selectInsights([primary, fallback], for: .dashboard, profile: profile, limit: 1, now: now).first
        )
        store.recordImpression(first, on: .dashboard, now: now)
        let second = store.selectInsights(
            [primary, fallback],
            for: .dashboard,
            profile: profile,
            limit: 1,
            now: now.addingTimeInterval(60)
        ).first

        XCTAssertEqual(first.dedupeKey, primary.dedupeKey)
        XCTAssertEqual(second?.dedupeKey, fallback.dedupeKey)
    }

    func testImportantInsightBypassesCooldownAfterImpression() throws {
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

        let first = try XCTUnwrap(
            store.selectInsights([insight], for: .dashboard, profile: profile, limit: 1, now: now).first
        )
        store.recordImpression(first, on: .dashboard, now: now)
        let second = store.selectInsights(
            [insight],
            for: .dashboard,
            profile: profile,
            limit: 1,
            now: now.addingTimeInterval(60)
        ).first

        XCTAssertEqual(second?.dedupeKey, insight.dedupeKey)
    }

    func testSelectGeneratedInsightsIgnoresOlderStoredInsights() throws {
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

        _ = store.selectInsights(
            [olderHighScore],
            for: .workoutSummary,
            profile: profile,
            limit: 1,
            now: now.addingTimeInterval(-600)
        )
        let selected = try XCTUnwrap(
            store.selectGeneratedInsights(
                [currentLowerScore],
                for: .workoutSummary,
                profile: profile,
                limit: 1,
                now: now
            ).first
        )

        XCTAssertEqual(selected.dedupeKey, currentLowerScore.dedupeKey)
        XCTAssertEqual(selected.evidence.first?.workoutId, currentWorkoutId)
    }

    func testEngagementRecordsPersistAcrossStoreReload() throws {
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

        _ = store.selectInsights([insight], for: .profile, profile: profile, limit: 1, now: now)
        store.recordEngagement(insight, kind: .helpful, now: now)
        store.recordEngagement(insight, kind: .notHelpful, now: now.addingTimeInterval(1))

        let reloaded = InsightStore(fileURL: url)
        let record = try XCTUnwrap(reloaded.engagementRecord(for: insight.dedupeKey))

        XCTAssertEqual(record.count(for: .helpful), 1)
        XCTAssertEqual(record.count(for: .notHelpful), 1)
        XCTAssertEqual(record.lastEngagedAt(for: .helpful), now)
    }

    func testLegacySnapshotWithoutEngagementRecordsStillDecodes() throws {
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
