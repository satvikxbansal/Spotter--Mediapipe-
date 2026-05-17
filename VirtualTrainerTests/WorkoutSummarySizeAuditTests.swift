import Foundation
import XCTest
@testable import VirtualTrainer

final class WorkoutSummarySizeAuditTests: XCTestCase {
    private static let exerciseCount = 8
    private static let setsPerExercise = 4
    private static let repQualityEventsPerSet = 25
    private static let cueEventsPerSet = 10
    private static let firestoreDocumentLimitBytes = 1_048_576
    private static let fullEmbedComfortThresholdBytes = 256 * 1_024
    private static let compactWorkoutDocumentThresholdBytes = 64 * 1_024
    private static let setDocumentThresholdBytes = 64 * 1_024
    private static let firestoreOverheadMultiplier = 1.35
    private static let firestoreFixedOverheadBytes = 1_024

    func testSyntheticWorstCaseSummarySizeSupportsSetSubcollectionShape() throws {
        let sizes = try Self.measureAuditSizes()

        print(
            """
            WorkoutSummarySizeAudit \
            fullEmbeddedJSONBytes=\(sizes.fullEmbeddedJSONBytes) \
            fullEmbeddedEstimatedFirestoreBytes=\(sizes.fullEmbeddedEstimatedFirestoreBytes) \
            compactWorkoutDocumentJSONBytes=\(sizes.compactWorkoutDocumentJSONBytes) \
            compactWorkoutDocumentEstimatedFirestoreBytes=\(sizes.compactWorkoutDocumentEstimatedFirestoreBytes) \
            maxSetDocumentJSONBytes=\(sizes.maxSetDocumentJSONBytes) \
            maxSetDocumentEstimatedFirestoreBytes=\(sizes.maxSetDocumentEstimatedFirestoreBytes)
            """
        )

        XCTAssertEqual(sizes.setDocumentCount, Self.exerciseCount * Self.setsPerExercise)
        XCTAssertEqual(
            sizes.repQualityEventCount,
            Self.exerciseCount * Self.setsPerExercise * Self.repQualityEventsPerSet
        )
        XCTAssertEqual(
            sizes.cueEventCount,
            Self.exerciseCount * Self.setsPerExercise * Self.cueEventsPerSet
        )

        XCTAssertLessThan(
            sizes.fullEmbeddedEstimatedFirestoreBytes,
            Self.firestoreDocumentLimitBytes,
            "The current embedded local-summary shape must stay below Firestore's hard 1 MiB document limit."
        )
        XCTAssertGreaterThan(
            sizes.fullEmbeddedEstimatedFirestoreBytes,
            Self.fullEmbedComfortThresholdBytes,
            "If full embedding drops under the 256 KiB comfort threshold, revisit Documentation/FirestoreShape.md."
        )
        XCTAssertLessThan(
            sizes.compactWorkoutDocumentEstimatedFirestoreBytes,
            Self.compactWorkoutDocumentThresholdBytes,
            "The chosen compact workout document should stay comfortably below 64 KiB."
        )
        XCTAssertLessThan(
            sizes.maxSetDocumentEstimatedFirestoreBytes,
            Self.setDocumentThresholdBytes,
            "The chosen per-set document shape should keep detailed rep/cue evidence comfortably below 64 KiB per set."
        )
    }

    func testFirestoreWorkoutDTOSizeMatchesDocumentedCompactEstimate() throws {
        let fixture = Self.makeAuditFixture()
        let document = mapToWorkoutDocument(
            fixture.summary,
            operationId: Self.uuid(7_000)
        )
        let jsonBytes = try Self.historyJSONEncoder().encode(document).count
        let estimatedBytes = Self.firestoreEstimate(forJSONBytes: jsonBytes)
        let documentedEstimate = try Self.documentedCompactWorkoutEstimate()
        let allowedDelta = max(1, Int((Double(documentedEstimate) * 0.05).rounded(.up)))

        XCTAssertLessThanOrEqual(
            abs(estimatedBytes - documentedEstimate),
            allowedDelta,
            "The implemented compact Firestore workout DTO should stay within 5% of Documentation/FirestoreShape.md."
        )
    }

