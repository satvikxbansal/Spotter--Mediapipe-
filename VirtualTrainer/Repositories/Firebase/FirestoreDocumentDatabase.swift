import FirebaseCore
import FirebaseFirestore
import Foundation

nonisolated struct FirestoreStoredDocument {
    let path: String
    let data: [String: Any]
    let updateTime: Date?

    var updateVersionString: String? {
        updateTime.map(FirestoreVersionStrings.string)
    }
}

nonisolated struct FirestoreQueryFilter {
    let field: String
    let value: Any
}

nonisolated protocol FirestoreListenerHandle: AnyObject {
    func remove()
}

nonisolated protocol FirestoreRepositoryTransaction: AnyObject {
    func getDocument(path: String) throws -> FirestoreStoredDocument?
    func setData(_ data: [String: Any], path: String, merge: Bool) throws
    func updateData(_ data: [String: Any], path: String) throws
}

nonisolated protocol FirestoreRepositoryBatch: AnyObject {
    func setData(_ data: [String: Any], path: String, merge: Bool) throws
    func updateData(_ data: [String: Any], path: String) throws
}

@MainActor
protocol FirestoreDocumentDatabase: AnyObject {
    func getDocument(path: String) async throws -> FirestoreStoredDocument?
    func queryDocuments(
        collectionPath: String,
        filters: [FirestoreQueryFilter],
        orderBy: String?,
        descending: Bool,
        limit: Int?
    ) async throws -> [FirestoreStoredDocument]
    func runTransaction(
        _ update: @escaping (FirestoreRepositoryTransaction) throws -> Any?
    ) async throws -> Any?
    func commitBatch(
        _ update: @escaping (FirestoreRepositoryBatch) throws -> Void
    ) async throws
    func listenDocument(
        path: String,
        onChange: @escaping (Result<FirestoreStoredDocument?, Error>) -> Void
    ) -> FirestoreListenerHandle
    func listenQuery(
        collectionPath: String,
        filters: [FirestoreQueryFilter],
        orderBy: String?,
        descending: Bool,
        limit: Int?,
        onChange: @escaping (Result<[FirestoreStoredDocument], Error>) -> Void
    ) -> FirestoreListenerHandle
}

@MainActor
final class FirebaseFirestoreDocumentDatabase: FirestoreDocumentDatabase {
    private let injectedFirestore: Firestore?

    init(firestore: Firestore? = nil) {
        self.injectedFirestore = firestore
    }

    func getDocument(path: String) async throws -> FirestoreStoredDocument? {
        let snapshot = try await documentSnapshot(path: path)
        return storedDocument(from: snapshot, path: path)
    }

