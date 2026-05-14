import Foundation
import XCTest
@testable import VirtualTrainer

@MainActor
final class FirestoreTranslationLayerTests: XCTestCase {
    private let accountId = "phase-16c-account"
    private let now = Date(timeIntervalSince1970: 1_779_100_000)

    func testProfileDTORoundTripSortsLimitationsArrayBackIntoSet() {
        let profile = makeProfile(
            accountId: "  \(accountId)  ",
            limitations: [.wristSensitive, .kneeSensitive, .lowerBackSensitive]
        )

        let document = mapToProfileDocument(profile)
        let roundTrip = mapFromProfileDocument(document)

        XCTAssertEqual(document.accountId, accountId)
        XCTAssertEqual(document.profileId, profile.id.uuidString.lowercased())
        XCTAssertEqual(document.limitations, document.limitations.sorted())
        XCTAssertEqual(roundTrip.limitations, profile.limitations)
        XCTAssertEqual(roundTrip.preferredSessionLength, profile.preferredSessionLength)
        XCTAssertEqual(roundTrip.syncMetadata.pendingOperationId, profile.syncMetadata.pendingOperationId)
    }

    func testWorkoutCompactDTOSizeStaysWithinDocumentedEstimate() throws {
        let summary = makeWorkoutSummary()
        let document = mapToWorkoutDocument(summary)
        let bytes = try historyJSONEncoder().encode(document).count
        let estimatedBytes = firestoreEstimate(forJSONBytes: bytes)

        XCTAssertLessThanOrEqual(
            estimatedBytes,
            try documentedCompactWorkoutEstimate(),
            "A realistic compact workout DTO should stay within the documented compact estimate."
        )
        XCTAssertEqual(document.setCount, summary.exerciseSummaries.count)
        XCTAssertEqual(document.repQualityEventCount, summary.exerciseSummaries.flatMap(\.repQualityEvents).count)
        XCTAssertEqual(document.cueEventCount, summary.exerciseSummaries.flatMap(\.cueEvents).count)
    }

    func testSetDTORoundTripPreservesRepQualityOrderAndFormScores() {
        let setSummary = makeSetSummary(formScores: [92, 81, 74])

        let document = mapToWorkoutSetDocument(
            setSummary,
            accountId: accountId,
            workoutId: fixedUUID(9_001),
            setId: "squat-set-1",
            operationId: fixedUUID(9_002)
        )
        let roundTrip = mapFromWorkoutSetDocument(document)

        XCTAssertEqual(document.repQualityEvents.map { $0.formScore ?? -1 }, [92, 81, 74])
        XCTAssertEqual(roundTrip.repQualityEvents.map(\.repIndex), [1, 2, 3])
        XCTAssertEqual(roundTrip.repQualityEvents.map { $0.formScore ?? -1 }, [92, 81, 74])
        XCTAssertEqual(roundTrip.averageFormScore, setSummary.averageFormScore)
    }

    func testCalibrationDTORoundTripPreservesStatusAndSyncMetadata() {
        let record = CalibrationRecord(
            id: fixedUUID(5_001),
            accountId: accountId,
            status: .completed,
            exerciseType: CalibrationDefaults.exerciseType,
            targetReps: CalibrationDefaults.targetReps,
            completedReps: 3,
            startedAt: now,
            completedAt: now.addingTimeInterval(30),
            serverCompletedAt: now.addingTimeInterval(32),
            visibilityPassed: true,
            averageFormScore: 93,
            notes: "Translation test.",
            syncMetadata: syncMetadata(operationId: fixedUUID(5_002))
        )

        let document = mapToCalibrationDocument(record)
        let roundTrip = mapFromCalibrationDocument(document)

        XCTAssertEqual(document.accountId, accountId)
        XCTAssertEqual(document.calibrationId, record.id.uuidString.lowercased())
        XCTAssertEqual(roundTrip.status, .completed)
        XCTAssertEqual(roundTrip.completedReps, 3)
        XCTAssertEqual(roundTrip.serverCompletedAt, now.addingTimeInterval(32))
        XCTAssertEqual(roundTrip.syncMetadata.pendingOperationId, record.syncMetadata.pendingOperationId)
    }

