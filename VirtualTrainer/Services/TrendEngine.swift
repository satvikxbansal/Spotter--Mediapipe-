import Foundation

nonisolated struct TrendEngine {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func buildSnapshot(
        history: [WorkoutSessionSummary],
        profile: UserProfile,
        trophies: TrophyProgressSnapshot,
        now: Date = Date()
    ) -> UserTrainingTrendSnapshot {
        let localCalendar = calendar(for: profile)
        let sortedHistory = sorted(history)
        let exerciseTrends = buildExerciseTrends(from: sortedHistory)
        let workoutCountThisWeek = workoutsThisWeek(in: sortedHistory, calendar: localCalendar, now: now)
        let weeklyUniqueDays = uniqueWorkoutDaysThisWeek(in: sortedHistory, calendar: localCalendar, now: now)
        let formComparison = comparison(
            history: sortedHistory,
            window: .threeWorkout,
            metric: .formScore
        )
        let volumeComparison = comparison(
            history: sortedHistory,
            window: .threeWorkout,
            metric: .volumeUnits
        )
        let fatigueComparison = effortComparison(history: sortedHistory, window: .threeWorkout)

        return UserTrainingTrendSnapshot(
            generatedAt: now,
            totalWorkouts: sortedHistory.count,
            currentStreak: currentStreak(history: sortedHistory, profile: profile, now: now),
            workoutsThisWeek: workoutCountThisWeek,
            workoutDaysThisWeek: weeklyUniqueDays,
            weeklyConsistencyStatus: weeklyConsistencyStatus(
                historyCount: sortedHistory.count,
                activeDaysThisWeek: weeklyUniqueDays,
                targetDays: profile.workoutDaysPerWeek
            ),
            overallFormTrend: trendDirection(
                delta: formComparison.delta,
                meaningfulThreshold: 5,
                positive: .improving,
                negative: .declining
            ),
            volumeTrend: trendDirection(
                delta: volumeComparison.delta,
                meaningfulThreshold: 8,
                positive: .increasing,
                negative: .decreasing
            ),
            fatigueTrend: fatigueTrend(from: fatigueComparison, history: sortedHistory),
            strongestExercise: strongestExercise(from: exerciseTrends),
            improvingExercise: improvingExercise(from: exerciseTrends),
            strugglingExercise: strugglingExercise(from: exerciseTrends),
            mostRepeatedCue: mostRepeatedCue(in: sortedHistory),
            trophyNearMisses: trophyNearMisses(from: trophies),
            cameraFrictionCount: cameraFrictionCount(in: sortedHistory),
            exerciseTrends: exerciseTrends
        )
    }

    func dailyWorkoutCounts(
        history: [WorkoutSessionSummary],
        profile: UserProfile? = nil
    ) -> [Date: Int] {
        let localCalendar = calendar(for: profile)
        return history.reduce(into: [Date: Int]()) { result, summary in
            result[localCalendar.startOfDay(for: summary.endedAt), default: 0] += 1
        }
    }

    func dailyTotalReps(
        history: [WorkoutSessionSummary],
        profile: UserProfile? = nil
    ) -> [Date: Int] {
        let localCalendar = calendar(for: profile)
        return history.reduce(into: [Date: Int]()) { result, summary in
            result[localCalendar.startOfDay(for: summary.endedAt), default: 0] += summary.totalReps
        }
    }

    func dailyHoldSeconds(
        history: [WorkoutSessionSummary],
        profile: UserProfile? = nil
    ) -> [Date: Int] {
        let localCalendar = calendar(for: profile)
        return history.reduce(into: [Date: Int]()) { result, summary in
            result[localCalendar.startOfDay(for: summary.endedAt), default: 0] += summary.totalHoldSeconds
        }
    }

    func dailyAverageForm(
        history: [WorkoutSessionSummary],
        profile: UserProfile? = nil
    ) -> [Date: Double] {
        let localCalendar = calendar(for: profile)
        let grouped = history.reduce(into: [Date: [Double]]()) { result, summary in
            guard let averageFormScore = summary.averageFormScore else { return }
            result[localCalendar.startOfDay(for: summary.endedAt), default: []].append(averageFormScore)
        }

        return grouped.mapValues { values in
            values.reduce(0, +) / Double(values.count)
        }
    }

    func dailyDuration(
        history: [WorkoutSessionSummary],
        profile: UserProfile? = nil
    ) -> [Date: Int] {
        let localCalendar = calendar(for: profile)
        return history.reduce(into: [Date: Int]()) { result, summary in
            result[localCalendar.startOfDay(for: summary.endedAt), default: 0] += summary.durationSeconds
        }
    }

    func currentStreak(
        history: [WorkoutSessionSummary],
        profile: UserProfile? = nil,
        now: Date = Date()
    ) -> Int {
        let localCalendar = calendar(for: profile)
        return currentStreakDays(
            from: uniqueWorkoutDays(in: history, calendar: localCalendar),
            calendar: localCalendar,
            now: now
        )
    }

    func longestStreak(
        history: [WorkoutSessionSummary],
        profile: UserProfile? = nil
    ) -> Int {
        let localCalendar = calendar(for: profile)
        return longestStreakDays(
            from: uniqueWorkoutDays(in: history, calendar: localCalendar),
            calendar: localCalendar
        )
    }

    func threeWorkoutComparison(
        history: [WorkoutSessionSummary],
        metric: TrendMetric = .volumeUnits
    ) -> TrendComparisonSummary {
        comparison(history: sorted(history), window: .threeWorkout, metric: metric)
    }

    func sevenWorkoutComparison(
        history: [WorkoutSessionSummary],
        metric: TrendMetric = .formScore
    ) -> TrendComparisonSummary {
        comparison(history: sorted(history), window: .sevenWorkout, metric: metric)
    }

    func averageForm(
        history: [WorkoutSessionSummary],
        window: TrendWindow,
        profile: UserProfile? = nil,
        now: Date = Date()
    ) -> Double? {
        let localCalendar = calendar(for: profile)
        let windowHistory: [WorkoutSessionSummary]
        switch window {
        case .latestWorkout:
            windowHistory = Array(sorted(history).prefix(1))
        case .threeWorkout:
            windowHistory = Array(sorted(history).prefix(3))
        case .sevenWorkout:
            windowHistory = Array(sorted(history).prefix(7))
        case .currentWeek:
            let currentWeek = localCalendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
            windowHistory = history.filter { summary in
                let workoutWeek = localCalendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: summary.endedAt)
                return workoutWeek.weekOfYear == currentWeek.weekOfYear &&
                    workoutWeek.yearForWeekOfYear == currentWeek.yearForWeekOfYear
            }
        case .currentMonth:
            guard let month = localCalendar.dateInterval(of: .month, for: now) else { return nil }
            windowHistory = history.filter { month.contains($0.endedAt) }
        }

        return average(windowHistory.compactMap(\.averageFormScore))
    }

    func monthSnapshot(
        history: [WorkoutSessionSummary],
        profile: UserProfile,
        now: Date = Date()
    ) -> WorkoutCalendarSnapshot {
        let localCalendar = calendar(for: profile)
        guard let month = localCalendar.dateInterval(of: .month, for: now) else {
            return WorkoutCalendarSnapshot(
                days: [],
                currentMonth: localCalendar.startOfDay(for: now),
                completedDays: [],
                streak: currentStreak(history: history, profile: profile, now: now),
                timeZoneIdentifier: localCalendar.timeZone.identifier
            )
        }

        let monthStart = localCalendar.startOfDay(for: month.start)
        let gridStart = localCalendar.dateInterval(of: .weekOfYear, for: monthStart)?.start ?? monthStart
        let counts = dailyWorkoutCounts(history: history, profile: profile)
        let reps = dailyTotalReps(history: history, profile: profile)
        let holds = dailyHoldSeconds(history: history, profile: profile)
        let form = dailyAverageForm(history: history, profile: profile)
        let completedDays = counts.keys
            .filter { day in
                day >= month.start && day < month.end && (counts[day] ?? 0) > 0
            }
            .sorted()

        let days = (0..<42).compactMap { offset -> WorkoutCalendarDay? in
            guard let date = localCalendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            let day = localCalendar.startOfDay(for: date)
            return WorkoutCalendarDay(
                date: day,
                isInCurrentMonth: day >= month.start && day < month.end,
                workoutCount: counts[day] ?? 0,
                totalReps: reps[day] ?? 0,
                totalHoldSeconds: holds[day] ?? 0,
                averageFormScore: form[day]
            )
        }

        return WorkoutCalendarSnapshot(
            days: days,
            currentMonth: monthStart,
            completedDays: completedDays,
            streak: currentStreak(history: history, profile: profile, now: now),
            timeZoneIdentifier: localCalendar.timeZone.identifier
        )
    }
}

