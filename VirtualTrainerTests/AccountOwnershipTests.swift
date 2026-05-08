import XCTest
@testable import VirtualTrainer

@MainActor
final class AccountOwnershipTests: XCTestCase {
    private let accountA = "account-a"
    private let accountB = "account-b"
    private let now = Date(timeIntervalSince1970: 1_778_067_200)

    func testAccountContextSupportsLocalOnlySetAndClear() {
        let context = AccountContext()

        XCTAssertTrue(context.isLocalOnly)
        XCTAssertNil(context.currentAccountId)

        context.setAccount("  \(accountA)  ")

        XCTAssertFalse(context.isLocalOnly)
        XCTAssertEqual(context.currentAccountId, accountA)

        context.clearAccount()

        XCTAssertTrue(context.isLocalOnly)
        XCTAssertNil(context.currentAccountId)
    }

    func testLegacyOwnershipJSONDecodesWithNilAccountId() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let profile = try decoder.decode(UserProfile.self, from: Data(legacyProfileJSON.utf8))
        let summary = try decoder.decode(WorkoutSessionSummary.self, from: Data(legacyWorkoutSummaryJSON.utf8))
        let trophySnapshot = try decoder.decode(TrophyProgressSnapshot.self, from: Data(legacyTrophySnapshotJSON.utf8))
        let insight = try decoder.decode(AIInsight.self, from: try encodedWithoutAccountId(makeInsight(dedupeKey: "legacy-insight")))
        let deliveryRecord = try decoder.decode(
            InsightDeliveryRecord.self,
            from: try encodedWithoutAccountId(
                InsightDeliveryRecord(dedupeKey: "legacy-insight", presentedAt: now, surface: .dashboard)
            )
        )
        let engagementRecord = try decoder.decode(
            InsightEngagementRecord.self,
            from: try encodedWithoutAccountId(InsightEngagementRecord(dedupeKey: "legacy-insight"))
        )
        let calibrationRecord = try decoder.decode(
            CalibrationRecord.self,
            from: try encodedWithoutAccountId(makeCalibrationRecord())
        )

