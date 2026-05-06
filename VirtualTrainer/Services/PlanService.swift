import Foundation

nonisolated final class PlanService {
    private let generator: PlanGenerator
    private let swapService: PlanSwapService
    private let quickStartDeckService: QuickStartPlanDeckService

    init(
        generator: PlanGenerator = PlanGenerator(),
        swapService: PlanSwapService = PlanSwapService(),
        quickStartDeckService: QuickStartPlanDeckService? = nil
    ) {
        self.generator = generator
        self.swapService = swapService
        self.quickStartDeckService = quickStartDeckService ?? QuickStartPlanDeckService(generator: generator)
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

    func generateSmartStart(
        profile: UserProfile,
        variantSeed: String,
        recentWorkoutHistory: [RecentWorkoutHistoryItem] = [],
        now: Date = Date()
    ) -> WorkoutPlanV2 {
        quickStartDeckService.generateSmartStart(
            profile: profile,
            variantSeed: variantSeed,
            recentWorkoutHistory: recentWorkoutHistory,
            now: now
        )
    }

    func generateQuickStartDeck(
        profile: UserProfile,
        recentWorkoutHistory: [RecentWorkoutHistoryItem] = [],
        now: Date = Date()
    ) -> QuickStartDeck {
        quickStartDeckService.generateDeck(
            profile: profile,
            recentWorkoutHistory: recentWorkoutHistory,
            now: now
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
