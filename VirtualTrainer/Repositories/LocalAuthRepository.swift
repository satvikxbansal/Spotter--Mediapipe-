import Foundation

private struct LocalAuthSnapshot: Codable, Equatable {
    let schemaVersion: Int
    var stableAccountId: String?
    var currentAccountId: String?
    var updatedAt: Date

    init(
        schemaVersion: Int = 1,
        stableAccountId: String?,
        currentAccountId: String?,
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.stableAccountId = AccountOwnership.normalizedAccountId(stableAccountId)
        self.currentAccountId = AccountOwnership.normalizedAccountId(currentAccountId)
        self.updatedAt = updatedAt
    }
}

@MainActor
final class LocalAuthRepository: AuthRepository {
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let persistenceActor: PersistenceActor
    private var snapshot: LocalAuthSnapshot
    private var authContinuations: [UUID: AsyncStream<String?>.Continuation] = [:]
    private var loadError: String?

    var currentAccountId: String? {
        snapshot.currentAccountId
    }

    init(
        fileURL: URL? = nil,
        persistenceActor: PersistenceActor = .shared
    ) {
        self.fileURL = fileURL ?? Self.defaultAuthURL()
        self.persistenceActor = persistenceActor
        self.snapshot = LocalAuthSnapshot(stableAccountId: nil, currentAccountId: nil)
        decoder.dateDecodingStrategy = .iso8601
        loadSnapshot()
    }

    nonisolated deinit {}

    func signInAnonymously() async throws -> String {
        if let loadError {
            throw RepositoryError.invalidPayload(loadError)
        }

        let stableAccountId = snapshot.stableAccountId ?? Self.makeLocalAccountId()
        snapshot.stableAccountId = stableAccountId
        snapshot.currentAccountId = stableAccountId
        snapshot.updatedAt = Date()
        try await persistSnapshot()
        notifyAuthObservers()
        return stableAccountId
    }

    func linkAnonymousAccountWithApple(idToken: String, nonce: String) async throws -> String {
        // Local mode intentionally has no identity-provider link step. Firebase
        // or another backend can implement Apple linking behind this protocol later.
        throw RepositoryError.backendUnavailable
    }

    func signOut() async throws {
        snapshot.currentAccountId = nil
        snapshot.updatedAt = Date()
        try await persistSnapshot()
        notifyAuthObservers()
    }

    func deleteAccount() async throws {
        snapshot = LocalAuthSnapshot(stableAccountId: nil, currentAccountId: nil)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try await persistenceActor.removeAfterQueuedWrites(at: fileURL)
        }
        notifyAuthObservers()
    }

    func observeAuthChanges() async throws -> AsyncStream<String?> {
        AsyncStream { continuation in
            let id = UUID()
            authContinuations[id] = continuation
            continuation.yield(snapshot.currentAccountId)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.authContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func loadSnapshot() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            snapshot = LocalAuthSnapshot(stableAccountId: nil, currentAccountId: nil)
            loadError = nil
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            snapshot = try decoder.decode(LocalAuthSnapshot.self, from: data)
            loadError = nil
        } catch {
            snapshot = LocalAuthSnapshot(stableAccountId: nil, currentAccountId: nil)
            loadError = "Could not load local auth state: \(error.localizedDescription)"
        }
    }

    private func persistSnapshot() async throws {
        let data = try await persistenceActor.encode(
            snapshot,
            outputFormatting: [.prettyPrinted, .sortedKeys]
        )
        _ = try await persistenceActor.writeLatest(data, to: fileURL, options: [.atomic])
    }

    private func notifyAuthObservers() {
        authContinuations.values.forEach {
            $0.yield(snapshot.currentAccountId)
        }
    }

    private static func makeLocalAccountId() -> String {
        "local-\(UUID().uuidString.lowercased())"
    }

    private static func defaultAuthURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Spotter", isDirectory: true)
            .appendingPathComponent("LocalAuth.json")
    }
}