        XCTAssertNil(profile.accountId)
        XCTAssertNil(summary.accountId)
        XCTAssertNil(trophySnapshot.accountId)
        XCTAssertTrue(trophySnapshot.progress.allSatisfy { $0.accountId == nil })
        XCTAssertTrue(trophySnapshot.newlyEarnedEvents.allSatisfy { $0.accountId == nil })
        XCTAssertNil(insight.accountId)
        XCTAssertNil(deliveryRecord.accountId)
        XCTAssertNil(engagementRecord.accountId)
        XCTAssertNil(calibrationRecord.accountId)
    }

    func testNewSavesStampAccountIdWhenPresentAndLocalOnlyStaysNil() throws {
        let urls = makeStoreURLs()

        let accountProfileStore = OnboardingStore(fileURL: urls.profile, accountId: accountA)
        accountProfileStore.draft = validDraft()
        accountProfileStore.completeOnboarding()
        XCTAssertEqual(accountProfileStore.profile?.accountId, accountA)

        let localProfileStore = OnboardingStore(fileURL: temporaryURL(named: "LocalProfile.json"))
        localProfileStore.draft = validDraft(displayName: "Local Athlete")
        localProfileStore.completeOnboarding()
        XCTAssertNil(localProfileStore.profile?.accountId)

        let accountHistoryStore = WorkoutHistoryStore(fileURL: urls.history, accountId: accountA)
        let accountSummary = makeSummary(idSuffix: "9001")
        XCTAssertTrue(accountHistoryStore.addSummary(accountSummary))
        XCTAssertEqual(accountHistoryStore.fetchSummary(id: accountSummary.id)?.accountId, accountA)

        let localHistoryStore = WorkoutHistoryStore(fileURL: temporaryURL(named: "LocalHistory.json"))
        let localSummary = makeSummary(idSuffix: "9002")
        XCTAssertTrue(localHistoryStore.addSummary(localSummary))
        XCTAssertNil(localHistoryStore.fetchSummary(id: localSummary.id)?.accountId)

        let calibrationStore = CalibrationStore(fileURL: urls.calibration, accountId: accountA)
        XCTAssertTrue(
            calibrationStore.saveCompleted(
                completedReps: 3,
                startedAt: now,
                completedAt: now.addingTimeInterval(30),
                visibilityPassed: true,
                averageFormScore: 90
            )
        )
        XCTAssertEqual(calibrationStore.record?.accountId, accountA)

        let themeStore = ThemeStore(fileURL: urls.theme, defaultTheme: .hyper, accountId: accountA)
        XCTAssertTrue(themeStore.updateSelectedTheme(.warm))
        XCTAssertEqual(ThemeStore(fileURL: urls.theme, defaultTheme: .hyper, accountId: accountA).selectedTheme, .warm)
        XCTAssertEqual(ThemeStore(fileURL: urls.theme, defaultTheme: .hyper, accountId: accountB).selectedTheme, .hyper)

        let insightStore = InsightStore(fileURL: urls.insights, accountId: accountA)
        let insight = makeInsight(dedupeKey: "stamp-insight")
        XCTAssertEqual(
            insightStore.selectInsights([insight], for: .dashboard, profile: makeProfile(), limit: 1, now: now).first?.accountId,
            accountA
        )
        insightStore.recordImpression(insight, on: .dashboard, now: now)
        insightStore.recordEngagement(insight, kind: .helpful, now: now)
        XCTAssertEqual(insightStore.deliveryRecord(for: insight.dedupeKey)?.accountId, accountA)
        XCTAssertEqual(insightStore.engagementRecord(for: insight.dedupeKey)?.accountId, accountA)

        let trophyStore = TrophyStore(fileURL: urls.trophies, accountId: accountA)
        let events = trophyStore.updateAll(
            history: [makeSummary(idSuffix: "9003", accountId: accountA)],
            calibrationStatus: .notStarted,
            now: now
        )
        XCTAssertTrue(trophyStore.snapshot.progress.allSatisfy { $0.accountId == accountA })
        XCTAssertTrue(events.allSatisfy { $0.accountId == accountA })
    }

    func testClaimLocalDataForAccountRewritesNilRecordsAndPersists() throws {
        let urls = makeStoreURLs()

        let profileStore = OnboardingStore(fileURL: urls.profile)
        profileStore.draft = validDraft()
        profileStore.completeOnboarding()
        XCTAssertTrue(profileStore.claimLocalDataForAccount(id: accountA))
        XCTAssertEqual(OnboardingStore(fileURL: urls.profile, accountId: accountA).profile?.accountId, accountA)

        let historyStore = WorkoutHistoryStore(fileURL: urls.history)
        let summary = makeSummary(idSuffix: "9101")
        XCTAssertTrue(historyStore.addSummary(summary))
        XCTAssertTrue(historyStore.claimLocalDataForAccount(id: accountA))
        XCTAssertEqual(
            WorkoutHistoryStore(fileURL: urls.history, accountId: accountA).fetchSummary(id: summary.id)?.accountId,
            accountA
        )

        let calibrationStore = CalibrationStore(fileURL: urls.calibration)
        XCTAssertTrue(calibrationStore.saveSkipped(at: now))
        XCTAssertTrue(calibrationStore.claimLocalDataForAccount(id: accountA))
        XCTAssertEqual(CalibrationStore(fileURL: urls.calibration, accountId: accountA).record?.accountId, accountA)

        let themeStore = ThemeStore(fileURL: urls.theme, defaultTheme: .hyper)
        XCTAssertTrue(themeStore.updateSelectedTheme(.spicy))
        XCTAssertTrue(themeStore.claimLocalDataForAccount(id: accountA))
        XCTAssertEqual(ThemeStore(fileURL: urls.theme, defaultTheme: .hyper, accountId: accountA).selectedTheme, .spicy)

        let insightStore = InsightStore(fileURL: urls.insights)
        let insight = makeInsight(dedupeKey: "claim-insight")
        _ = insightStore.selectInsights([insight], for: .dashboard, profile: makeProfile(), limit: 1, now: now)
        insightStore.recordImpression(insight, on: .dashboard, now: now)
        insightStore.recordEngagement(insight, kind: .opened, now: now)
        XCTAssertTrue(insightStore.claimLocalDataForAccount(id: accountA))
        let reloadedInsightStore = InsightStore(fileURL: urls.insights, accountId: accountA)
        XCTAssertEqual(reloadedInsightStore.recentInsights.first?.accountId, accountA)
        XCTAssertEqual(reloadedInsightStore.deliveryRecord(for: insight.dedupeKey)?.accountId, accountA)
        XCTAssertEqual(reloadedInsightStore.engagementRecord(for: insight.dedupeKey)?.accountId, accountA)

        let trophyStore = TrophyStore(fileURL: urls.trophies)
        _ = trophyStore.updateAll(
            history: [makeSummary(idSuffix: "9102")],
            calibrationStatus: .notStarted,
            now: now
        )
        XCTAssertTrue(trophyStore.claimLocalDataForAccount(id: accountA))
        let reloadedTrophyStore = TrophyStore(fileURL: urls.trophies, accountId: accountA)
        XCTAssertTrue(reloadedTrophyStore.snapshot.progress.allSatisfy { $0.accountId == accountA })
    }

    func testRecordsForAnotherAccountAreFilteredWhenAccountIsSet() throws {
        let urls = makeStoreURLs()

        let profileStore = OnboardingStore(fileURL: urls.profile, accountId: accountA)
        profileStore.draft = validDraft()
        profileStore.completeOnboarding()
        profileStore.setCurrentAccountId(accountB)
        XCTAssertNil(profileStore.profile)

        let historyStore = WorkoutHistoryStore(fileURL: urls.history, accountId: accountA)
        let summary = makeSummary(idSuffix: "9201")
        XCTAssertTrue(historyStore.addSummary(summary))
        historyStore.setCurrentAccountId(accountB)
        XCTAssertTrue(historyStore.fetchRecentSummaries().isEmpty)
        XCTAssertNil(historyStore.fetchSummary(id: summary.id))

        let calibrationStore = CalibrationStore(fileURL: urls.calibration, accountId: accountA)
        XCTAssertTrue(calibrationStore.saveSkipped(at: now))
        calibrationStore.setCurrentAccountId(accountB)
        XCTAssertNil(calibrationStore.record)
        XCTAssertEqual(calibrationStore.status, .notStarted)

        let themeStore = ThemeStore(fileURL: urls.theme, defaultTheme: .hyper, accountId: accountA)
        XCTAssertTrue(themeStore.updateSelectedTheme(.hotGirl))
        themeStore.setCurrentAccountId(accountB)
        XCTAssertEqual(themeStore.selectedTheme, .hyper)

        let insightStore = InsightStore(fileURL: urls.insights, accountId: accountA)
        _ = insightStore.selectInsights(
            [makeInsight(dedupeKey: "other-account-insight")],
            for: .profile,
            profile: makeProfile(),
            limit: 1,
            now: now
        )
        insightStore.setCurrentAccountId(accountB)
        XCTAssertTrue(insightStore.recentInsights.isEmpty)

        let trophyStore = TrophyStore(fileURL: urls.trophies, accountId: accountA)
        _ = trophyStore.updateAll(
            history: [makeSummary(idSuffix: "9202", accountId: accountA)],
            calibrationStatus: .notStarted,
            now: now
        )
        trophyStore.setCurrentAccountId(accountB)
        XCTAssertFalse(trophyStore.snapshot.progress(for: TrophyDefinitionCatalog.ID.spark)?.earned ?? true)
    }
}

