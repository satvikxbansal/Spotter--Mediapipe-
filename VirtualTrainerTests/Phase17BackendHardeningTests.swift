import XCTest
@testable import VirtualTrainer

@MainActor
final class Phase17BackendHardeningTests: XCTestCase {
    private let accountId = "phase-17-hardening-account"
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    func testPhase17BackendDocumentationExistsAndCoversCostBudget() throws {
        let root = Self.repositoryRootURL()
        let qa = try String(contentsOf: root.appendingPathComponent("Documentation/BackendQAChecklist.md"))
        let emulator = try String(contentsOf: root.appendingPathComponent("Documentation/FirebaseEmulatorSetup.md"))
        let cost = try String(contentsOf: root.appendingPathComponent("Documentation/FirebaseCostBudget.md"))
        let runner = try String(contentsOf: root.appendingPathComponent("Scripts/run_backend_integration_tests.sh"))

        XCTAssertTrue(qa.contains("Fresh Install, Local Mode"))
        XCTAssertTrue(qa.contains("SpringBoard Crash"))
        XCTAssertTrue(emulator.contains("--firebase-emulator"))
        XCTAssertTrue(emulator.contains("SPOTTER_FIREBASE_EMULATOR=1"))
        XCTAssertTrue(emulator.contains("firebase emulators:start --only auth,firestore"))
        XCTAssertTrue(cost.contains("320 writes/month"))
        XCTAssertTrue(cost.contains("Cost Snapshot"))
        XCTAssertTrue(runner.contains("start_firebase_emulators.sh"))
        XCTAssertTrue(runner.contains("SPOTTER_RUN_BACKEND_INTEGRATION_TESTS=1"))
    }

    func testFirestoreCostTrackerRecordsSessionReadsAndWrites() {
        let tracker = FirestoreCostTracker.shared
        tracker.isEnabled = false
        tracker.reset(now: now)

        tracker.recordReads(3, reason: "unitTestRead")
        tracker.recordWrites(5, reason: "unitTestWrite")

        XCTAssertEqual(tracker.snapshot.reads, 3)
        XCTAssertEqual(tracker.snapshot.writes, 5)
        XCTAssertNotNil(tracker.snapshot.lastUpdatedAt)
    }

    func testFullSyncRepresentativePayloadsRejectForbiddenRawAndSecretFields() throws {
        let operationId = fixedUUID(17_100)
        let summary = makeWorkoutSummary(setCount: 4, operationId: operationId)
        let insight = makeInsight(operationId: operationId)
        var engagement = InsightEngagementRecord(
            accountId: accountId,
            dedupeKey: insight.dedupeKey,
            syncMetadata: .initialPendingUpload(operationId: operationId, now: now)
        )
        engagement.record(.helpful, at: now.addingTimeInterval(10), operationId: operationId)

        let payloads = try [
            FirestoreEncodingHelpers.payload(from: mapToProfileDocument(makeProfile(operationId: operationId))),
            FirestoreEncodingHelpers.payload(from: mapToWorkoutDocument(summary, operationId: operationId)),
            FirestoreEncodingHelpers.payload(
                from: mapToWorkoutSetDocument(
                    summary.exerciseSummaries[0],
                    accountId: accountId,
                    workoutId: summary.id,
                    setId: "phase-17-set",
                    operationId: operationId
                )
            ),
            FirestoreEncodingHelpers.payload(from: mapToTrophyEventDocument(makeTrophyEvent(operationId: operationId))),
            FirestoreEncodingHelpers.payload(from: mapToInsightDocument(insight)),
            FirestoreEncodingHelpers.payload(
                from: mapToInsightDeliveryDocument(
                    InsightDeliveryRecord(
                        accountId: accountId,
                        dedupeKey: insight.dedupeKey,
                        presentedAt: now,
                        surface: .dashboard,
                        syncMetadata: .initialPendingUpload(operationId: operationId, now: now)
                    )
                )
            ),
            FirestoreEncodingHelpers.payload(from: mapToInsightEngagementDocument(engagement)),
            FirestoreEncodingHelpers.payload(from: mapToCalibrationDocument(makeCalibrationRecord(operationId: operationId))),
            FirestoreEncodingHelpers.payload(
                from: mapToPlanDocument(
                    makePlan(),
                    accountId: accountId,
                    active: true,
                    savedAt: now,
                    syncMetadata: .initialPendingUpload(operationId: operationId, now: now),
                    operationId: operationId
                )
            )
        ]

        for payload in payloads {
            XCTAssertNoThrow(try FirestorePrivacyValidator.validate(payload))
            let keys = flattenedKeys(in: payload)
            XCTAssertFalse(keys.contains("rawVideo"))
            XCTAssertFalse(keys.contains("cameraFrame"))
            XCTAssertFalse(keys.contains("faceImage"))
            XCTAssertFalse(keys.contains("rawPoseStream"))
            XCTAssertFalse(keys.contains("rawPoseTimeline"))
            XCTAssertFalse(keys.contains("rawFaceBlendshapeStream"))
            XCTAssertFalse(keys.contains("biometricFaceData"))
            XCTAssertFalse(keys.contains("apiKey"))
            XCTAssertFalse(keys.contains("secret"))
        }
    }

