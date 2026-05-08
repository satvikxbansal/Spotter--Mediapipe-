import Foundation

nonisolated protocol AppClock: Sendable {
    func now() -> Date
    func estimatedServerNow() -> Date
}

nonisolated struct LocalClock: AppClock {
    func now() -> Date { Date() }
    func estimatedServerNow() -> Date { Date() }
}