nonisolated extension TrendEngine {
    static func isCameraFrictionCue(_ cue: String) -> Bool {
        let normalized = cue.lowercased()
        return [
            "camera",
            "visible",
            "visibility",
            "frame",
            "step back",
            "move back",
            "move closer",
            "too close",
            "too far",
            "full body",
            "body visible",
            "can see"
        ].contains { normalized.contains($0) }
    }
}

nonisolated private extension TrendEngine {
    struct ExerciseObservation {
        let summaryId: UUID
        let endedAt: Date
        let exerciseType: ExerciseType
        let reps: Int
        let holdSeconds: Int
        let averageFormScore: Double?
        let bestFormScore: Double?
        let cueMessages: [String]
        let highSeverityCueCount: Int
        let breakdownRepIndex: Int?
        let improvementRepIndex: Int?
        let goodFormReps: Int
        let excellentFormReps: Int
        let formDroppedOff: Bool
        let skipped: Bool
        let restExtended: Bool
        let cameraFrictionCueCount: Int
    }

    struct EffortComparison {
        let latestValue: Double?
        let comparisonValue: Double?
        let delta: Double?
    }

    func calendar(for profile: UserProfile?) -> Calendar {
        var resolved = calendar
        if let identifier = profile?.timezoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            resolved.timeZone = timeZone
        }
        return resolved
    }

    func sorted(_ history: [WorkoutSessionSummary]) -> [WorkoutSessionSummary] {
        history.sorted {
            if $0.endedAt == $1.endedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.endedAt > $1.endedAt
        }
    }

    func uniqueWorkoutDays(
        in history: [WorkoutSessionSummary],
        calendar: Calendar
    ) -> Set<Date> {
        Set(history.map { calendar.startOfDay(for: $0.endedAt) })
    }

    func currentStreakDays(
        from workoutDays: Set<Date>,
        calendar: Calendar,
        now: Date
    ) -> Int {
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

    func longestStreakDays(
        from workoutDays: Set<Date>,
        calendar: Calendar
    ) -> Int {
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

    func workoutsThisWeek(
        in history: [WorkoutSessionSummary],
        calendar: Calendar,
        now: Date
    ) -> Int {
        let currentWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
        return history.filter { summary in
            let workoutWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: summary.endedAt)
            return workoutWeek.weekOfYear == currentWeek.weekOfYear &&
                workoutWeek.yearForWeekOfYear == currentWeek.yearForWeekOfYear
        }.count
    }

    func uniqueWorkoutDaysThisWeek(
        in history: [WorkoutSessionSummary],
        calendar: Calendar,
        now: Date
    ) -> Int {
        let currentWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
        let days = history.reduce(into: Set<Date>()) { result, summary in
            let workoutWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: summary.endedAt)
            guard workoutWeek.weekOfYear == currentWeek.weekOfYear,
                  workoutWeek.yearForWeekOfYear == currentWeek.yearForWeekOfYear
            else { return }
            result.insert(calendar.startOfDay(for: summary.endedAt))
        }
        return days.count
    }

    func weeklyConsistencyStatus(
        historyCount: Int,
        activeDaysThisWeek: Int,
        targetDays: Int?
    ) -> WeeklyConsistencyStatus {
        guard historyCount > 0 else { return .noHistory }
        guard activeDaysThisWeek > 0 else { return .gettingStarted }
        let safeTarget = max(targetDays ?? UserProfile.defaultWorkoutDaysPerWeek, 1)
        if activeDaysThisWeek > safeTarget { return .aboveTarget }
        if activeDaysThisWeek == safeTarget { return .aligned }
        return .building
    }

    func comparison(
        history: [WorkoutSessionSummary],
        window: TrendWindow,
        metric: TrendMetric
    ) -> TrendComparisonSummary {
        let count: Int
        switch window {
        case .latestWorkout:
            count = 1
        case .threeWorkout:
            count = 3
        case .sevenWorkout:
            count = 7
        case .currentWeek, .currentMonth:
            return .unavailable(window: window, metric: metric)
        }

        guard history.count >= count * 2 else {
            return .unavailable(window: window, metric: metric)
        }

        let latest = Array(history.prefix(count))
        let previous = Array(history.dropFirst(count).prefix(count))
        let latestValue = metricValue(metric, in: latest)
        let previousValue = metricValue(metric, in: previous)
        let delta: Double?
        if let latestValue, let previousValue {
            delta = latestValue - previousValue
        } else {
            delta = nil
        }
        return TrendComparisonSummary(
            window: window,
            metric: metric,
            latestValue: latestValue,
            comparisonValue: previousValue,
            delta: delta
        )
    }

    func metricValue(
        _ metric: TrendMetric,
        in history: [WorkoutSessionSummary]
    ) -> Double? {
        guard !history.isEmpty else { return nil }
        switch metric {
        case .totalReps:
            return Double(history.reduce(0) { $0 + $1.totalReps })
        case .holdSeconds:
            return Double(history.reduce(0) { $0 + $1.totalHoldSeconds })
        case .formScore:
            return average(history.compactMap(\.averageFormScore))
        case .durationSeconds:
            return Double(history.reduce(0) { $0 + $1.durationSeconds })
        case .volumeUnits:
            let reps = history.reduce(0) { $0 + $1.totalReps }
            let holds = history.reduce(0) { $0 + $1.totalHoldSeconds }
            return Double(reps) + Double(holds) / 10
        }
    }

    func trendDirection(
        delta: Double?,
        meaningfulThreshold: Double,
        positive: TrainingTrendDirection,
        negative: TrainingTrendDirection
    ) -> TrainingTrendDirection {
        guard let delta else { return .unavailable }
        if delta >= meaningfulThreshold { return positive }
        if delta <= -meaningfulThreshold { return negative }
        return .steady
    }

    func effortComparison(
        history: [WorkoutSessionSummary],
        window: TrendWindow
    ) -> EffortComparison {
        let count: Int
        switch window {
        case .latestWorkout:
            count = 1
        case .threeWorkout:
            count = 3
        case .sevenWorkout:
            count = 7
        case .currentWeek, .currentMonth:
            return EffortComparison(latestValue: nil, comparisonValue: nil, delta: nil)
        }

        guard history.count >= count * 2 else {
            return EffortComparison(latestValue: nil, comparisonValue: nil, delta: nil)
        }

        let latest = averageEffort(in: Array(history.prefix(count)))
        let previous = averageEffort(in: Array(history.dropFirst(count).prefix(count)))
        let delta: Double?
        if let latest, let previous {
            delta = latest - previous
        } else {
            delta = nil
        }
        return EffortComparison(
            latestValue: latest,
            comparisonValue: previous,
            delta: delta
        )
    }

    func averageEffort(in history: [WorkoutSessionSummary]) -> Double? {
        let values = history.compactMap { summary in
            summary.structuredEffortSummary?.peakEffort
        }
        return average(values)
    }

    func fatigueTrend(
        from comparison: EffortComparison,
        history: [WorkoutSessionSummary]
    ) -> TrainingTrendDirection {
        let recentRestFriction = history.prefix(3)
            .flatMap(\.exerciseSummaries)
            .filter { $0.restExtended || ($0.qualitySummary?.qualityTrend == .faded) }
            .count

        if let latest = comparison.latestValue, latest >= 0.75, recentRestFriction >= 2 {
            return .elevated
        }

        guard let delta = comparison.delta else {
            return recentRestFriction >= 3 ? .elevated : .unavailable
        }

        if delta >= 0.08 { return .increasing }
        if delta <= -0.08 { return .decreasing }
        return .steady
    }

    func buildExerciseTrends(
        from history: [WorkoutSessionSummary]
    ) -> [ExerciseTrendSummary] {
        let observations = history.flatMap(exerciseObservations)
        let grouped = Dictionary(grouping: observations, by: \.exerciseType)

        return grouped.map { exerciseType, values in
            let sortedValues = values.sorted {
                if $0.endedAt == $1.endedAt {
                    return $0.summaryId.uuidString < $1.summaryId.uuidString
                }
                return $0.endedAt < $1.endedAt
            }
            let formScores = sortedValues.compactMap(\.averageFormScore)
            let cueCounts = cueCounts(from: sortedValues.flatMap(\.cueMessages))
            let recentDelta = recentFormDelta(in: sortedValues)
            let summaryIds = Set(sortedValues.map(\.summaryId))

            return ExerciseTrendSummary(
                exerciseType: exerciseType,
                sessions: summaryIds.count,
                totalReps: sortedValues.reduce(0) { $0 + $1.reps },
                totalHoldSeconds: sortedValues.reduce(0) { $0 + $1.holdSeconds },
                averageFormScore: average(formScores),
                bestFormScore: sortedValues.compactMap(\.bestFormScore).max(),
                recentFormDelta: recentDelta,
                mostCommonCue: cueCounts.first?.key,
                breakdownRepIndex: sortedValues.compactMap(\.breakdownRepIndex).min(),
                improvementRepIndex: sortedValues.compactMap(\.improvementRepIndex).min(),
                goodFormRepCount: sortedValues.reduce(0) { $0 + $1.goodFormReps },
                excellentFormRepCount: sortedValues.reduce(0) { $0 + $1.excellentFormReps },
                highSeverityCueCount: sortedValues.reduce(0) { $0 + $1.highSeverityCueCount },
                formDropOffSetCount: sortedValues.filter(\.formDroppedOff).count,
                skippedSetCount: sortedValues.filter(\.skipped).count,
                restExtendedSetCount: sortedValues.filter(\.restExtended).count,
                cameraFrictionCueCount: sortedValues.reduce(0) { $0 + $1.cameraFrictionCueCount }
            )
        }
        .sorted {
            if $0.sessions == $1.sessions {
                return $0.exerciseType.rawValue < $1.exerciseType.rawValue
            }
            return $0.sessions > $1.sessions
        }
    }

    func exerciseObservations(from summary: WorkoutSessionSummary) -> [ExerciseObservation] {
        summary.exerciseSummaries.map { setSummary in
            let repScores = setSummary.repQualityEvents.compactMap(\.formScore).map(Double.init)
            let quality = setSummary.qualitySummary
            let cueMessages = setSummary.cueEvents.map(\.cueMessage) +
                setSummary.repQualityEvents.compactMap(\.cueMessageNearRep)
            let highSeverityCueCount = quality?.highSeverityCueCount ?? highSeverityCueCount(in: setSummary)
            let bestFormScore = [quality?.maxFormScore, setSummary.averageFormScore, repScores.max()]
                .compactMap { $0 }
                .max()
            let averageFormScore = quality?.averageFormScore
                ?? setSummary.averageFormScore
                ?? average(repScores)
            let cameraCues = cueMessages.filter(Self.isCameraFrictionCue).count

            return ExerciseObservation(
                summaryId: summary.id,
                endedAt: summary.endedAt,
                exerciseType: setSummary.exerciseType,
                reps: setSummary.achievedReps,
                holdSeconds: setSummary.achievedHoldSeconds,
                averageFormScore: averageFormScore,
                bestFormScore: bestFormScore,
                cueMessages: cueMessages,
                highSeverityCueCount: highSeverityCueCount,
                breakdownRepIndex: quality?.breakdownRepIndex,
                improvementRepIndex: quality?.improvementRepIndex,
                goodFormReps: quality?.goodFormReps ?? setSummary.repQualityEvents.filter { ($0.formScore ?? -1) >= 80 }.count,
                excellentFormReps: quality?.excellentFormReps ?? setSummary.repQualityEvents.filter { ($0.formScore ?? -1) >= 90 }.count,
                formDroppedOff: quality?.qualityTrend == .faded,
                skipped: setSummary.skipped,
                restExtended: setSummary.restExtended,
                cameraFrictionCueCount: cameraCues
            )
        }
    }

    func highSeverityCueCount(in setSummary: ExerciseSetSummary) -> Int {
        let cueEvents = setSummary.cueEvents.filter { $0.severity >= .warning }.count
        let repEvents = setSummary.repQualityEvents.filter {
            guard let severity = $0.cueSeverityNearRep else { return false }
            return severity >= .warning
        }.count
        return cueEvents + repEvents
    }

    func recentFormDelta(in observations: [ExerciseObservation]) -> Double? {
        let scored = observations.filter { $0.averageFormScore != nil }
        guard scored.count >= 2 else { return nil }

        let sampleCount = min(3, max(scored.count / 2, 1))
        guard scored.count >= sampleCount * 2 else {
            guard let latest = scored.last?.averageFormScore,
                  let previous = scored.dropLast().last?.averageFormScore
            else { return nil }
            return latest - previous
        }

        let latest = scored.suffix(sampleCount).compactMap(\.averageFormScore)
        let previous = scored.dropLast(sampleCount).suffix(sampleCount).compactMap(\.averageFormScore)
        guard let latestAverage = average(latest),
              let previousAverage = average(previous)
        else { return nil }
        return latestAverage - previousAverage
    }

    func strongestExercise(from trends: [ExerciseTrendSummary]) -> ExerciseType? {
        trends
            .filter { $0.sessions > 0 && (($0.averageFormScore != nil) || $0.totalReps > 0 || $0.totalHoldSeconds > 0) }
            .max { lhs, rhs in
                let lhsScore = strengthScore(lhs)
                let rhsScore = strengthScore(rhs)
                if lhsScore == rhsScore {
                    return lhs.exerciseType.rawValue > rhs.exerciseType.rawValue
                }
                return lhsScore < rhsScore
            }?
            .exerciseType
    }

    func strengthScore(_ trend: ExerciseTrendSummary) -> Double {
        let form = trend.averageFormScore ?? 0
        let volume = min(Double(trend.totalReps) / 25, 8) + min(Double(trend.totalHoldSeconds) / 120, 8)
        let quality = Double(trend.goodFormRepCount) * 0.2 + Double(trend.excellentFormRepCount) * 0.35
        let friction = Double(trend.highSeverityCueCount + trend.formDropOffSetCount) * 1.5
        return form + volume + quality - friction
    }

    func improvingExercise(from trends: [ExerciseTrendSummary]) -> ExerciseType? {
        trends
            .filter { ($0.recentFormDelta ?? 0) >= 5 && $0.sessions >= 2 }
            .max { lhs, rhs in
                let lhsDelta = lhs.recentFormDelta ?? 0
                let rhsDelta = rhs.recentFormDelta ?? 0
                if lhsDelta == rhsDelta {
                    return lhs.exerciseType.rawValue > rhs.exerciseType.rawValue
                }
                return lhsDelta < rhsDelta
            }?
            .exerciseType
    }

    func strugglingExercise(from trends: [ExerciseTrendSummary]) -> ExerciseType? {
        trends
            .filter { struggleScore($0) >= 3 }
            .max { lhs, rhs in
                let lhsScore = struggleScore(lhs)
                let rhsScore = struggleScore(rhs)
                if lhsScore == rhsScore {
                    return lhs.exerciseType.rawValue > rhs.exerciseType.rawValue
                }
                return lhsScore < rhsScore
            }?
            .exerciseType
    }

    func struggleScore(_ trend: ExerciseTrendSummary) -> Int {
        var score = trend.formDropOffSetCount * 2
        score += min(trend.highSeverityCueCount, 4)
        score += trend.skippedSetCount * 2
        score += trend.restExtendedSetCount
        score += trend.cameraFrictionCueCount
        if let average = trend.averageFormScore, average < 75 {
            score += 2
        }
        if let delta = trend.recentFormDelta, delta <= -5 {
            score += 2
        }
        return score
    }

    func mostRepeatedCue(in history: [WorkoutSessionSummary]) -> String? {
        cueCounts(from: history.flatMap { summary in
            summary.exerciseSummaries.flatMap { setSummary in
                setSummary.cueEvents.map(\.cueMessage) +
                    setSummary.repQualityEvents.compactMap(\.cueMessageNearRep)
            }
        }).first?.key
    }

    func cueCounts(from cueMessages: [String]) -> [(key: String, value: Int)] {
        cueMessages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { counts, cue in
                counts[cue, default: 0] += 1
            }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
    }

    func trophyNearMisses(from snapshot: TrophyProgressSnapshot) -> [TrophyNearMiss] {
        snapshot.inProgress
            .compactMap { progress -> TrophyNearMiss? in
                guard progress.confidence != .unavailable,
                      progress.progressFraction >= 0.70,
                      let definition = TrophyDefinitionCatalog.definition(for: progress.trophyId)
                else { return nil }

                return TrophyNearMiss(
                    trophyId: progress.trophyId,
                    title: definition.title,
                    currentValue: progress.currentValue,
                    targetValue: progress.targetValue,
                    remainingValue: max(progress.targetValue - progress.currentValue, 0),
                    progressFraction: progress.progressFraction,
                    unit: definition.unit
                )
            }
            .sorted {
                if $0.progressFraction == $1.progressFraction {
                    return $0.title < $1.title
                }
                return $0.progressFraction > $1.progressFraction
            }
            .prefix(3)
            .map { $0 }
    }

    func cameraFrictionCount(in history: [WorkoutSessionSummary]) -> Int {
        history.reduce(0) { total, summary in
            total + summary.exerciseSummaries.reduce(0) { setTotal, setSummary in
                let cues = setSummary.cueEvents.map(\.cueMessage) +
                    setSummary.repQualityEvents.compactMap(\.cueMessageNearRep)
                return setTotal + cues.filter(Self.isCameraFrictionCue).count
            }
        }
    }

    func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