    func testLargestFirestoreSetDTOStaysUnder64KB() throws {
        let fixture = Self.makeAuditFixture()
        let setDocumentSizes = try fixture.summary.exerciseSummaries.map { setSummary in
            try Self.historyJSONEncoder().encode(
                mapToWorkoutSetDocument(
                    setSummary,
                    accountId: fixture.summary.accountId ?? "",
                    workoutId: fixture.summary.id,
                    setId: firestoreWorkoutSetDocumentId(for: setSummary),
                    operationId: Self.uuid(7_000)
                )
            ).count
        }
        let estimatedBytes = Self.firestoreEstimate(forJSONBytes: setDocumentSizes.max() ?? 0)

        XCTAssertLessThan(
            estimatedBytes,
            Self.setDocumentThresholdBytes,
            "The implemented Firestore set DTO should keep detailed evidence below 64 KiB."
        )
    }

    func testFirestoreSetPrivacyValidatorRejectsRawCameraAndForbiddenNestedPayloads() throws {
        let fixture = Self.makeAuditFixture()
        let setSummary = try XCTUnwrap(fixture.summary.exerciseSummaries.first)
        let setDocument = mapToWorkoutSetDocument(
            setSummary,
            accountId: fixture.summary.accountId ?? "",
            workoutId: fixture.summary.id,
            setId: firestoreWorkoutSetDocumentId(for: setSummary),
            operationId: Self.uuid(7_000)
        )
        var payload = try FirestoreEncodingHelpers.payload(from: setDocument)

        payload["cameraFrame"] = Data(repeating: 0, count: 32)
        XCTAssertThrowsError(try FirestorePrivacyValidator.validate(payload))

        var nestedPayload = try FirestoreEncodingHelpers.payload(from: setDocument)
        nestedPayload["repQualityEvents"] = [
            [
                "repIndex": 1,
                "rawPoseTimeline": "derived tests must still reject this forbidden key"
            ]
        ]
        XCTAssertThrowsError(try FirestorePrivacyValidator.validate(nestedPayload))
    }

    func testFirestoreShapeDocumentExistsAndMatchesAudit() throws {
        let sizes = try Self.measureAuditSizes()
        let documentationURL = Self.repositoryRootURL()
            .appendingPathComponent("Documentation/FirestoreShape.md")
        let contents = try String(contentsOf: documentationURL)

        XCTAssertTrue(contents.contains("Option A"))
        XCTAssertTrue(contents.contains("Option B"))
        XCTAssertTrue(contents.contains("Option C"))
        XCTAssertTrue(contents.contains("Decision: Option B"))
        XCTAssertTrue(contents.contains("users/{uid}/workouts/{workoutId}"))
        XCTAssertTrue(contents.contains("users/{uid}/workouts/{workoutId}/sets/{setId}"))
        XCTAssertTrue(contents.contains("raw camera"))
        XCTAssertTrue(contents.contains("raw pose"))
        XCTAssertTrue(contents.contains("raw biometric face data"))
        XCTAssertTrue(contents.contains("fullEmbeddedJSONBytes: \(sizes.fullEmbeddedJSONBytes)"))
        XCTAssertTrue(
            contents.contains(
                "fullEmbeddedEstimatedFirestoreBytes: \(sizes.fullEmbeddedEstimatedFirestoreBytes)"
            )
        )
        XCTAssertTrue(
            contents.contains(
                "compactWorkoutDocumentEstimatedFirestoreBytes: \(sizes.compactWorkoutDocumentEstimatedFirestoreBytes)"
            )
        )
        XCTAssertTrue(
            contents.contains(
                "maxSetDocumentEstimatedFirestoreBytes: \(sizes.maxSetDocumentEstimatedFirestoreBytes)"
            )
        )
    }

