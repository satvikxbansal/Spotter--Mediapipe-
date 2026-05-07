import Foundation

nonisolated struct WorkoutRecap: Equatable {
    let headline: String
    let bodyMessage: String
    let highlightStat: String?
    let nextStep: String?
}

nonisolated enum InsightTextSanitizer {
    static let blocklist = [
        "heart-rate",
        "heart rate",
        "bpm",
        "calorie",
        "calories",
        "fat loss",
        "fat-loss",
        "weight loss",
        "weight-loss"
    ]

    static func sanitize(_ text: String) -> String {
        let normalized = text.lowercased()
        guard !blocklist.contains(where: { normalized.contains($0) }) else {
            return "This insight uses only supported local workout, form, cue, rest, and trophy evidence."
        }
        return text
    }
}

nonisolated struct WorkoutRecapBuilder {
    func build(summary: WorkoutSessionSummary) -> WorkoutRecap {
        guard let dominantExercise = DominantExercise.build(from: summary.exerciseSummaries),
              dominantExercise.hasSessionEvidence
        else {
            return genericRecap(summary: summary)
        }

        let trajectory = qualityTrajectory(for: dominantExercise)
        let bodyMessage = bodyMessage(
            summary: summary,
            dominantExercise: dominantExercise,
            trajectory: trajectory
        )

        return WorkoutRecap(
            headline: headline(
                exerciseType: dominantExercise.exerciseType,
                trajectory: trajectory
            ),
            bodyMessage: bodyMessage,
            highlightStat: highlightStat(for: dominantExercise),
            nextStep: nextStep(
                summary: summary,
                dominantExercise: dominantExercise,
                trajectory: trajectory
            )
        )
    }
}