    func testPlanDTORoundTripPreservesActiveCacheFieldsAndBlocks() {
        let plan = makePlan(id: fixedUUID(5_101), title: "Remote Cache Plan")
        let savedAt = now.addingTimeInterval(44)
        let document = mapToPlanDocument(
            plan,
            accountId: accountId,
            active: true,
            savedAt: savedAt,
            operationId: fixedUUID(5_102)
        )
        let roundTrip = mapFromPlanDocument(document)

        XCTAssertEqual(document.accountId, accountId)
        XCTAssertEqual(document.planId, plan.id.uuidString.lowercased())
        XCTAssertTrue(document.active)
        XCTAssertEqual(document.savedAt, savedAt)
        XCTAssertEqual(roundTrip.id, plan.id)
        XCTAssertEqual(roundTrip.blocks.flatMap(\.exercises).map(\.exerciseType), [.squat])
    }

    func testTrophyEventDTORoundTripPreservesEarnedAtAndServerEarnedAt() {
        let serverEarnedAt = now.addingTimeInterval(8)
        let event = TrophyUnlockEvent(
            id: fixedUUID(8_001),
            accountId: accountId,
            trophyId: TrophyDefinitionCatalog.ID.spark,
            title: "The Spark",
            subtitle: "First workout complete",
            earnedAt: now,
            serverEarnedAt: serverEarnedAt,
            reason: "Saved the first workout.",
            celebrationStyle: .standard,
            syncMetadata: syncMetadata(operationId: fixedUUID(8_002))
        )

        let document = mapToTrophyEventDocument(event)
        let roundTrip = mapFromTrophyEventDocument(document)

        XCTAssertEqual(document.eventId, event.id.uuidString.lowercased())
        XCTAssertEqual(roundTrip.earnedAt, now)
        XCTAssertEqual(roundTrip.serverEarnedAt, serverEarnedAt)
        XCTAssertEqual(roundTrip.dedupeKey, event.dedupeKey)
    }

    func testInsightDeliveryDTOsMergeWithExpectedConflictRules() {
        let local = InsightDeliveryRecord(
            accountId: accountId,
            dedupeKey: "delivery-merge",
            firstPresentedAt: now,
            lastPresentedAt: now.addingTimeInterval(10),
            presentationCount: 2,
            surfaceLastPresentedAt: [
                InsightSurface.dashboard.rawValue: now.addingTimeInterval(10)
            ],
            syncMetadata: syncMetadata(operationId: fixedUUID(7_001))
        )
        let remote = InsightDeliveryRecord(
            accountId: accountId,
            dedupeKey: "delivery-merge",
            firstPresentedAt: now.addingTimeInterval(-60),
            lastPresentedAt: now.addingTimeInterval(40),
            presentationCount: 1,
            surfaceLastPresentedAt: [
                InsightSurface.profile.rawValue: now.addingTimeInterval(40)
            ],
            syncMetadata: syncMetadata(operationId: fixedUUID(7_002))
        )

        let mappedLocal = mapFromInsightDeliveryDocument(mapToInsightDeliveryDocument(local))
        let mappedRemote = mapFromInsightDeliveryDocument(mapToInsightDeliveryDocument(remote))
        let merged = InsightDeliveryRecord.merged(local: mappedLocal, remote: mappedRemote)

        XCTAssertEqual(merged.firstPresentedAt, now.addingTimeInterval(-60))
        XCTAssertEqual(merged.lastPresentedAt, now.addingTimeInterval(40))
        XCTAssertEqual(merged.presentationCount, 2)
        XCTAssertEqual(merged.surfaceLastPresentedAt[InsightSurface.dashboard.rawValue], now.addingTimeInterval(10))
        XCTAssertEqual(merged.surfaceLastPresentedAt[InsightSurface.profile.rawValue], now.addingTimeInterval(40))
    }

    func testPathBuilderRejectsEmptyUIDAndDedupeKey() throws {
        XCTAssertThrowsError(try FirestorePathBuilder.profileDocument(uid: "  "))
        XCTAssertThrowsError(try FirestorePathBuilder.insight(uid: accountId, dedupeKey: ""))

        XCTAssertEqual(
            try FirestorePathBuilder.setDocument(
                uid: accountId,
                workoutId: "workout-1",
                setId: "set-1"
            ),
            "users/\(accountId)/workouts/workout-1/sets/set-1"
        )
    }

    func testPrivacyValidatorRejectsRawFrameAPIKeyAndPrivateKeyPayloads() {
        XCTAssertThrowsError(
            try FirestorePrivacyValidator.validate([
                "cameraFrame": Data(repeating: 0, count: 4_097)
            ])
        )

        let googleKey = "AIza" + String(repeating: "A", count: 35)
        XCTAssertThrowsError(
            try FirestorePrivacyValidator.validate([
                "apiKey": googleKey
            ])
        )

        let privateKeyField = "private" + "_key"
        let privateKeyValue = "-----" + "BEGIN PRIVATE KEY-----"
        XCTAssertThrowsError(
            try FirestorePrivacyValidator.validate([
                privateKeyField: privateKeyValue
            ])
        )
    }