    func testProductionFirebaseUploadCodeIsLimitedToApprovedPhase16Repositories() throws {
        let sourceURL = Self.repositoryRootURL().appendingPathComponent("VirtualTrainer")
        let swiftFiles = try Self.swiftFiles(in: sourceURL)
        let allowedNeedlesByFile: [String: Set<String>] = [
            "VirtualTrainerApp.swift": [
                "FirebaseSmokeVerifier.runIfRequested"
            ],
            "FirebaseBootstrap.swift": [
                "import FirebaseAuth",
                "import FirebaseCore",
                "import FirebaseFirestore",
                "FirebaseApp.configure",
                "Firestore.firestore"
            ],
            "BackendStatusStore.swift": [
                "FirebaseBootstrap.configureIfAvailable"
            ],
            "FirebaseAuthRepository.swift": [
                "import FirebaseAuth",
                "import FirebaseCore"
            ],
            "FirestoreEncodingHelpers.swift": [
                "import FirebaseFirestore"
            ],
            "FirestoreDocumentDatabase.swift": [
                "import FirebaseCore",
                "import FirebaseFirestore",
                "Firestore.firestore",
                ".setData(",
                ".updateData("
            ],
            "FirestoreThemeRepository.swift": [
                "import FirebaseFirestore",
                ".setData("
            ],
            "FirestoreProfileRepository.swift": [
                ".setData("
            ],
            "FirestoreCalibrationRepository.swift": [
                ".setData("
            ],
            "FirestorePlanRepository.swift": [
                ".setData(",
                ".updateData("
            ],
            "FirestoreTrophyRepository.swift": [
                ".setData("
            ],
            "FirestoreInsightRepository.swift": [
                "import FirebaseFirestore",
                ".setData("
            ],
            "FirestoreWorkoutRepository.swift": [
                "import FirebaseFirestore",
                ".setData(",
                ".updateData("
            ],
            "FirebaseSmokeVerifier.swift": [
                "import FirebaseAuth",
                "import FirebaseCore",
                "import FirebaseFirestore",
                "FirebaseBootstrap.configureIfAvailable",
                "Firestore.firestore",
                ".setData("
            ]
        ]
        let trackedNeedles = [
            "import FirebaseCore",
            "import FirebaseAuth",
            "import FirebaseFirestore",
            "FirebaseApp.configure",
            "FirebaseBootstrap.configureIfAvailable",
            "FirebaseSmokeVerifier.runIfRequested",
            "Firestore.firestore",
            ".setData(",
            ".updateData(",
            ".addDocument("
        ]

        let matches = try swiftFiles.flatMap { fileURL in
            let source = try String(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            let allowedNeedles = allowedNeedlesByFile[fileName] ?? []
            return trackedNeedles.compactMap { needle in
                source.contains(needle) && !allowedNeedles.contains(needle)
                    ? "\(fileName): \(needle)"
                    : nil
            }
        }

        XCTAssertTrue(
            matches.isEmpty,
            "Firebase usage must remain limited to app bootstrap, the explicit DEBUG smoke verifier, and intentional Phase 16D/16F Firestore repository APIs: \(matches.joined(separator: ", "))"
        )
    }
}

private extension WorkoutSummarySizeAuditTests {
    struct AuditSizes {
        let fullEmbeddedJSONBytes: Int
        let fullEmbeddedEstimatedFirestoreBytes: Int
        let compactWorkoutDocumentJSONBytes: Int
        let compactWorkoutDocumentEstimatedFirestoreBytes: Int
        let maxSetDocumentJSONBytes: Int
        let maxSetDocumentEstimatedFirestoreBytes: Int
        let setDocumentCount: Int
        let repQualityEventCount: Int
        let cueEventCount: Int
    }

    struct AuditFixture {
        let summary: WorkoutSessionSummary
        let compactWorkoutDocument: CompactWorkoutDocument
        let setDocuments: [SetDocument]
    }

