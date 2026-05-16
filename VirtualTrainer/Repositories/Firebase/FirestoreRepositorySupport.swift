import Foundation

nonisolated enum FirestoreRepositorySupport {
    static let observerDebounceNanoseconds: UInt64 = 250_000_000

    static func requiredAccountId(_ accountId: String) throws -> String {
        guard let normalized = AccountOwnership.normalizedAccountId(accountId) else {
            throw RepositoryError.accountMissing
        }
        return normalized
    }

    static func serverVersion(
        from storedDocument: FirestoreStoredDocument?,
        serverDate: Date?,
        fallbackDate: Date = Date()
    ) -> String {
        if let updateVersionString = storedDocument?.updateVersionString {
            return updateVersionString
        }
        if let serverDate {
            return FirestoreVersionStrings.string(from: serverDate)
        }
        return FirestoreVersionStrings.string(from: fallbackDate)
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        from storedDocument: FirestoreStoredDocument
    ) throws -> T {
        try FirestoreEncodingHelpers.decode(type, from: storedDocument.data)
    }

    static func operationMatches(_ pendingOperationId: UUID?, _ operationId: UUID) -> Bool {
        pendingOperationId == operationId
    }
}

nonisolated final class FirestoreObserverDebouncer: @unchecked Sendable {
    private let lock = NSLock()
    private var scheduledTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    func schedule(
        after nanoseconds: UInt64,
        operation: @escaping @MainActor () -> Void
    ) {
        lock.lock()
        generation &+= 1
        let scheduledGeneration = generation
        let previousTask = scheduledTask
        let nextTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled,
                  self.isCurrentGeneration(scheduledGeneration) else {
                return
            }
            operation()
            self.clearTaskIfCurrentGeneration(scheduledGeneration)
        }
        scheduledTask = nextTask
        lock.unlock()

        previousTask?.cancel()
    }

    func cancel() {
        lock.lock()
        generation &+= 1
        let task = scheduledTask
        scheduledTask = nil
        lock.unlock()

        task?.cancel()
    }

    private func isCurrentGeneration(_ candidate: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == candidate
    }

    private func clearTaskIfCurrentGeneration(_ candidate: UInt64) {
        lock.lock()
        if generation == candidate {
            scheduledTask = nil
        }
        lock.unlock()
    }
}
