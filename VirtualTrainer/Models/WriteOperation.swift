import Foundation

nonisolated enum WriteEntityKind: String, Codable {
    case profile
    case workout
    case trophyEvent
    case insight
    case insightDelivery
    case insightEngagement
    case calibration
    case theme
    case plan
}

nonisolated struct WriteOperation<Payload: Codable & Equatable>: Codable, Equatable {
    let operationId: UUID
    let entityKind: WriteEntityKind
    let payload: Payload
    let createdAt: Date
}
