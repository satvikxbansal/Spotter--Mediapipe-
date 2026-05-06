import Foundation

nonisolated struct UserStats: Equatable {
    let totalWorkouts: Int
    let totalPlannedWorkouts: Int
    let totalFreeAnalysisSessions: Int
    let totalReps: Int
    let totalHoldSeconds: Int
    let totalGoodFormReps: Int
    let totalExcellentFormReps: Int
    let currentStreak: Int
    let longestStreak: Int
    let averageFormScore: Double?
    let totalDurationSeconds: Int
    let workoutsThisWeek: Int
    let xp: Int
    let level: Int
    let trophiesEarned: Int
    let lastWorkoutAt: Date?

    var xpIntoCurrentLevel: Int {
        xp - StatsEngine.xpRequired(forLevel: level)
    }

    var xpNeededForNextLevel: Int {
        StatsEngine.xpRequired(forLevel: level + 1) - StatsEngine.xpRequired(forLevel: level)
    }

    var levelProgressFraction: Double {
        guard xpNeededForNextLevel > 0 else { return 0 }
        return min(max(Double(xpIntoCurrentLevel) / Double(xpNeededForNextLevel), 0), 1)
    }
}

nonisolated struct StatsEngine {
    static let xpPerLevel = 500

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func makeStats(
        history: [WorkoutSessionSummary],
        trophySnapshot: TrophyProgressSnapshot,
        now: Date = Date()
    ) -> UserStats {
        let totalPlannedWorkouts = history.filter { $0.mode == .plannedWorkout }.count
        let totalFreeAnalysisSessions = history.filter { $0.mode == .freeAnalysis }.count
        let totalReps = history.reduce(0) { $0 + $1.totalReps }
        let totalHoldSeconds = history.reduce(0) { $0 + $1.totalHoldSeconds }
        let totalGoodFormReps = history.reduce(0) { $0 + $1.totalGoodFormReps }
        let totalExcellentFormReps = history.reduce(0) { $0 + $1.totalExcellentFormReps }
        let totalDurationSeconds = history.reduce(0) { $0 + $1.durationSeconds }
        let formScores = history.compactMap(\.averageFormScore)
        let workoutDays = Set(history.map { calendar.startOfDay(for: $0.endedAt) })
        let currentStreak = currentStreakDays(from: workoutDays, now: now)
        let longestStreak = longestStreakDays(from: workoutDays)
        let trophiesEarned = trophySnapshot.availableProgress.filter(\.earned).count
        let xp = xp(
            history: history,
            totalReps: totalReps,
            totalHoldSeconds: totalHoldSeconds,
            totalGoodFormReps: totalGoodFormReps,
            totalExcellentFormReps: totalExcellentFormReps,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            trophiesEarned: trophiesEarned
        )

        return UserStats(
            totalWorkouts: history.count,
            totalPlannedWorkouts: totalPlannedWorkouts,
            totalFreeAnalysisSessions: totalFreeAnalysisSessions,
            totalReps: totalReps,
            totalHoldSeconds: totalHoldSeconds,
            totalGoodFormReps: totalGoodFormReps,
            totalExcellentFormReps: totalExcellentFormReps,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            averageFormScore: average(formScores),
            totalDurationSeconds: totalDurationSeconds,
            workoutsThisWeek: workoutsThisWeek(in: history, now: now),
            xp: xp,
            level: Self.level(forXP: xp),
            trophiesEarned: trophiesEarned,
            lastWorkoutAt: history.map(\.endedAt).max()
        )
    }

    static func level(forXP xp: Int) -> Int {
        max(1, max(xp, 0) / xpPerLevel + 1)
    }

    static func xpRequired(forLevel level: Int) -> Int {
        max(level - 1, 0) * xpPerLevel
    }

    // XP rules:
    // - Completed planned workout: 100 XP.
    // - Partial planned workout: 50 XP.
    // - Saved free-analysis session: 40 XP.
    // - Volume: 1 XP per rep, plus 1 XP per 10 hold seconds.
    // - Form: 1 XP per good-form rep, plus 2 extra XP per excellent-form rep.
    // - High session score: 25 XP for each session averaging 90%+ form.
    // - Streaks: 25 XP per current-streak day, plus 10 XP per longest-streak day.
    // - Trophies: 50 XP per earned, currently supported trophy.
    private func xp(
        history: [WorkoutSessionSummary],
        totalReps: Int,
        totalHoldSeconds: Int,
        totalGoodFormReps: Int,
        totalExcellentFormReps: Int,
        currentStreak: Int,
        longestStreak: Int,
        trophiesEarned: Int
    ) -> Int {
        let sessionXP = history.reduce(0) { total, summary in
            switch summary.mode {
            case .freeAnalysis:
                return total + 40
            case .plannedWorkout:
                switch summary.workoutOutcome {
                case .completed:
                    return total + 100
                case .partial:
                    return total + 50
                case .cancelled, .freeAnalysisSaved:
                    return total
                }
            }
        }
        let holdXP = totalHoldSeconds / 10
        let highScoreBonus = history.filter { ($0.averageFormScore ?? 0) >= 90 }.count * 25
        let streakXP = currentStreak * 25 + longestStreak * 10
        let trophyXP = trophiesEarned * 50

        return sessionXP
            + totalReps
            + holdXP
            + totalGoodFormReps
            + totalExcellentFormReps * 2
            + highScoreBonus
            + streakXP
            + trophyXP
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func currentStreakDays(from workoutDays: Set<Date>, now: Date) -> Int {
        guard !workoutDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var cursor = workoutDays.contains(today) ? today : yesterday
        var streak = 0

        while workoutDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }

        return streak
    }

    private func longestStreakDays(from workoutDays: Set<Date>) -> Int {
        let sortedDays = workoutDays.sorted()
        guard !sortedDays.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for index in sortedDays.indices.dropFirst() {
            let previous = sortedDays[sortedDays.index(before: index)]
            let day = sortedDays[index]
            let expectedNext = calendar.date(byAdding: .day, value: 1, to: previous)
            if expectedNext == day {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
        }

        return longest
    }

    private func workoutsThisWeek(in history: [WorkoutSessionSummary], now: Date) -> Int {
        let currentWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
        return history.filter { summary in
            let workoutWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: summary.endedAt)
            return workoutWeek.weekOfYear == currentWeek.weekOfYear &&
                workoutWeek.yearForWeekOfYear == currentWeek.yearForWeekOfYear
        }.count
    }
}

nonisolated enum ProfileHistorySelection {
    static func detailSummary(
        for summaryID: UUID,
        in summaries: [WorkoutSessionSummary]
    ) -> WorkoutSessionSummary? {
        summaries.first { $0.id == summaryID }
    }
}
