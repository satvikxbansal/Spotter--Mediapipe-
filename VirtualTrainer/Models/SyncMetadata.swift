import Foundation

nonisolated enum SyncState: String, Codable {
    case localOnly
    case pendingUpload
    case synced
    case conflict
}

nonisolated struct SyncMetadata: Codable, Equatable {
    var localUpdatedAt: Date
    var lastSyncedAt: Date?
    var serverVersion: String?
    var syncState: SyncState
    var pendingOperationId: UUID?

    static func initialLocalOnly(now: Date = Date()) -> SyncMetadata {
        SyncMetadata(
            localUpdatedAt: now,
            lastSyncedAt: nil,
            serverVersion: nil,
            syncState: .localOnly,
            pendingOperationId: nil
        )
    }

    static func initialPendingUpload(operationId: UUID?, now: Date = Date()) -> SyncMetadata {
        SyncMetadata(
            localUpdatedAt: now,
            lastSyncedAt: nil,
            serverVersion: nil,
            syncState: .pendingUpload,
            pendingOperationId: operationId
        )
    }

    func markedForLocalMutation(
        accountId: String?,
        operationId: UUID? = nil,
        now: Date = Date()
    ) -> SyncMetadata {
        var copy = self
        copy.markLocalMutation(accountId: accountId, operationId: operationId, now: now)
        return copy
    }

    mutating func markLocalMutation(
        accountId: String?,
        operationId: UUID? = nil,
        now: Date = Date()
    ) {
        localUpdatedAt = now

        guard syncState != .conflict else { return }

        if AccountOwnership.normalizedAccountId(accountId) != nil {
            syncState = .pendingUpload
            if let operationId {
                pendingOperationId = operationId
            }
        } else {
            syncState = .localOnly
            pendingOperationId = nil
        }
    }

    static func preferredForMerge(_ lhs: SyncMetadata, _ rhs: SyncMetadata) -> SyncMetadata {
        if lhs.syncState == .conflict { return lhs }
        if rhs.syncState == .conflict { return rhs }
        if lhs.syncState == .pendingUpload && rhs.syncState != .pendingUpload { return lhs }
        if rhs.syncState == .pendingUpload && lhs.syncState != .pendingUpload { return rhs }
        return lhs.localUpdatedAt >= rhs.localUpdatedAt ? lhs : rhs
    }

    func markedSynced(
        lastSyncedAt: Date = Date(),
        serverVersion: String? = nil
    ) -> SyncMetadata {
        var copy = self
        copy.lastSyncedAt = lastSyncedAt
        copy.serverVersion = serverVersion ?? copy.serverVersion
        copy.syncState = .synced
        copy.pendingOperationId = nil
        return copy
    }

    func markedConflict(serverVersion: String?, localVersion _: String?) -> SyncMetadata {
        var copy = self
        copy.serverVersion = serverVersion ?? copy.serverVersion
        copy.syncState = .conflict
        copy.pendingOperationId = nil
        return copy
    }
}