nonisolated private extension WorkoutRecapBuilder {
    struct DominantExercise {
        let exerciseType: ExerciseType
        let firstSessionIndex: Int
        var sets: [ExerciseSetSummary]

        var totalReps: Int {
            sets.reduce(0) { $0 + max($1.achievedReps, 0) }
        }

        var totalHoldSeconds: Int {
            sets.reduce(0) { $0 + max($1.achievedHoldSeconds, 0) }
        }

        var totalVolume: Int {
            totalReps + totalHoldSeconds
        }

        var excellentFormReps: Int {
            sets.reduce(0) { total, set in
                total + (set.qualitySummary?.excellentFormReps ?? set.repQualityEvents.filter {
                    guard let formScore = $0.formScore else { return false }
                    return formScore >= 90
                }.count)
            }
        }

        var averageFormScore: Double? {
            let scores = sets.compactMap(\.averageFormScore)
            guard !scores.isEmpty else { return nil }
            return scores.reduce(0, +) / Double(scores.count)
        }

        var hasSessionEvidence: Bool {
            totalVolume > 0 ||
                averageFormScore != nil ||
                sets.contains { set in
                    set.qualitySummary != nil ||
                        !set.repQualityEvents.isEmpty ||
                        !set.cueEvents.isEmpty
                }
        }

        static func build(from sets: [ExerciseSetSummary]) -> DominantExercise? {
            var aggregates: [ExerciseType: DominantExercise] = [:]

            for (index, set) in sets.enumerated() {
                if aggregates[set.exerciseType] == nil {
                    aggregates[set.exerciseType] = DominantExercise(
                        exerciseType: set.exerciseType,
                        firstSessionIndex: index,
                        sets: []
                    )
                }
                aggregates[set.exerciseType]?.sets.append(set)
            }

            return aggregates.values.sorted { lhs, rhs in
                if lhs.totalVolume != rhs.totalVolume {
                    return lhs.totalVolume > rhs.totalVolume
                }
                if lhs.totalReps != rhs.totalReps {
                    return lhs.totalReps > rhs.totalReps
                }
                return lhs.firstSessionIndex < rhs.firstSessionIndex
            }.first
        }
    }

    struct QualityTrajectory {
        let trend: SetQualityTrend
        let firstHalfAverage: Double?
        let secondHalfAverage: Double?
        let averageFormScore: Double?

        var phrase: String {
            switch trend {
            case .improved:
                return "form climbed"
            case .faded:
                return "form faded"
            case .stable:
                return "form held"
            case .unknown:
                return "form scoring was limited"
            }
        }

        var sentenceFragment: String {
            if let firstHalfAverage, let secondHalfAverage {
                return "\(phrase) from \(percentText(firstHalfAverage)) to \(percentText(secondHalfAverage))"
            }
            if trend != .unknown {
                return phrase
            }
            if let averageFormScore {
                return "average form landed at \(percentText(averageFormScore))"
            }
            return phrase
        }

        private func percentText(_ value: Double) -> String {
            "\(Int(value.rounded()))%"
        }
    }

    func qualityTrajectory(for dominantExercise: DominantExercise) -> QualityTrajectory {
        let firstHalfAverages = dominantExercise.sets.compactMap {
            $0.qualitySummary?.firstHalfAverageFormScore
        }
        let secondHalfAverages = dominantExercise.sets.compactMap {
            $0.qualitySummary?.secondHalfAverageFormScore
        }

        if let firstAverage = average(firstHalfAverages),
           let secondAverage = average(secondHalfAverages) {
            return QualityTrajectory(
                trend: trend(firstAverage: firstAverage, secondAverage: secondAverage),
                firstHalfAverage: firstAverage,
                secondHalfAverage: secondAverage,
                averageFormScore: dominantExercise.averageFormScore
            )
        }

        let trends = dominantExercise.sets.compactMap(\.qualitySummary?.qualityTrend)
        let fallbackTrend: SetQualityTrend
        if trends.contains(.faded) {
            fallbackTrend = .faded
        } else if trends.contains(.improved) {
            fallbackTrend = .improved
        } else if trends.contains(.stable) {
            fallbackTrend = .stable
        } else {
            fallbackTrend = .unknown
        }

        return QualityTrajectory(
            trend: fallbackTrend,
            firstHalfAverage: nil,
            secondHalfAverage: nil,
            averageFormScore: dominantExercise.averageFormScore
        )
    }

    func trend(firstAverage: Double, secondAverage: Double) -> SetQualityTrend {
        let delta = secondAverage - firstAverage
        if delta >= 5 { return .improved }
        if delta <= -5 { return .faded }
        return .stable
    }

    func headline(
        exerciseType: ExerciseType,
        trajectory: QualityTrajectory
    ) -> String {
        let exercise = exerciseType.displayName
        switch trajectory.trend {
        case .improved:
            return "\(exercise) climbed late."
        case .faded:
            return "\(exercise) needs an early cue."
        case .stable:
            return "\(exercise) held the line."
        case .unknown:
            return "\(exercise) work is logged."
        }
    }

    func bodyMessage(
        summary: WorkoutSessionSummary,
        dominantExercise: DominantExercise,
        trajectory: QualityTrajectory
    ) -> String {
        let exercise = dominantExercise.exerciseType.displayName
        let firstSentence = "\(exercise) led the session with \(volumeText(reps: dominantExercise.totalReps, holdSeconds: dominantExercise.totalHoldSeconds)); \(trajectory.sentenceFragment)."

        var evidenceClauses: [String] = []
        if let breakdown = breakdownText(in: dominantExercise) {
            evidenceClauses.append(breakdown)
        }
        if let completionPercent = summary.completionPercent {
            evidenceClauses.append("\(completionText(completionPercent)) complete")
        }

        guard !evidenceClauses.isEmpty else { return firstSentence }
        return "\(firstSentence) \(joinedEvidenceSentence(evidenceClauses))."
    }

    func joinedEvidenceSentence(_ clauses: [String]) -> String {
        guard let first = clauses.first else { return "" }
        guard clauses.count > 1 else { return first.capitalizedFirstLetter }
        return "\(first.capitalizedFirstLetter), and \(clauses.dropFirst().joined(separator: ", and "))"
    }

    func breakdownText(in dominantExercise: DominantExercise) -> String? {
        let sortedSets = dominantExercise.sets.sorted { lhs, rhs in
            switch (lhs.setIndex, rhs.setIndex) {
            case let (lhsIndex?, rhsIndex?):
                return lhsIndex < rhsIndex
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return false
            }
        }

        for set in sortedSets {
            guard let repIndex = set.qualitySummary?.breakdownRepIndex,
                  repIndex > 0
            else { continue }

            let observedRepCeiling = max(
                max(set.achievedReps, 0),
                set.repQualityEvents.map(\.repIndex).max() ?? 0
            )
            guard repIndex <= observedRepCeiling else { continue }

            if let setIndex = set.setIndex {
                return "breakdown showed at set \(setIndex + 1), rep \(repIndex)"
            }
            return "breakdown showed at rep \(repIndex)"
        }

        return nil
    }

    func highlightStat(for dominantExercise: DominantExercise) -> String? {
        let bestRep = dominantExercise.sets.flatMap { set in
            set.repQualityEvents.compactMap { event -> (setIndex: Int?, repIndex: Int, score: Int)? in
                guard let score = event.formScore else { return nil }
                return (set.setIndex ?? event.setIndex, event.repIndex, score)
            }
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.repIndex != rhs.repIndex {
                return lhs.repIndex < rhs.repIndex
            }
            return (lhs.setIndex ?? Int.max) < (rhs.setIndex ?? Int.max)
        }
        .first

        if let bestRep {
            if let setIndex = bestRep.setIndex {
                return "Best rep: set \(setIndex + 1), rep \(bestRep.repIndex) hit \(bestRep.score)%"
            }
            return "Best rep: rep \(bestRep.repIndex) hit \(bestRep.score)%"
        }

        if dominantExercise.totalHoldSeconds > 0 {
            return "Hold total: \(durationText(dominantExercise.totalHoldSeconds))"
        }

        if dominantExercise.totalReps > 0 {
            return "Volume: \(dominantExercise.totalReps) reps"
        }

        return nil
    }

    func nextStep(
        summary: WorkoutSessionSummary,
        dominantExercise: DominantExercise,
        trajectory: QualityTrajectory
    ) -> String? {
        if trajectory.trend == .faded ||
            dominantExercise.sets.contains(where: { $0.qualitySummary?.qualityTrend == .faded }) {
            return "lock the cue early next time"
        }
        if dominantExercise.excellentFormReps >= 3 {
            return "earn a small rep bump"
        }
        if summary.exerciseSummaries.contains(where: \.restExtended) {
            return "give yourself 15s more rest next set"
        }
        return "keep the same target, deepen quality"
    }

    func genericRecap(summary: WorkoutSessionSummary) -> WorkoutRecap {
        let body: String
        if let safeGoal = safeGoalFragment(summary.goal) {
            body = "Logged a session for goal: \(safeGoal). Save a few more to unlock specific coaching."
        } else {
            body = "Logged a session. Save a few more to unlock specific coaching."
        }

        return WorkoutRecap(
            headline: "Session logged.",
            bodyMessage: body,
            highlightStat: nil,
            nextStep: "keep the same target, deepen quality"
        )
    }

    func safeGoalFragment(_ goal: String?) -> String? {
        guard let goal else { return nil }
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sanitized = InsightTextSanitizer.sanitize(trimmed)
        guard sanitized == trimmed else { return nil }

        let sentence = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return nil }
        return sentence
    }

    func volumeText(reps: Int, holdSeconds: Int) -> String {
        var pieces: [String] = []
        if reps > 0 {
            pieces.append("\(reps) \(reps == 1 ? "rep" : "reps")")
        }
        if holdSeconds > 0 {
            pieces.append("\(durationText(holdSeconds)) hold")
        }
        return pieces.isEmpty ? "logged work" : pieces.joined(separator: " and ")
    }

    func completionText(_ completion: Double) -> String {
        let clamped = min(max(completion, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    func durationText(_ seconds: Int) -> String {
        let safeSeconds = max(seconds, 0)
        guard safeSeconds >= 60 else { return "\(safeSeconds)s" }
        return String(format: "%d:%02d", safeSeconds / 60, safeSeconds % 60)
    }

    func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

nonisolated private extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