private extension AccountOwnershipTests {
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
            .appendingPathComponent("AccountOwnershipTests-\(UUID().uuidString)", isDirectory: true)
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
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountOwnershipTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    func validDraft(displayName: String = "Account Athlete") -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft.displayName = displayName
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
            id: UUID(uuidString: "00000000-0000-0000-0000-000000009990") ?? UUID(),
            accountId: accountId,
            displayName: "Account Athlete",
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

    func makeSummary(idSuffix: String, accountId: String? = nil) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000\(idSuffix)") ?? UUID(),
            accountId: accountId,
            mode: .plannedWorkout,
            title: "Account Test Workout",
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

    func makeInsight(dedupeKey: String, accountId: String? = nil) -> AIInsight {
        AIInsight(
            accountId: accountId,
            type: .growthCelebration,
            headline: "\(dedupeKey) headline",
            message: "\(dedupeKey) message",
            shortMessage: "\(dedupeKey) short",
            evidence: [
                InsightEvidence(
                    metric: "testMetric",
                    value: dedupeKey,
                    workoutId: UUID(uuidString: "00000000-0000-0000-0000-000000009991"),
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
            dedupeKey: dedupeKey
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

    func encodedWithoutAccountId<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try encoder.encode(value)) as? [String: Any]
        )
        object.removeValue(forKey: "accountId")
        return try JSONSerialization.data(withJSONObject: object)
    }

    var legacyProfileJSON: String {
        """
        {
          "id": "00000000-0000-0000-0000-000000009001",
          "displayName": "Legacy Athlete",
          "genderIdentity": "preferNotToSay",
          "age": 31,
          "height": 175,
          "heightUnit": "metric",
          "weight": 72,
          "weightUnit": "metric",
          "primaryGoal": "strength",
          "fitnessLevel": "beginner",
          "equipment": ["bodyweight", "mat"],
          "preferredCoach": "bennett",
          "selectedTheme": "hyper",
          "onboardingCompletedAt": "2026-05-06T00:00:00Z",
          "createdAt": "2026-05-06T00:00:00Z",
          "updatedAt": "2026-05-06T00:00:00Z"
        }
        """
    }

    var legacyWorkoutSummaryJSON: String {
        """
        {
          "id": "00000000-0000-0000-0000-000000009002",
          "mode": "plannedWorkout",
          "title": "Legacy Strength",
          "goal": "Build clean strength.",
          "coach": "good",
          "startedAt": "2026-05-05T10:00:00Z",
          "endedAt": "2026-05-05T10:20:00Z",
          "durationSeconds": 1200,
          "totalReps": 12,
          "totalHoldSeconds": 0,
          "averageFormScore": 88,
          "completionPercent": 1,
          "exerciseSummaries": [
            {
              "exerciseType": "squat",
              "setIndex": 0,
              "achievedReps": 12,
              "achievedHoldSeconds": 0,
              "averageFormScore": 88
            }
          ],
          "topCue": null,
          "effortSummary": "Peak effort reached 50%. Solid working intensity.",
          "createdAt": "2026-05-05T10:20:01Z"
        }
        """
    }

    var legacyTrophySnapshotJSON: String {
        """
        {
          "catalogVersion": \(TrophyDefinitionCatalog.version),
          "generatedAt": "2026-05-05T10:20:01Z",
          "progress": [
            {
              "trophyId": "\(TrophyDefinitionCatalog.ID.spark)",
              "currentValue": 1,
              "targetValue": 1,
              "earned": true,
              "earnedAt": "2026-05-05T10:20:01Z",
              "lastUpdatedAt": "2026-05-05T10:20:01Z",
              "confidence": "exact",
              "progressLabel": "Earned"
            }
          ],
          "newlyEarnedEvents": [
            {
              "id": "00000000-0000-0000-0000-000000009003",
              "trophyId": "\(TrophyDefinitionCatalog.ID.spark)",
              "title": "Spark",
              "subtitle": "Save your first workout.",
              "earnedAt": "2026-05-05T10:20:01Z",
              "reason": "You saved your first workout.",
              "celebrationStyle": "standard"
            }
          ]
        }
        """
    }
}
