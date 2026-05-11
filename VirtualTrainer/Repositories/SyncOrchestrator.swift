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
