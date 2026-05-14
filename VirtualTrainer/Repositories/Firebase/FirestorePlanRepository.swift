import Foundation

@MainActor
final class FirestorePlanRepository: PlanRepository {
    private let database: any FirestoreDocumentDatabase

    init(database: any FirestoreDocumentDatabase) {
        self.database = database
    }

    @discardableResult
    func saveActivePlan(_ plan: WorkoutPlanV2, accountId: String, operationId: UUID) async throws -> WorkoutPlanV2 {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let planPath = try FirestorePathBuilder.plan(uid: uid, planId: plan.id)
        let activeDocuments = try await activePlanDocuments(uid: uid, limit: nil)

        if activeDocuments.contains(where: { document in
            guard let planDocument = try? FirestoreRepositorySupport.decode(
                FirestorePlanDocument.self,
                from: document
            ) else { return false }
            return planDocument.operationId == operationId
        }) {
            return try await loadActivePlan(accountId: uid) ?? plan
        }

        _ = try await database.runTransaction { transaction in
            for activeDocument in activeDocuments {
                guard activeDocument.path != planPath,
                      try transaction.getDocument(path: activeDocument.path) != nil else {
                    continue
                }
                let inactivePayload: [String: Any] = ["active": false]
                try FirestorePrivacyValidator.validate(inactivePayload)
                try transaction.updateData(inactivePayload, path: activeDocument.path)
            }

            if let current = try transaction.getDocument(path: planPath),
               let currentDocument = try? FirestoreRepositorySupport.decode(
                FirestorePlanDocument.self,
                from: current
               ),
               currentDocument.operationId == operationId {
                return nil
            }

            let now = Date()
            let document = mapToPlanDocument(
                plan,
                accountId: uid,
                active: true,
                savedAt: now,
                operationId: operationId
            )
            let payload = try FirestoreEncodingHelpers.payload(from: document)
            try transaction.setData(payload, path: planPath, merge: true)
            return nil
        }

        return try await loadActivePlan(accountId: uid) ?? plan
    }

    func loadActivePlan(accountId: String) async throws -> WorkoutPlanV2? {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        return try await activePlanDocuments(uid: uid, limit: 1)
            .compactMap { try? FirestoreRepositorySupport.decode(FirestorePlanDocument.self, from: $0) }
            .filter { $0.deletedAt == nil && $0.active }
            .map(mapFromPlanDocument)
            .first
    }

    func loadPlanHistory(accountId: String, limit: Int) async throws -> [WorkoutPlanV2] {
        let uid = try FirestoreRepositorySupport.requiredAccountId(accountId)
        let collectionPath = try FirestorePathBuilder.plansCollection(uid: uid)
        return try await database.queryDocuments(
            collectionPath: collectionPath,
            filters: [],
            orderBy: "savedAt",
            descending: true,
            limit: max(limit, 0)
        )
        .compactMap { try? FirestoreRepositorySupport.decode(FirestorePlanDocument.self, from: $0) }
        .filter { $0.deletedAt == nil }
        .map(mapFromPlanDocument)
    }

    private func activePlanDocuments(uid: String, limit: Int?) async throws -> [FirestoreStoredDocument] {
        let collectionPath = try FirestorePathBuilder.plansCollection(uid: uid)
        return try await database.queryDocuments(
            collectionPath: collectionPath,
            filters: [FirestoreQueryFilter(field: "active", value: true)],
            orderBy: "savedAt",
            descending: true,
            limit: limit
        )
    }
}
