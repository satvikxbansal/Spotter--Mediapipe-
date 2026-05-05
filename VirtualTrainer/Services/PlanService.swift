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

    func generateSmartStart(profile: UserProfile) -> WorkoutPlanV2 {
        generator.generate(
            input: PlanGenerationInput(
                profile: profile,
                sessionLength: .seven
            )
        )
    }

    func generateDailyPlan(profile: UserProfile) -> WorkoutPlanV2 {
        generator.generate(
            input: PlanGenerationInput(
                profile: profile,
                sessionLength: .twentyFive
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
}