    func testPrivacyValidatorAllowsFullyPopulatedWorkoutDTO() throws {
        let summary = makeWorkoutSummary(serverEndedAt: now.addingTimeInterval(140))
        let document = mapToWorkoutDocument(summary)
        let payload = try FirestoreEncodingHelpers.payload(from: document)

        XCTAssertEqual(payload["workoutId"] as? String, summary.id.uuidString.lowercased())
        XCTAssertNoThrow(try FirestorePrivacyValidator.validate(payload))
    }

    func testEncodingHelperInjectsServerTimestampMarkerForNilServerDatesAndLowercaseUUIDs() throws {
        let summary = makeWorkoutSummary(serverEndedAt: nil)
        let document = mapToWorkoutDocument(summary)
        let payload = try FirestoreEncodingHelpers.payload(from: document)
        let serverEndedAt = try XCTUnwrap(payload["serverEndedAt"])

        XCTAssertTrue(String(describing: type(of: serverEndedAt)).contains("FieldValue"))
        XCTAssertEqual(payload["operationId"] as? String, document.operationId.uuidString.lowercased())
    }

    func testWorkoutDocumentCanRebuildSummaryWithSortedSetDocuments() {
        let workoutId = fixedUUID(6_001)
        let firstSet = makeSetSummary(setIndex: 1, formScores: [91])
        let secondSet = makeSetSummary(setIndex: 2, formScores: [88])
        let summary = makeWorkoutSummary(
            id: workoutId,
            sets: [firstSet, secondSet],
            serverEndedAt: now.addingTimeInterval(90)
        )
        let workoutDocument = mapToWorkoutDocument(summary)
        let setDocuments = [
            mapToWorkoutSetDocument(secondSet, accountId: accountId, workoutId: workoutId, setId: "set-2"),
            mapToWorkoutSetDocument(firstSet, accountId: accountId, workoutId: workoutId, setId: "set-1")
        ]

        let roundTrip = mapFromWorkoutDocument(workoutDocument, sets: setDocuments)

        XCTAssertEqual(roundTrip.exerciseSummaries.map(\.setIndex), [1, 2])
        XCTAssertEqual(roundTrip.exerciseSummaries.flatMap(\.repQualityEvents).map(\.formScore), [91, 88])
    }
}

private extension FirestoreTranslationLayerTests {
    func makeProfile(
        accountId: String?,
        limitations: Set<PhysicalLimitation>
    ) -> UserProfile {
        UserProfile(
            id: fixedUUID(1_001),
            accountId: accountId,
            displayName: "Casey Runner",
            genderIdentity: .preferNotToSay,
            age: 34,
            height: 173,
            heightUnit: .metric,
            weight: 68,
            weightUnit: .metric,
            primaryGoal: .performance,
            fitnessLevel: .intermediate,
            equipment: [.mat, .bodyweight, .bands],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            limitations: limitations,
            preferredSessionLength: .twentyFive,
            workoutDaysPerWeek: 4,
            reminderPreference: .morning,
            timezoneIdentifier: "Asia/Kolkata",
            avatarStyle: .performance,
            onboardingCompletedAt: now.addingTimeInterval(-1_000),
            createdAt: now.addingTimeInterval(-1_000),
            updatedAt: now,
            syncMetadata: syncMetadata(operationId: fixedUUID(1_002))
        )
    }