    struct CompactWorkoutDocument: Codable {
        let id: UUID
        let accountId: String?
        let summarySchemaVersion: Int
        let appBuildVersion: String?
        let mode: WorkoutSessionSummaryMode
        let planId: UUID?
        let planTitle: String?
        let title: String
        let goal: String?
        let coach: CoachPersonality
        let startedAt: Date
        let endedAt: Date
        let serverEndedAt: Date?
        let durationSeconds: Int
        let totalReps: Int
        let totalHoldSeconds: Int
        let averageFormScore: Double?
        let completionPercent: Double?
        let setCount: Int
        let repQualityEventCount: Int
        let cueEventCount: Int
        let topCue: CueEvent?
        let effortSummary: String
        let workoutOutcome: WorkoutOutcome
        let structuredEffortSummary: StructuredEffortSummary?
        let totalGoodFormReps: Int
        let totalExcellentFormReps: Int
        let totalHighSeverityCues: Int
        let createdAt: Date
        let deletedAt: Date?
        let syncMetadata: SyncMetadata

        init(summary: WorkoutSessionSummary) {
            id = summary.id
            accountId = summary.accountId
            summarySchemaVersion = summary.summarySchemaVersion
            appBuildVersion = summary.appBuildVersion
            mode = summary.mode
            planId = summary.planId
            planTitle = summary.planTitle
            title = summary.title
            goal = summary.goal
            coach = summary.coach
            startedAt = summary.startedAt
            endedAt = summary.endedAt
            serverEndedAt = summary.serverEndedAt
            durationSeconds = summary.durationSeconds
            totalReps = summary.totalReps
            totalHoldSeconds = summary.totalHoldSeconds
            averageFormScore = summary.averageFormScore
            completionPercent = summary.completionPercent
            setCount = summary.exerciseSummaries.count
            repQualityEventCount = summary.exerciseSummaries.flatMap(\.repQualityEvents).count
            cueEventCount = summary.exerciseSummaries.flatMap(\.cueEvents).count
            topCue = summary.topCue
            effortSummary = summary.effortSummary
            workoutOutcome = summary.workoutOutcome
            structuredEffortSummary = summary.structuredEffortSummary
            totalGoodFormReps = summary.totalGoodFormReps
            totalExcellentFormReps = summary.totalExcellentFormReps
            totalHighSeverityCues = summary.totalHighSeverityCues
            createdAt = summary.createdAt
            deletedAt = summary.deletedAt
            syncMetadata = summary.syncMetadata
        }
    }

    struct SetDocument: Codable {
        let id: String
        let workoutId: UUID
        let exerciseIndex: Int
        let setIndex: Int
        let createdAt: Date
        let summary: ExerciseSetSummary
    }

    static func measureAuditSizes() throws -> AuditSizes {
        let fixture = makeAuditFixture()
        let encoder = historyJSONEncoder()
        let fullEmbeddedJSONBytes = try encoder.encode(fixture.summary).count
        let compactWorkoutDocumentJSONBytes = try encoder.encode(fixture.compactWorkoutDocument).count
        let setDocumentJSONBytes = try fixture.setDocuments.map { try encoder.encode($0).count }

        return AuditSizes(
            fullEmbeddedJSONBytes: fullEmbeddedJSONBytes,
            fullEmbeddedEstimatedFirestoreBytes: firestoreEstimate(forJSONBytes: fullEmbeddedJSONBytes),
            compactWorkoutDocumentJSONBytes: compactWorkoutDocumentJSONBytes,
            compactWorkoutDocumentEstimatedFirestoreBytes: firestoreEstimate(
                forJSONBytes: compactWorkoutDocumentJSONBytes
            ),
            maxSetDocumentJSONBytes: setDocumentJSONBytes.max() ?? 0,
            maxSetDocumentEstimatedFirestoreBytes: firestoreEstimate(forJSONBytes: setDocumentJSONBytes.max() ?? 0),
            setDocumentCount: fixture.summary.exerciseSummaries.count,
            repQualityEventCount: fixture.summary.exerciseSummaries.flatMap(\.repQualityEvents).count,
            cueEventCount: fixture.summary.exerciseSummaries.flatMap(\.cueEvents).count
        )
    }

