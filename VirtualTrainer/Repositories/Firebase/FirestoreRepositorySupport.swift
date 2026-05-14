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