    func makeWorkoutSummary(
        id: UUID? = nil,
        sets: [ExerciseSetSummary]? = nil,
        serverEndedAt: Date? = nil
    ) -> WorkoutSessionSummary {
        let exerciseSummaries = sets ?? [makeSetSummary(setIndex: 1, formScores: [96, 88, 82])]
        let allCueEvents = exerciseSummaries.flatMap(\.cueEvents)
        let allRepEvents = exerciseSummaries.flatMap(\.repQualityEvents)
        return WorkoutSessionSummary(
            id: id ?? fixedUUID(2_001),
            accountId: accountId,
            summarySchemaVersion: WorkoutSessionSummary.currentSchemaVersion,
            appBuildVersion: "phase-16c-test",
            mode: .plannedWorkout,
            planId: fixedUUID(2_002),
            planTitle: "DTO Builder",
            title: "DTO Builder",
            goal: "Keep Firestore compact.",
            coach: .good,
            startedAt: now,
            endedAt: now.addingTimeInterval(120),
            serverEndedAt: serverEndedAt,
            durationSeconds: 120,
            totalReps: allRepEvents.count,
            totalHoldSeconds: 0,
            averageFormScore: average(allRepEvents.compactMap(\.formScore).map(Double.init)),
            completionPercent: 1,
            exerciseSummaries: exerciseSummaries,
            topCue: allCueEvents.first,
            effortSummary: "Peak effort reached 60%.",
            workoutOutcome: .completed,
            structuredEffortSummary: StructuredEffortSummary.build(
                repQualityEvents: allRepEvents,
                peakEffort: 0.6
            ),
            totalGoodFormReps: nil,
            totalExcellentFormReps: nil,
            totalHighSeverityCues: nil,
            createdAt: now.addingTimeInterval(130),
            deletedAt: nil,
            syncMetadata: syncMetadata(operationId: fixedUUID(2_003))
        )
    }

    func makeSetSummary(
        setIndex: Int = 1,
        formScores: [Int]
    ) -> ExerciseSetSummary {
        let repEvents = formScores.enumerated().map { index, score in
            RepQualityEvent(
                id: fixedUUID(3_000 + index + setIndex * 10),
                exerciseType: .squat,
                setIndex: setIndex,
                repIndex: index + 1,
                timestamp: now.addingTimeInterval(TimeInterval(index)),
                secondsIntoSet: TimeInterval(index * 4),
                formScore: score,
                formGrade: FormScore.Grade.from(score: score).rawValue,
                phase: RepPhase.up.rawValue,
                cueMessageNearRep: index == 0 ? nil : "Keep knees tracking.",
                cueSeverityNearRep: index == 0 ? nil : .warning,
                effortAtRep: 0.4 + Double(index) * 0.1
            )
        }
        let cueEvents = [
            CueEvent(
                id: fixedUUID(4_000 + setIndex),
                timestamp: now.addingTimeInterval(5),
                exerciseType: .squat,
                cueMessage: "Keep knees tracking.",
                severity: .warning,
                setIndex: setIndex,
                repIndex: 2,
                secondsIntoSet: 8,
                formScoreAtEvent: formScores.dropFirst().first
            )
        ]
        let qualitySummary = SetQualitySummary.build(
            repQualityEvents: repEvents,
            cueEvents: cueEvents
        )

        return ExerciseSetSummary(
            exerciseType: .squat,
            setIndex: setIndex,
            target: .reps(formScores.count),
            achievedReps: formScores.count,
            achievedHoldSeconds: 0,
            averageFormScore: qualitySummary.averageFormScore,
            cueEvents: cueEvents,
            restExtended: true,
            skipped: false,
            qualitySummary: qualitySummary,
            repQualityEvents: repEvents,
            completionSource: .targetMet,
            completedAt: now.addingTimeInterval(60),
            durationSeconds: 60,
            peakEffort: 0.7,
            bestCue: "Strong depth.",
            worstCue: "Knees drifted late."
        )
    }

    func makePlan(id: UUID, title: String) -> WorkoutPlanV2 {
        WorkoutPlanV2(
            id: id,
            title: title,
            subtitle: "Translation test plan",
            goal: "Keep sync deterministic.",
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
            planReason: "Stable fixture.",
            source: .generatedLocal
        )
    }

    func syncMetadata(operationId: UUID) -> SyncMetadata {
        SyncMetadata(
            localUpdatedAt: now,
            lastSyncedAt: now.addingTimeInterval(20),
            serverVersion: "version-\(operationId.uuidString.lowercased())",
            syncState: .pendingUpload,
            pendingOperationId: operationId
        )
    }

    func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }

    func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func historyJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func firestoreEstimate(forJSONBytes jsonBytes: Int) -> Int {
        Int((Double(jsonBytes) * 1.35).rounded(.up)) + 1_024
    }

    func documentedCompactWorkoutEstimate() throws -> Int {
        let documentationURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Documentation/FirestoreShape.md")
        let contents = try String(contentsOf: documentationURL)
        let prefix = "compactWorkoutDocumentEstimatedFirestoreBytes: "
        guard let range = contents.range(of: prefix) else {
            XCTFail("FirestoreShape.md is missing compact workout estimate.")
            return 0
        }
        let suffix = contents[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }
}
