import Foundation

nonisolated struct LabeledStat: Identifiable, Codable, Equatable {
    let label: String
    let value: String

    var id: String { label }
}

nonisolated struct WeeklyRecap: Identifiable, Codable, Equatable {
    let weekStart: Date
    let weekEnd: Date
    let headline: String
    let narrative: String
    let stats: [LabeledStat]
    let topMoment: String
    let biggestSurprise: String
    let nextWeekFocus: String
    let evidence: [InsightEvidence]
    let dedupeKey: String

    var id: String { dedupeKey }
}

nonisolated struct WeeklyRecapBuilder {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func build(
        history: [WorkoutSessionSummary],
        profile: UserProfile,
        trophies: TrophyProgressSnapshot,
        now: Date = Date()
    ) -> WeeklyRecap? {
        guard let targetWeek = targetWeekInterval(profile: profile, now: now) else {
            return nil
        }

        let localCalendar = calendar(for: profile)
        let weekSessions = history
            .filter { targetWeek.contains($0.endedAt) }
            .sorted { lhs, rhs in
                if lhs.endedAt == rhs.endedAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.endedAt < rhs.endedAt
            }
        let stats = stats(for: weekSessions, trophies: trophies, in: targetWeek)
        let weekEnd = localCalendar.date(byAdding: .second, value: -1, to: targetWeek.end) ?? targetWeek.end
        let evidence = evidence(for: weekSessions, in: targetWeek)
        let nextFocus = nextWeekFocus(
            for: profile.primaryGoal,
            sessions: weekSessions,
            hasOlderHistory: history.contains { $0.endedAt < targetWeek.start }
        )

        if weekSessions.isEmpty {
            let hasOlderHistory = history.contains { $0.endedAt < targetWeek.start }
            return WeeklyRecap(
                weekStart: targetWeek.start,
                weekEnd: weekEnd,
                headline: hasOlderHistory ? "This week became a recovery week" : "Your first recap is a rest reset",
                narrative: restNarrative(
                    hasOlderHistory: hasOlderHistory,
                    weekStart: targetWeek.start,
                    weekEnd: weekEnd,
                    calendar: localCalendar,
                    nextFocus: nextFocus
                ),
                stats: stats,
                topMoment: hasOlderHistory ? "No saved sessions, so recovery stayed the main signal." : "No saved sessions yet, which keeps the first baseline clean.",
                biggestSurprise: hasOlderHistory ? "A full rest week after previous training is still useful context." : "The useful signal is that Spotter should start conservatively, not guess from missing data.",
                nextWeekFocus: nextFocus,
                evidence: evidence,
                dedupeKey: dedupeKey(for: targetWeek.start, calendar: localCalendar)
            )
        }

        let avgForm = average(weekSessions.compactMap(\.averageFormScore))
        let totalReps = weekSessions.reduce(0) { $0 + $1.totalReps }
        let totalHoldSeconds = weekSessions.reduce(0) { $0 + $1.totalHoldSeconds }
        let bestSession = weekSessions.max {
            ($0.averageFormScore ?? -1) < ($1.averageFormScore ?? -1)
        }
        let topMoment = topMoment(
            sessions: weekSessions,
            trophies: trophies,
            targetWeek: targetWeek
        )
        let surprise = biggestSurprise(
            sessions: weekSessions,
            averageForm: avgForm,
            totalReps: totalReps,
            totalHoldSeconds: totalHoldSeconds
        )

        return WeeklyRecap(
            weekStart: targetWeek.start,
            weekEnd: weekEnd,
            headline: headline(for: weekSessions, bestSession: bestSession),
            narrative: normalNarrative(
                sessions: weekSessions,
                averageForm: avgForm,
                totalReps: totalReps,
                totalHoldSeconds: totalHoldSeconds,
                weekStart: targetWeek.start,
                weekEnd: weekEnd,
                calendar: localCalendar,
                nextFocus: nextFocus
            ),
            stats: stats,
            topMoment: topMoment,
            biggestSurprise: surprise,
            nextWeekFocus: nextFocus,
            evidence: evidence,
            dedupeKey: dedupeKey(for: targetWeek.start, calendar: localCalendar)
        )
    }
}

