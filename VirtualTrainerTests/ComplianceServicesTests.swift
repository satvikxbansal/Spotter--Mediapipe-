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
