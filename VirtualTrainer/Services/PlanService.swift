import Foundation

nonisolated final class PlanService {
    private let generator: PlanGenerator
    private let swapService: PlanSwapService

    init(
        generator: PlanGenerator = PlanGenerator(),
        swapService: PlanSwapService = PlanSwapService()
    ) {
        self.generator = generator
        self.swapService = swapService
    }

    func generateSmartStart(
        profile: UserProfile,
        recentWorkoutHistory: [RecentWorkoutHistoryItem] = []
    ) -> WorkoutPlanV2 {
        generator.generate(
            input: PlanGenerationInput(
                profile: profile,
                sessionLength: .seven,
                recentWorkoutHistory: recentWorkoutHistory
            )
        )
    }

    func generateDailyPlan(
        profile: UserProfile,
        recentWorkoutHistory: [RecentWorkoutHistoryItem] = []
    ) -> WorkoutPlanV2 {
        generator.generate(
            input: PlanGenerationInput(
                profile: profile,
                sessionLength: .twentyFive,
                recentWorkoutHistory: recentWorkoutHistory
            )
        )
    }

    func generatePlan(input: PlanGenerationInput) -> WorkoutPlanV2 {
        generator.generate(input: input)
    }

    func swapExercise(
        in plan: WorkoutPlanV2,
        exerciseId: ExerciseType,
        reason: PlanSwapReason
    ) -> WorkoutPlanV2 {
        swapService.swapExercise(
            in: plan,
            exerciseId: exerciseId,
            reason: reason
        )
    }

    func swapExercise(
        in plan: WorkoutPlanV2,
        exerciseId: ExerciseType,
        reason: PlanSwapReason,
        input: PlanGenerationInput
    ) -> WorkoutPlanV2 {
        swapService.swapExercise(
            in: plan,
            exerciseId: exerciseId,
            reason: reason,
            input: input
        )
    }

    func swapAll(
        in plan: WorkoutPlanV2,
        reason: PlanSwapReason,
        input: PlanGenerationInput? = nil
    ) -> WorkoutPlanV2 {
        var updatedPlan = plan
        let originalExerciseIds = plan.blocks.flatMap(\.exercises)
            .filter(\.allowSwap)
            .map(\.exerciseType)

        for exerciseId in originalExerciseIds {
            updatedPlan = swapService.swapExercise(
                in: updatedPlan,
                exerciseId: exerciseId,
                reason: reason,
                input: input
            )
        }

        return updatedPlan
    }
}