nonisolated private extension WeeklyRecapBuilder {
    struct WeekInterval {
        let start: Date
        let end: Date

        func contains(_ date: Date) -> Bool {
            date >= start && date < end
        }
    }

    func targetWeekInterval(
        profile: UserProfile,
        now: Date
    ) -> WeekInterval? {
        let localCalendar = calendar(for: profile)
        let components = localCalendar.dateComponents([.weekday, .hour], from: now)
        let weekday = components.weekday
        let hour = components.hour ?? 0

        let referenceDate: Date?
        if weekday == 1, hour >= 18 {
            referenceDate = now
        } else if weekday == 2, hour < 12 {
            referenceDate = localCalendar.date(byAdding: .day, value: -1, to: now)
        } else {
            referenceDate = nil
        }

        guard let referenceDate else { return nil }
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = localCalendar.timeZone
        guard let interval = isoCalendar.dateInterval(of: .weekOfYear, for: referenceDate) else {
            return nil
        }
        return WeekInterval(start: interval.start, end: interval.end)
    }

    func calendar(for profile: UserProfile) -> Calendar {
        var resolved = calendar
        if let timeZone = TimeZone(identifier: profile.timezoneIdentifier) {
            resolved.timeZone = timeZone
        }
        return resolved
    }

    func stats(
        for sessions: [WorkoutSessionSummary],
        trophies: TrophyProgressSnapshot,
        in week: WeekInterval
    ) -> [LabeledStat] {
        [
            LabeledStat(label: "Sessions", value: "\(sessions.count)"),
            LabeledStat(label: "Avg form", value: averageFormText(sessions.compactMap(\.averageFormScore))),
            LabeledStat(label: "Total reps", value: "\(sessions.reduce(0) { $0 + $1.totalReps })"),
            LabeledStat(label: "Hold", value: durationText(sessions.reduce(0) { $0 + $1.totalHoldSeconds })),
            LabeledStat(label: "Trophies", value: "\(trophiesEarned(in: trophies, week: week))")
        ]
    }

    func evidence(
        for sessions: [WorkoutSessionSummary],
        in week: WeekInterval
    ) -> [InsightEvidence] {
        guard !sessions.isEmpty else {
            return [
                InsightEvidence(
                    metric: "weeklyRest",
                    value: "0 sessions",
                    comparison: "No saved workouts in this ISO week",
                    confidence: 0.72
                )
            ]
        }

        return Array(sessions.prefix(3)).map { summary in
            InsightEvidence(
                metric: "weeklySession",
                value: summary.title,
                comparison: summary.averageFormScore.map { "Avg form \(Int($0.rounded()))%" },
                workoutId: summary.id,
                exerciseType: summary.primaryExerciseType,
                confidence: summary.averageFormScore == nil ? 0.72 : 0.9
            )
        }
    }

    func headline(
        for sessions: [WorkoutSessionSummary],
        bestSession: WorkoutSessionSummary?
    ) -> String {
        if let bestSession,
           let form = bestSession.averageFormScore,
           form >= 90 {
            return "Your week peaked with clean form"
        }
        if sessions.count >= 3 {
            return "Your week built real consistency"
        }
        return "Your week has a clear training signal"
    }

    func normalNarrative(
        sessions: [WorkoutSessionSummary],
        averageForm: Double?,
        totalReps: Int,
        totalHoldSeconds: Int,
        weekStart: Date,
        weekEnd: Date,
        calendar: Calendar,
        nextFocus: String
    ) -> String {
        let formText = averageForm.map { "average form was \(Int($0.rounded()))%" } ?? "form scoring was limited"
        let holdText = totalHoldSeconds > 0 ? " and \(durationText(totalHoldSeconds)) of holds" : ""
        return "From \(shortDate(weekStart, calendar: calendar)) to \(shortDate(weekEnd, calendar: calendar)), you saved \(sessions.count) session\(sessions.count == 1 ? "" : "s"). Across the week, \(formText), with \(totalReps) reps\(holdText). \(nextFocus)"
    }

    func restNarrative(
        hasOlderHistory: Bool,
        weekStart: Date,
        weekEnd: Date,
        calendar: Calendar,
        nextFocus: String
    ) -> String {
        let dateText = "\(shortDate(weekStart, calendar: calendar)) to \(shortDate(weekEnd, calendar: calendar))"
        if hasOlderHistory {
            return "\(dateText) became a rest week with no saved sessions. That still matters: Spotter should treat the next workout as a re-entry, not a place to force missed volume. \(nextFocus)"
        }
        return "\(dateText) had no saved sessions yet. That is not a failure; it just means the first useful baseline should stay small, clean, and repeatable. \(nextFocus)"
    }

    func topMoment(
        sessions: [WorkoutSessionSummary],
        trophies: TrophyProgressSnapshot,
        targetWeek: WeekInterval
    ) -> String {
        if let event = trophies.newlyEarnedEvents.first(where: { targetWeek.contains($0.earnedAt) }) {
            return "Trophy earned: \(event.title)."
        }
        if let best = sessions.max(by: { ($0.averageFormScore ?? -1) < ($1.averageFormScore ?? -1) }),
           let form = best.averageFormScore {
            return "\(best.title) led quality at \(Int(form.rounded()))% average form."
        }
        if let highestVolume = sessions.max(by: { $0.totalReps < $1.totalReps }) {
            return "\(highestVolume.title) carried the week with \(highestVolume.totalReps) reps."
        }
        return "The week was logged without a standout scored moment."
    }

    func biggestSurprise(
        sessions: [WorkoutSessionSummary],
        averageForm: Double?,
        totalReps: Int,
        totalHoldSeconds: Int
    ) -> String {
        if let averageForm, averageForm >= 88 {
            return "Quality stayed higher than the volume alone would suggest."
        }
        if totalHoldSeconds > 0 && totalReps == 0 {
            return "Hold work carried the week more than rep volume."
        }
        if sessions.contains(where: { ($0.completionPercent ?? 1) < 0.75 }) {
            return "Partial sessions still created usable coaching evidence."
        }
        return totalReps > 0 ? "The clearest signal came from repeatable reps, not just session count." : "The clearest signal was recovery space."
    }

    func nextWeekFocus(
        for goal: FitnessGoal,
        sessions: [WorkoutSessionSummary],
        hasOlderHistory: Bool
    ) -> String {
        if sessions.isEmpty {
            return hasOlderHistory
                ? "Next week, restart with the easiest first target and let form decide the second set."
                : "Next week, start with one short session so Spotter can build the first baseline."
        }

        switch goal {
        case .strength:
            return "Next week, repeat the cleanest movement first, then add only the smallest rep or hold bump."
        case .performance:
            return "Next week, keep one quality benchmark and one stamina block; stop the increase if form fades."
        case .longevity:
            return "Next week, protect consistency with short sessions and add mobility if recovery feels flat."
        }
    }

    func trophiesEarned(
        in trophies: TrophyProgressSnapshot,
        week: WeekInterval
    ) -> Int {
        trophies.availableProgress.filter { progress in
            guard let earnedAt = progress.earnedAt else { return false }
            return week.contains(earnedAt)
        }.count
    }

    func averageFormText(_ scores: [Double]) -> String {
        guard let average = average(scores) else { return "N/A" }
        return "\(Int(average.rounded()))%"
    }

    func durationText(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(max(seconds, 0))s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func shortDate(
        _ date: Date,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    func dedupeKey(
        for weekStart: Date,
        calendar: Calendar
    ) -> String {
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = calendar.timeZone
        let components = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return "weekly-recap|\(year)-W\(String(format: "%02d", week))"
    }

    func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