    static func makeAuditFixture() -> AuditFixture {
        let baseDate = Date(timeIntervalSince1970: 1_777_000_000)
        let exerciseTypes: [ExerciseType] = [
            .squat,
            .pushup,
            .lunge,
            .bicepCurl,
            .mountainClimber,
            .russianTwist,
            .plank,
            .overheadPress
        ]
        var setDocuments: [SetDocument] = []

        let sets: [ExerciseSetSummary] = exerciseTypes.enumerated().flatMap { exerciseIndex, exerciseType in
            (0..<setsPerExercise).map { setNumber in
                let globalSetIndex = exerciseIndex * setsPerExercise + setNumber
                let repEvents = makeRepQualityEvents(
                    exerciseType: exerciseType,
                    setIndex: globalSetIndex,
                    baseDate: baseDate
                )
                let cueEvents = makeCueEvents(
                    exerciseType: exerciseType,
                    setIndex: globalSetIndex,
                    baseDate: baseDate
                )
                let qualitySummary = SetQualitySummary.build(
                    repQualityEvents: repEvents,
                    cueEvents: cueEvents
                )
                let setSummary = ExerciseSetSummary(
                    exerciseType: exerciseType,
                    setIndex: globalSetIndex,
                    target: .reps(repQualityEventsPerSet),
                    achievedReps: repQualityEventsPerSet,
                    achievedHoldSeconds: exerciseType.isIsometric ? 90 : 0,
                    averageFormScore: qualitySummary.averageFormScore,
                    cueEvents: cueEvents,
                    restExtended: globalSetIndex.isMultiple(of: 3),
                    skipped: globalSetIndex.isMultiple(of: 11),
                    qualitySummary: qualitySummary,
                    repQualityEvents: repEvents,
                    completionSource: .targetMet,
                    completedAt: baseDate.addingTimeInterval(TimeInterval(globalSetIndex * 180 + 120)),
                    durationSeconds: 120,
                    peakEffort: min(0.98, 0.52 + Double(globalSetIndex % 10) * 0.04),
                    bestCue: "Depth, tempo, and breathing stayed controlled through the cleanest reps.",
                    worstCue: "Late-set fatigue showed up as rib flare, knee drift, and shorter range."
                )

                setDocuments.append(
                    SetDocument(
                        id: "exercise-\(exerciseIndex)-set-\(setNumber)",
                        workoutId: uuid(9_000),
                        exerciseIndex: exerciseIndex,
                        setIndex: globalSetIndex,
                        createdAt: baseDate.addingTimeInterval(TimeInterval(globalSetIndex)),
                        summary: setSummary
                    )
                )

                return setSummary
            }
        }

        let allRepEvents = sets.flatMap(\.repQualityEvents)
        let allCueEvents = sets.flatMap(\.cueEvents)
        let averageFormScore = average(allRepEvents.compactMap(\.formScore).map(Double.init))
        let summary = WorkoutSessionSummary(
            id: uuid(9_000),
            accountId: "audit-user-for-firestore-shape",
            summarySchemaVersion: WorkoutSessionSummary.currentSchemaVersion,
            appBuildVersion: "audit-build-2026.05.08",
            mode: .plannedWorkout,
            planId: uuid(8_000),
            planTitle: "Firestore Shape Audit Plan",
            title: "Firestore Shape Audit Plan",
            goal: "Stress-test derived workout evidence before Firebase exists.",
            coach: .good,
            startedAt: baseDate,
            endedAt: baseDate.addingTimeInterval(42 * 60),
            serverEndedAt: baseDate.addingTimeInterval(42 * 60 + 1),
            durationSeconds: 42 * 60,
            totalReps: allRepEvents.count,
            totalHoldSeconds: sets.reduce(0) { $0 + $1.achievedHoldSeconds },
            averageFormScore: averageFormScore,
            completionPercent: 1,
            exerciseSummaries: sets,
            topCue: allCueEvents.first,
            effortSummary: "Peak effort hit 96%. Synthetic audit filled optional derived evidence.",
            workoutOutcome: .completed,
            structuredEffortSummary: StructuredEffortSummary.build(
                repQualityEvents: allRepEvents,
                peakEffort: 0.96
            ),
            createdAt: baseDate.addingTimeInterval(42 * 60 + 2),
            deletedAt: baseDate.addingTimeInterval(42 * 60 + 3),
            syncMetadata: SyncMetadata(
                localUpdatedAt: baseDate.addingTimeInterval(42 * 60 + 4),
                lastSyncedAt: baseDate.addingTimeInterval(42 * 60 + 5),
                serverVersion: "audit-server-version-token-with-extra-length",
                syncState: .pendingUpload,
                pendingOperationId: uuid(7_000)
            )
        )

        return AuditFixture(
            summary: summary,
            compactWorkoutDocument: CompactWorkoutDocument(summary: summary),
            setDocuments: setDocuments
        )
    }

