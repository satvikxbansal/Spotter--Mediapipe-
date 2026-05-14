import XCTest
@testable import VirtualTrainer

@MainActor
final class AccountClaimCoordinatorTests: XCTestCase {
    func testMockAuthSignInUpdatesAccountContextAndClaimsEachStoreOnce() async throws {
        let authRepository = MockAuthRepository(signInUID: "firebase-user-123")
        let accountContext = AccountContext()
        let claimingStores = makeMockStores()
        let writeJournal = LocalWriteJournal(fileURL: temporaryURL(named: "LocalWriteJournal.json"))
        let coordinator = AccountClaimCoordinator(
            accountContext: accountContext,
            stores: AccountAwareStores(stores: claimingStores),
            writeJournal: writeJournal
        )
        let operationId = fixedUUID("1601")
        let claimExpectation = expectation(description: "all stores claimed local data")
        claimExpectation.expectedFulfillmentCount = claimingStores.count
        claimingStores.forEach { store in
            store.onClaim = { claimExpectation.fulfill() }
        }

        let authChanges = try await authRepository.observeAuthChanges()
        let listener = Task { @MainActor in
            for await uid in authChanges {
                await coordinator.handleAuthChange(uid, operationId: operationId)
            }
        }

        let uid = try await authRepository.signInAnonymously()
        await fulfillment(of: [claimExpectation], timeout: 2)
        listener.cancel()

        XCTAssertEqual(uid, "firebase-user-123")
        XCTAssertEqual(accountContext.currentAccountId, "firebase-user-123")
        XCTAssertEqual(claimingStores.map(\.claimCount), Array(repeating: 1, count: 6))
        XCTAssertEqual(claimingStores.flatMap(\.claimedAccountIds), Array(repeating: "firebase-user-123", count: 6))
        XCTAssertTrue(claimingStores.allSatisfy { $0.currentAccountId == "firebase-user-123" })
    }

    func testMockAuthSignOutDoesNotDeleteLocalFile() async throws {
        let fileURL = temporaryURL(named: "UserProfile.json")
        let originalData = Data(#"{"displayName":"Local Athlete"}"#.utf8)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try originalData.write(to: fileURL, options: [.atomic])

        let authRepository = MockAuthRepository(signInUID: "firebase-user-456")
        let accountContext = AccountContext()
        let claimingStores = makeMockStores()
        let coordinator = AccountClaimCoordinator(
            accountContext: accountContext,
            stores: AccountAwareStores(stores: claimingStores),
            writeJournal: LocalWriteJournal(fileURL: temporaryURL(named: "LocalWriteJournal.json"))
        )
        let claimExpectation = expectation(description: "sign-in claim completed")
        claimExpectation.expectedFulfillmentCount = claimingStores.count
        let signOutExpectation = expectation(description: "sign-out reached stores")
        signOutExpectation.expectedFulfillmentCount = claimingStores.count
        claimingStores.forEach { store in
            store.onClaim = { claimExpectation.fulfill() }
        }

        let authChanges = try await authRepository.observeAuthChanges()
        let listener = Task { @MainActor in
            for await uid in authChanges {
                await coordinator.handleAuthChange(uid)
            }
        }

        _ = try await authRepository.signInAnonymously()
        await fulfillment(of: [claimExpectation], timeout: 2)
        claimingStores.forEach { store in
            store.onSetAccount = { accountId in
                if accountId == nil {
                    signOutExpectation.fulfill()
                }
            }
        }
        try await authRepository.signOut()
        await fulfillment(of: [signOutExpectation], timeout: 2)
        listener.cancel()

        XCTAssertNil(accountContext.currentAccountId)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
    }

    func testAccountClaimJournalRecordsProfileAndRetriedOperationIsNoop() async throws {
        let accountContext = AccountContext()
        let claimingStores = makeMockStores()
        let writeJournal = LocalWriteJournal(fileURL: temporaryURL(named: "LocalWriteJournal.json"))
        let coordinator = AccountClaimCoordinator(
            accountContext: accountContext,
            stores: AccountAwareStores(stores: claimingStores),
            writeJournal: writeJournal
        )
        let operationId = fixedUUID("1602")

        let firstClaim = await coordinator.claimLocalData(
            forAccountId: "firebase-user-789",
            operationId: operationId
        )
        let retriedClaim = await coordinator.claimLocalData(
            forAccountId: "firebase-user-789",
            operationId: operationId
        )

        let journalEntries = await writeJournal.snapshot()

        XCTAssertTrue(firstClaim)
        XCTAssertTrue(retriedClaim)
        XCTAssertEqual(claimingStores.map(\.claimCount), Array(repeating: 1, count: 6))
        XCTAssertEqual(journalEntries.count, 1)
        XCTAssertEqual(journalEntries.first?.operationId, operationId)
        XCTAssertEqual(journalEntries.first?.entityKind, .profile)
    }

    private func makeMockStores() -> [MockAccountClaimingStore] {
        (0..<6).map { _ in MockAccountClaimingStore() }
    }

    private func temporaryURL(named fileName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountClaimCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private func fixedUUID(_ suffix: String) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-00000000\(suffix)") ?? UUID()
    }
}

@MainActor
private final class MockAuthRepository: AuthRepository {
    private let signInUID: String
    private var currentUID: String?
    private var continuation: AsyncStream<String?>.Continuation?

    var currentAccountId: String? {
        currentUID
    }

    init(signInUID: String) {
        self.signInUID = signInUID
    }

    func signInAnonymously() async throws -> String {
        currentUID = signInUID
        continuation?.yield(currentUID)
        return signInUID
    }

    func linkAnonymousAccountWithApple(idToken: String, nonce: String) async throws -> String {
        throw RepositoryError.backendUnavailable
    }

    func signOut() async throws {
        currentUID = nil
        continuation?.yield(nil)
    }

    func deleteAccount() async throws {
        currentUID = nil
        continuation?.yield(nil)
    }

    func observeAuthChanges() async throws -> AsyncStream<String?> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(currentUID)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuation = nil
                }
            }
        }
    }
}

@MainActor
private final class MockAccountClaimingStore: AccountClaimingStore {
    private(set) var currentAccountId: String?
    private(set) var claimCount = 0
    private(set) var claimedAccountIds: [String] = []
    var onClaim: (() -> Void)?
    var onSetAccount: ((String?) -> Void)?

    func setCurrentAccountId(_ accountId: String?) {
        currentAccountId = AccountOwnership.normalizedAccountId(accountId)
        onSetAccount?(currentAccountId)
    }

    func claimLocalDataForAccount(id accountId: String, operationId: UUID?) async -> Bool {
        guard let normalizedAccountId = AccountOwnership.normalizedAccountId(accountId) else {
            return false
        }

        claimCount += 1
        claimedAccountIds.append(normalizedAccountId)
        onClaim?()
        return true
    }
}