    func queryDocuments(
        collectionPath: String,
        filters: [FirestoreQueryFilter],
        orderBy: String?,
        descending: Bool,
        limit: Int?
    ) async throws -> [FirestoreStoredDocument] {
        let query = try resolvedQuery(
            collectionPath: collectionPath,
            filters: filters,
            orderBy: orderBy,
            descending: descending,
            limit: limit
        )

        let snapshot: QuerySnapshot = try await withCheckedThrowingContinuation { continuation in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: RepositoryError.backendUnavailable)
                }
            }
        }

        return snapshot.documents.compactMap { document in
            storedDocument(from: document, path: document.reference.path)
        }
    }

    func runTransaction(
        _ update: @escaping (FirestoreRepositoryTransaction) throws -> Any?
    ) async throws -> Any? {
        let firestore = try resolvedFirestore()
        return try await firestore.runTransaction { [firestore] transaction, errorPointer in
            do {
                let adapter = FirebaseFirestoreTransactionAdapter(
                    transaction: transaction,
                    firestore: firestore
                )
                return try update(adapter)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    func commitBatch(
        _ update: @escaping (FirestoreRepositoryBatch) throws -> Void
    ) async throws {
        let firestore = try resolvedFirestore()
        let batch = firestore.batch()
        let adapter = FirebaseFirestoreBatchAdapter(batch: batch, firestore: firestore)
        try update(adapter)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            batch.commit { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func listenDocument(
        path: String,
        onChange: @escaping (Result<FirestoreStoredDocument?, Error>) -> Void
    ) -> FirestoreListenerHandle {
        let firestore: Firestore
        do {
            firestore = try resolvedFirestore()
        } catch {
            onChange(.failure(error))
            return FirebaseFirestoreNoopListenerHandle()
        }
        let registration = firestore.document(path).addSnapshotListener { snapshot, error in
            if let error {
                onChange(.failure(error))
                return
            }
            guard let snapshot else {
                onChange(.success(nil))
                return
            }
            onChange(.success(storedDocument(from: snapshot, path: path)))
        }
        return FirebaseFirestoreListenerHandle(registration: registration)
    }

    func listenQuery(
        collectionPath: String,
        filters: [FirestoreQueryFilter],
        orderBy: String?,
        descending: Bool,
        limit: Int?,
        onChange: @escaping (Result<[FirestoreStoredDocument], Error>) -> Void
    ) -> FirestoreListenerHandle {
        let query: Query
        do {
            query = try resolvedQuery(
                collectionPath: collectionPath,
                filters: filters,
                orderBy: orderBy,
                descending: descending,
                limit: limit
            )
        } catch {
            onChange(.failure(error))
            return FirebaseFirestoreNoopListenerHandle()
        }

        let registration = query.addSnapshotListener { snapshot, error in
            if let error {
                onChange(.failure(error))
                return
            }
            guard let snapshot else {
                onChange(.success([]))
                return
            }
            onChange(
                .success(
                    snapshot.documents.compactMap { document in
                        storedDocument(from: document, path: document.reference.path)
                    }
                )
            )
        }
        return FirebaseFirestoreListenerHandle(registration: registration)
    }

    private func documentSnapshot(path: String) async throws -> DocumentSnapshot {
        let firestore = try resolvedFirestore()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DocumentSnapshot, Error>) in
            firestore.document(path).getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: RepositoryError.backendUnavailable)
                }
            }
        }
    }

    private func resolvedFirestore() throws -> Firestore {
        if let injectedFirestore {
            return injectedFirestore
        }
        guard FirebaseApp.app() != nil else {
            throw RepositoryError.backendUnavailable
        }
        return Firestore.firestore()
    }

    private func resolvedQuery(
        collectionPath: String,
        filters: [FirestoreQueryFilter],
        orderBy: String?,
        descending: Bool,
        limit: Int?
    ) throws -> Query {
        let firestore = try resolvedFirestore()
        var query: Query = firestore.collection(collectionPath)
        for filter in filters {
            query = query.whereField(filter.field, isEqualTo: filter.value)
        }
        if let orderBy {
            query = query.order(by: orderBy, descending: descending)
        }
        if let limit {
            query = query.limit(to: limit)
        }
        return query
    }
}

private final class FirebaseFirestoreTransactionAdapter: FirestoreRepositoryTransaction {
    private let transaction: Transaction
    private let firestore: Firestore

    init(transaction: Transaction, firestore: Firestore) {
        self.transaction = transaction
        self.firestore = firestore
    }

    func getDocument(path: String) throws -> FirestoreStoredDocument? {
        let snapshot = try transaction.getDocument(firestore.document(path))
        return storedDocument(from: snapshot, path: path)
    }

    func setData(_ data: [String: Any], path: String, merge: Bool) throws {
        transaction.setData(data, forDocument: firestore.document(path), merge: merge)
    }

    func updateData(_ data: [String: Any], path: String) throws {
        transaction.updateData(data, forDocument: firestore.document(path))
    }
}

private final class FirebaseFirestoreBatchAdapter: FirestoreRepositoryBatch {
    private let batch: WriteBatch
    private let firestore: Firestore

    init(batch: WriteBatch, firestore: Firestore) {
        self.batch = batch
        self.firestore = firestore
    }

    func setData(_ data: [String: Any], path: String, merge: Bool) throws {
        batch.setData(data, forDocument: firestore.document(path), merge: merge)
    }

    func updateData(_ data: [String: Any], path: String) throws {
        batch.updateData(data, forDocument: firestore.document(path))
    }
}

private final class FirebaseFirestoreListenerHandle: FirestoreListenerHandle {
    private let registration: ListenerRegistration

    init(registration: ListenerRegistration) {
        self.registration = registration
    }

    func remove() {
        registration.remove()
    }
}

private final class FirebaseFirestoreNoopListenerHandle: FirestoreListenerHandle {
    func remove() {}
}

private func storedDocument(from snapshot: DocumentSnapshot, path: String) -> FirestoreStoredDocument? {
    guard snapshot.exists,
          let data = snapshot.data(with: .estimate) else {
        return nil
    }

    // The classic iOS Firestore snapshot API used by this app does not expose
    // document updateTime, so repositories fall back to server timestamp fields
    // when building local serverVersion strings.
    return FirestoreStoredDocument(path: path, data: data, updateTime: nil)
}

nonisolated enum FirestoreVersionStrings {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