    func testAnalyticsPrivacyGuardRejectsPIIAndAllowsDocumentedCatalog() {
        XCTAssertTrue(AnalyticsEventCatalog.privacySamples.allSatisfy(AnalyticsPrivacyGuard.isAllowed))
        XCTAssertFalse(
            AnalyticsPrivacyGuard.isAllowed(
                AnalyticsEvent(
                    .syncError,
                    parameters: [
                        "display_name": "A Person",
                        "raw-pose-timeline": "forbidden",
                        "accountID": accountId
                    ]
                )
            )
        )
    }
}

private extension Phase17BackendHardeningTests {
    func makeProfile(operationId: UUID) -> UserProfile {
        UserProfile(
            id: fixedUUID(17_101),
            accountId: accountId,
            displayName: "Hardening Tester",
            genderIdentity: .preferNotToSay,
            age: 35,
            height: 176,
            heightUnit: .metric,
            weight: 75,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .intermediate,
            equipment: [.bodyweight, .dumbbells],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            preferredSessionLength: .twentyFive,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now,
            syncMetadata: .initialPendingUpload(operationId: operationId, now: now)
        )
    }

    func makeWorkoutSummary(setCount: Int, operationId: UUID) -> WorkoutSessionSummary {
        let sets = (0..<setCount).map { index in
            ExerciseSetSummary(
                exerciseType: index.isMultiple(of: 2) ? .squat : .lunge,
                setIndex: index,
                target: .reps(8),
                achievedReps: 8,
                achievedHoldSeconds: 0,
                averageFormScore: 88,
                completionSource: .targetMet,
                completedAt: now.addingTimeInterval(Double(index * 60)),
                durationSeconds: 45,
                peakEffort: 0.76
            )
        }
        return WorkoutSessionSummary(
            id: fixedUUID(17_102),
            accountId: accountId,
            mode: .plannedWorkout,
            planId: fixedUUID(17_103),
            planTitle: "Hardening Plan",
            title: "Hardening Plan",
            goal: "Validate sync payload privacy.",
            coach: .good,
            startedAt: now.addingTimeInterval(-1_200),
            endedAt: now,
            durationSeconds: 1_200,
            totalReps: sets.reduce(0) { $0 + $1.achievedReps },
            totalHoldSeconds: 0,
            averageFormScore: 88,
            completionPercent: 1,
            exerciseSummaries: sets,
            topCue: nil,
            effortSummary: "Derived summary only.",
            createdAt: now,
            syncMetadata: .initialPendingUpload(operationId: operationId, now: now)
        )
    }

    func makeTrophyEvent(operationId: UUID) -> TrophyUnlockEvent {
        TrophyUnlockEvent(
            id: fixedUUID(17_104),
            accountId: accountId,
            trophyId: "first_saved_workout",
            title: "First Save",
            subtitle: "Saved the first workout.",
            earnedAt: now,
            reason: "A derived trophy event crossed the local threshold.",
            celebrationStyle: .standard,
            syncMetadata: .initialPendingUpload(operationId: operationId, now: now)
        )
    }

    func makeInsight(operationId: UUID) -> AIInsight {
        AIInsight(
            accountId: accountId,
            type: .consistency,
            headline: "Consistency is building",
            message: "The last few sessions were completed on schedule.",
            shortMessage: "Schedule is steady.",
            evidence: [
                InsightEvidence(metric: "workouts", value: "3 in 7 days", confidence: 0.9)
            ],
            recommendedAction: .continuePlan,
            severity: .positive,
            emotionalIntent: .reinforceConsistency,
            userValueScore: 80,
            confidence: 0.9,
            surfaces: [.dashboard, .workoutSummary],
            createdAt: now,
            expiresAt: now.addingTimeInterval(86_400),
            dedupeKey: "phase17-consistency",
            syncMetadata: .initialPendingUpload(operationId: operationId, now: now)
        )
    }

    func makeCalibrationRecord(operationId: UUID) -> CalibrationRecord {
        CalibrationRecord(
            id: fixedUUID(17_105),
            accountId: accountId,
            status: .completed,
            exerciseType: .squat,
            targetReps: 3,
            completedReps: 3,
            startedAt: now.addingTimeInterval(-60),
            completedAt: now,
            visibilityPassed: true,
            averageFormScore: 87,
            syncMetadata: .initialPendingUpload(operationId: operationId, now: now)
        )
    }

    func makePlan() -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: fixedUUID(17_106),
            title: "Internal Beta Plan",
            subtitle: "Four-set lower body focus",
            goal: "Build consistency",
            estimatedMinutes: 24,
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
                                PlannedSet(setIndex: 1, target: .reps(8)),
                                PlannedSet(setIndex: 2, target: .reps(8)),
                                PlannedSet(setIndex: 3, target: .reps(8)),
                                PlannedSet(setIndex: 4, target: .reps(8))
                            ],
                            restSeconds: 60,
                            coachingFocus: "Keep reps controlled.",
                            cameraPosition: .front,
                            allowSwap: true
                        )
                    ]
                )
            ],
            generatedAt: now,
            planReason: "Deterministic local beta fixture.",
            source: .generatedLocal
        )
    }

    func flattenedKeys(in value: Any) -> Set<String> {
        var keys = Set<String>()
        collectKeys(from: value, into: &keys)
        return keys
    }

    func collectKeys(from value: Any, into keys: inout Set<String>) {
        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                keys.insert(key)
                collectKeys(from: nested, into: &keys)
            }
        } else if let array = value as? [Any] {
            for nested in array {
                collectKeys(from: nested, into: &keys)
            }
        }
    }

    func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }

    static func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
