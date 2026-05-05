import Foundation

nonisolated struct WorkoutExerciseSummary: Identifiable {
    let id: String
    let exerciseType: ExerciseType
    let setsCompleted: Int
    let totalReps: Int
    let totalHoldSeconds: TimeInterval

    init(
        exerciseIndex: Int,
        exerciseType: ExerciseType,
        setsCompleted: Int,
        totalReps: Int,
        totalHoldSeconds: TimeInterval
    ) {
        self.id = "\(exerciseIndex)-\(exerciseType.rawValue)"
        self.exerciseType = exerciseType
        self.setsCompleted = setsCompleted
        self.totalReps = totalReps
        self.totalHoldSeconds = totalHoldSeconds
    }
}

nonisolated struct WorkoutSummary: Identifiable {
    let planId: UUID
    let planTitle: String
    let duration: TimeInterval
    let exercisesCompleted: Int
    let totalExercises: Int
    let completedSets: Int
    let totalSets: Int
    let totalReps: Int
    let totalHoldSeconds: TimeInterval
    let averageFormScore: Double?
    let completionPercentage: Double
    let coachInsight: String
    let exerciseSummaries: [WorkoutExerciseSummary]

    var id: UUID { planId }
}

nonisolated enum WorkoutSummaryBuilder {
    static func build(
        plan: WorkoutPlanV2,
        startedAt: Date,
        completedSets: [PlannedWorkoutSetSummary],
        completedAt: Date = Date()
    ) -> WorkoutSummary {
        let plannedExercises = plan.blocks.flatMap(\.exercises)
        let plannedSetCount = plannedExercises.reduce(0) { $0 + $1.sets.count }
        let safeCompletedSetCount = completedSets.count
        let completionPercentage = plannedSetCount > 0
            ? min(Double(safeCompletedSetCount) / Double(plannedSetCount), 1.0)
            : 1.0

        let lastCompletedAt = completedSets
            .map(\.completedAt)
            .max() ?? completedAt
        let wallDuration = max(lastCompletedAt.timeIntervalSince(startedAt), 0)
        let activeDuration = completedSets.reduce(0) {
            $0 + max($1.duration, 0)
        }

        let formScores = completedSets.compactMap { $0.latestFormScore?.score }
        let averageFormScore = formScores.isEmpty
            ? nil
            : Double(formScores.reduce(0, +)) / Double(formScores.count)

        return WorkoutSummary(
            planId: plan.id,
            planTitle: plan.title,
            duration: max(wallDuration, activeDuration),
            exercisesCompleted: Set(completedSets.map(\.exerciseIndex)).count,
            totalExercises: plannedExercises.count,
            completedSets: safeCompletedSetCount,
            totalSets: plannedSetCount,
            totalReps: completedSets.reduce(0) { $0 + max($1.reps, 0) },
            totalHoldSeconds: completedSets.reduce(0) { $0 + max($1.holdDuration, 0) },
            averageFormScore: averageFormScore,
            completionPercentage: completionPercentage,
            coachInsight: Self.placeholderInsight(
                completedSets: safeCompletedSetCount,
                totalSets: plannedSetCount
            ),
            exerciseSummaries: Self.exerciseSummaries(from: completedSets)
        )
    }

    private static func placeholderInsight(
        completedSets: Int,
        totalSets: Int
    ) -> String {
        if totalSets > 0, completedSets < totalSets {
            return "Coach insight will use the completed sets from this partial session once workout history is live."
        }
        return "Coach insight will use form, cue, rest, and completion trends once workout history is live."
    }

    private static func exerciseSummaries(
        from completedSets: [PlannedWorkoutSetSummary]
    ) -> [WorkoutExerciseSummary] {
        struct Accumulator {
            let exerciseType: ExerciseType
            var setsCompleted: Int
            var totalReps: Int
            var totalHoldSeconds: TimeInterval
        }

        var summariesByIndex: [Int: Accumulator] = [:]

        for set in completedSets {
            let existing = summariesByIndex[set.exerciseIndex]
            summariesByIndex[set.exerciseIndex] = Accumulator(
                exerciseType: existing?.exerciseType ?? set.exerciseType,
                setsCompleted: (existing?.setsCompleted ?? 0) + 1,
                totalReps: (existing?.totalReps ?? 0) + max(set.reps, 0),
                totalHoldSeconds: (existing?.totalHoldSeconds ?? 0) + max(set.holdDuration, 0)
            )
        }

        return summariesByIndex
            .keys
            .sorted()
            .compactMap { index in
                guard let summary = summariesByIndex[index] else { return nil }
                return WorkoutExerciseSummary(
                    exerciseIndex: index,
                    exerciseType: summary.exerciseType,
                    setsCompleted: summary.setsCompleted,
                    totalReps: summary.totalReps,
                    totalHoldSeconds: summary.totalHoldSeconds
                )
            }
    }
}