    static func makeRepQualityEvents(
        exerciseType: ExerciseType,
        setIndex: Int,
        baseDate: Date
    ) -> [RepQualityEvent] {
        var events: [RepQualityEvent] = []
        events.reserveCapacity(repQualityEventsPerSet)

        for repIndex in 1...repQualityEventsPerSet {
            let score = max(52, 97 - ((repIndex + setIndex) % 23))
            let cueMessage = """
            Audit cue near rep \(repIndex): keep ribs stacked, knees tracking, \
            controlled tempo, and full range under fatigue.
            """
            events.append(RepQualityEvent(
                id: uuid(100_000 + setIndex * 100 + repIndex),
                exerciseType: exerciseType,
                setIndex: setIndex,
                repIndex: repIndex,
                timestamp: baseDate.addingTimeInterval(TimeInterval(setIndex * 180 + repIndex * 4)),
                secondsIntoSet: TimeInterval(repIndex * 4),
                formScore: score,
                formGrade: FormScore.Grade.from(score: score).rawValue,
                phase: repIndex.isMultiple(of: 2) ? RepPhase.down.rawValue : RepPhase.up.rawValue,
                cueMessageNearRep: cueMessage,
                cueSeverityNearRep: severity(for: repIndex),
                effortAtRep: min(0.99, 0.35 + Double(repIndex) * 0.02)
            ))
        }

        return events
    }

    static func makeCueEvents(
        exerciseType: ExerciseType,
        setIndex: Int,
        baseDate: Date
    ) -> [CueEvent] {
        var events: [CueEvent] = []
        events.reserveCapacity(cueEventsPerSet)

        for cueIndex in 1...cueEventsPerSet {
            let cueMessage = """
            Audit cue \(cueIndex): derived coaching event with metric context, \
            set timing, rep reference, and form score evidence.
            """
            let repIndex = min(repQualityEventsPerSet, max(1, cueIndex * 2))
            let metricKey = "audit.metric.\(exerciseType.rawValue).set\(setIndex).cue\(cueIndex)"
            events.append(CueEvent(
                id: uuid(200_000 + setIndex * 100 + cueIndex),
                timestamp: baseDate.addingTimeInterval(TimeInterval(setIndex * 180 + cueIndex * 11)),
                exerciseType: exerciseType,
                cueMessage: cueMessage,
                severity: severity(for: cueIndex + setIndex),
                setIndex: setIndex,
                repIndex: repIndex,
                secondsIntoSet: TimeInterval(cueIndex * 11),
                formScoreAtEvent: max(45, 94 - cueIndex - (setIndex % 8)),
                metricKey: metricKey,
                metricValue: Double(setIndex * 10 + cueIndex) + 0.42
            ))
        }

        return events
    }

    static func severity(for value: Int) -> CoachCue.Severity {
        if value.isMultiple(of: 5) { return .critical }
        if value.isMultiple(of: 2) { return .warning }
        return .info
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func historyJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func firestoreEstimate(forJSONBytes jsonBytes: Int) -> Int {
        Int((Double(jsonBytes) * firestoreOverheadMultiplier).rounded(.up)) + firestoreFixedOverheadBytes
    }

    static func documentedCompactWorkoutEstimate() throws -> Int {
        let contents = try String(
            contentsOf: repositoryRootURL().appendingPathComponent("Documentation/FirestoreShape.md")
        )
        let prefix = "compactWorkoutDocumentEstimatedFirestoreBytes: "
        guard let range = contents.range(of: prefix) else {
            XCTFail("FirestoreShape.md is missing compact workout estimate.")
            return 0
        }
        let suffix = contents[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }

    static func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
    }
}
