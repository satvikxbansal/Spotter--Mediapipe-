import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import XCTest
@testable import VirtualTrainer

@MainActor
final class BackendIntegrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_100_000)

    override func setUp() async throws {
        try await super.setUp()
        try requireEmulatorOptIn()
        try configureFirebaseForEmulators()
        try? Auth.auth().signOut()
    }

    func testAnonymousSignInAndProfileRoundTrip() async throws {
        let accountId = try await FirebaseAuthRepository().signInAnonymously()
        let repository = FirestoreProfileRepository(database: FirebaseFirestoreDocumentDatabase())
        let operationId = fixedUUID(17_201)
        let profile = makeProfile(accountId: accountId, operationId: operationId)

        let saved = try await repository.saveProfile(profile, operationId: operationId)
        let loaded = try await repository.loadProfile(accountId: accountId)

        XCTAssertEqual(saved.accountId, accountId)
        XCTAssertEqual(loaded?.id, profile.id)
        XCTAssertEqual(loaded?.primaryGoal, profile.primaryGoal)
        XCTAssertEqual(loaded?.equipment, profile.equipment)
    }

    func testMultiSetWorkoutSaveLoadRecentOrderAndDetail() async throws {
        let accountId = try await FirebaseAuthRepository().signInAnonymously()
        let repository = FirestoreWorkoutRepository(database: FirebaseFirestoreDocumentDatabase())
        let older = makeWorkoutSummary(
            accountId: accountId,
            id: fixedUUID(17_211),
            endedAt: now.addingTimeInterval(-3_600),
            setCount: 4,
            operationId: fixedUUID(17_212)
        )
        let newer = makeWorkoutSummary(
            accountId: accountId,
            id: fixedUUID(17_213),
            endedAt: now,
            setCount: 4,
            operationId: fixedUUID(17_214)
        )

        _ = try await repository.saveWorkoutSummary(older, operationId: fixedUUID(17_212))
        _ = try await repository.saveWorkoutSummary(newer, operationId: fixedUUID(17_214))

        let recent = try await repository.loadRecentWorkouts(accountId: accountId, limit: 2, since: nil)
        let detail = try await repository.loadWorkout(accountId: accountId, id: newer.id)

        XCTAssertEqual(recent.map(\.id), [newer.id, older.id])
        XCTAssertEqual(detail?.exerciseSummaries.count, 4)
        XCTAssertEqual(detail?.exerciseSummaries.compactMap(\.setIndex), [0, 1, 2, 3])
    }

    func testForbiddenWriteIsDeniedByRules() async throws {
        _ = try await FirebaseAuthRepository().signInAnonymously()

        do {
            try await setFirestoreDocument(
                path: "users/not-the-current-user/profile/current",
                data: [
                    "accountId": "not-the-current-user",
                    "updatedAt": Timestamp(date: now)
                ]
            )
            XCTFail("Expected Firestore rules to deny writing another user's profile.")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, FirestoreErrorDomain)
            XCTAssertEqual(nsError.code, FirestoreErrorCode.permissionDenied.rawValue)
        }
    }

    func testWorkoutTombstonePropagationHidesDeletedWorkout() async throws {
        let accountId = try await FirebaseAuthRepository().signInAnonymously()
        let repository = FirestoreWorkoutRepository(database: FirebaseFirestoreDocumentDatabase())
        let workout = makeWorkoutSummary(
            accountId: accountId,
            id: fixedUUID(17_221),
            endedAt: now,
            setCount: 4,
            operationId: fixedUUID(17_222)
        )

        _ = try await repository.saveWorkoutSummary(workout, operationId: fixedUUID(17_222))
        try await repository.deleteWorkout(
            accountId: accountId,
            id: workout.id,
            operationId: fixedUUID(17_223)
        )

        let active = try await repository.loadRecentWorkouts(accountId: accountId, limit: 10, since: nil)
        let tombstones = try await repository.loadRecentWorkoutTombstones(accountId: accountId, limit: 10, since: nil)

        XCTAssertFalse(active.contains { $0.id == workout.id })
        XCTAssertTrue(tombstones.contains { $0.id == workout.id && $0.isDeleted })
    }
}

private extension BackendIntegrationTests {
    func requireEmulatorOptIn() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SPOTTER_RUN_BACKEND_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("BackendIntegrationTests require SPOTTER_RUN_BACKEND_INTEGRATION_TESTS=1.")
        }
        guard FirebaseEmulatorBootstrap.isRequested(arguments: ProcessInfo.processInfo.arguments) else {
            throw XCTSkip("BackendIntegrationTests require --firebase-emulator or SPOTTER_FIREBASE_EMULATOR=1.")
        }
    }

    func configureFirebaseForEmulators() throws {
        if FirebaseApp.app() == nil {
            let options = FirebaseOptions(
                googleAppID: "1:123456789:ios:backendintegration",
                gcmSenderID: "123456789"
            )
            options.projectID = "spotter-local"
            options.apiKey = "emulator-local-key"
            FirebaseApp.configure(options: options)
        }
        FirebaseEmulatorBootstrap.configure()
    }

    func setFirestoreDocument(path: String, data: [String: Any]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Firestore.firestore().document(path).setData(data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func makeProfile(accountId: String, operationId: UUID) -> UserProfile {
        UserProfile(
            id: fixedUUID(17_230),
            accountId: accountId,
            displayName: "Emulator Tester",
            genderIdentity: .preferNotToSay,
            age: 33,
            height: 173,
            heightUnit: .metric,
            weight: 72,
            weightUnit: .metric,
            primaryGoal: .strength,
            fitnessLevel: .beginner,
            equipment: [.bodyweight, .mat],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            preferredSessionLength: .twentyFive,
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now,
            syncMetadata: .initialPendingUpload(operationId: operationId, now: now)
        )
    }

    func makeWorkoutSummary(
        accountId: String,
        id: UUID,
        endedAt: Date,
        setCount: Int,
        operationId: UUID
    ) -> WorkoutSessionSummary {
        let sets = (0..<setCount).map { setIndex in
            ExerciseSetSummary(
                exerciseType: setIndex.isMultiple(of: 2) ? .squat : .pushup,
                setIndex: setIndex,
                target: .reps(10),
                achievedReps: 10,
                achievedHoldSeconds: 0,
                averageFormScore: 86,
                completionSource: .targetMet,
                completedAt: endedAt.addingTimeInterval(Double(setIndex * 60)),
                durationSeconds: 45,
                peakEffort: 0.75
            )
        }
        return WorkoutSessionSummary(
            id: id,
            accountId: accountId,
            mode: .plannedWorkout,
            planId: fixedUUID(17_240),
            planTitle: "Emulator Plan",
            title: "Emulator Plan",
            goal: "Exercise emulator sync.",
            coach: .good,
            startedAt: endedAt.addingTimeInterval(-1_500),
            endedAt: endedAt,
            serverEndedAt: endedAt,
            durationSeconds: 1_500,
            totalReps: sets.reduce(0) { $0 + $1.achievedReps },
            totalHoldSeconds: 0,
            averageFormScore: 86,
            completionPercent: 1,
            exerciseSummaries: sets,
            topCue: nil,
            effortSummary: "Emulator integration workout.",
            createdAt: endedAt,
            syncMetadata: .initialPendingUpload(operationId: operationId, now: endedAt)
        )
    }

    func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value)) ?? UUID()
    }
}
