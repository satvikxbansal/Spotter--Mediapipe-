import Foundation

nonisolated struct TrendWindowPolicy: Equatable {
    let maxSessions: Int?
    let maxDays: Int?

    init(maxSessions: Int? = nil, maxDays: Int? = nil) {
        self.maxSessions = maxSessions.map { max($0, 0) }
        self.maxDays = maxDays.map { max($0, 0) }
    }

    static let recentCues = TrendWindowPolicy(maxSessions: 7)
    static let recentSetup = TrendWindowPolicy(maxDays: 14)
    static let recentExerciseFriction = TrendWindowPolicy(maxSessions: 5)

    func filteredSessions(
        _ history: [WorkoutSessionSummary],
        now: Date
    ) -> [WorkoutSessionSummary] {
        let sortedHistory = history.sorted {
            if $0.authoritativeEndedAt == $1.authoritativeEndedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.authoritativeEndedAt > $1.authoritativeEndedAt
        }
        let eligibleHistory = sortedHistory.filter { contains($0.authoritativeEndedAt, now: now) }
        return maxSessions.map { Array(eligibleHistory.prefix($0)) } ?? eligibleHistory
    }

    func contains(_ date: Date, now: Date) -> Bool {
        guard date <= now else { return false }
        guard let maxDays else { return true }
        guard let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -maxDays, to: now) else {
            return true
        }
        return date >= cutoff
    }
}
