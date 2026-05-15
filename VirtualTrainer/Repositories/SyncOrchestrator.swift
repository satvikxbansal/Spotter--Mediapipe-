import Combine
import Foundation

nonisolated enum SyncOrchestratorStatus: Equatable {
    case idle
    case syncing
    case failed
    case offline
    case conflict
}

@MainActor
final class SyncOrchestrator: ObservableObject {
    @Published private(set) var status: SyncOrchestratorStatus = .idle

    let backendMode: BackendMode
    private weak var workoutHistoryStore: WorkoutHistoryStore?
    private var workoutRepository: (any WorkoutRepository)?

    init(backendMode: BackendMode = .local) {
        self.backendMode = backendMode
    }

    convenience init(dependencies: AppDependencies) {
        self.init(backendMode: dependencies.backendMode)
    }

    func performFullSync() async throws {
        try await runLocalNoopSync()
    }

    func observeRemote() async throws {
        try ensureLocalMode()
        status = .idle
    }

    func enqueueDirtyWrites() async throws {
        try await runLocalNoopSync()
    }

    func configureWorkoutPush(
        localStore: WorkoutHistoryStore,
        workoutRepository: (any WorkoutRepository)?
    ) {
        workoutHistoryStore = localStore
        self.workoutRepository = workoutRepository
    }

#if DEBUG
    func pushPendingWorkouts() async throws {
        guard backendMode == .firebase else {
            try await runLocalNoopSync()
            return
        }
        guard let workoutHistoryStore,
              let workoutRepository else {
            status = .failed
            throw RepositoryError.backendUnavailable
        }

        status = .syncing
        let pendingSummaries = workoutHistoryStore
            .fetchDirtyOrDeletedSummaries()
            .filter { $0.syncMetadata.syncState == .pendingUpload }

        do {
            for summary in pendingSummaries {
                let operationId = summary.syncMetadata.pendingOperationId ?? UUID()
                if summary.isDeleted {
                    guard let accountId = summary.accountId else {
                        throw RepositoryError.accountMissing
                    }
                    try await workoutRepository.deleteWorkout(
                        accountId: accountId,
                        id: summary.id,
                        operationId: operationId
                    )
                    _ = await workoutHistoryStore.markSummarySynced(id: summary.id)
                } else {
                    let savedSummary = try await workoutRepository.saveWorkoutSummary(
                        summary,
                        operationId: operationId
                    )
                    _ = await workoutHistoryStore.applyRemoteWorkoutCache(savedSummary)
                }
            }
            status = .idle
        } catch {
            status = .failed
            throw error
        }
    }
#endif

    private func runLocalNoopSync() async throws {
        try ensureLocalMode()
        status = .syncing
        await Task.yield()
        status = .idle
    }

    private func ensureLocalMode() throws {
        guard backendMode == .local else {
            status = .failed
            throw RepositoryError.backendUnavailable
        }
    }
}
