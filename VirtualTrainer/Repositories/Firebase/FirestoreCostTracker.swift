import Combine
import Foundation

nonisolated struct FirestoreCostSnapshot: Equatable {
    var reads: Int
    var writes: Int
    var startedAt: Date
    var lastUpdatedAt: Date?

    static func empty(startedAt: Date = Date()) -> FirestoreCostSnapshot {
        FirestoreCostSnapshot(reads: 0, writes: 0, startedAt: startedAt, lastUpdatedAt: nil)
    }
}

@MainActor
final class FirestoreCostTracker: ObservableObject {
    static let shared = FirestoreCostTracker()

    @Published private(set) var snapshot = FirestoreCostSnapshot.empty()
    @Published var isEnabled = false {
        didSet {
#if DEBUG
            guard oldValue != isEnabled else { return }
            if isEnabled {
                reset()
                logSnapshot(reason: "enabled")
            } else {
                logSnapshot(reason: "disabled")
            }
#endif
        }
    }

    func reset(now: Date = Date()) {
#if DEBUG
        snapshot = .empty(startedAt: now)
        logSnapshot(reason: "reset")
#else
        _ = now
#endif
    }

    func recordReads(_ count: Int, reason: String) {
#if DEBUG
        guard count > 0 else { return }
        snapshot.reads += count
        snapshot.lastUpdatedAt = Date()
        logSnapshot(reason: reason)
#else
        _ = count
        _ = reason
#endif
    }

    func recordWrites(_ count: Int, reason: String) {
#if DEBUG
        guard count > 0 else { return }
        snapshot.writes += count
        snapshot.lastUpdatedAt = Date()
        logSnapshot(reason: reason)
#else
        _ = count
        _ = reason
#endif
    }

    private func logSnapshot(reason: String) {
#if DEBUG
        guard isEnabled else { return }
        print(
            "Spotter Firestore Cost Snapshot reads=\(snapshot.reads) writes=\(snapshot.writes) reason=\(reason)"
        )
#endif
    }
}
