import Foundation

nonisolated enum RepositoryError: Error, Equatable {
    case notFound
    case conflict(serverVersion: String?, localVersion: String?)
    case unauthorized
    case network(String)
    case invalidPayload(String)
    case accountMissing
    case backendUnavailable
}
