import Foundation

nonisolated struct PlanGenerationRules: Codable, Equatable {
    let maxExercises: Int
    let maxCameraSwitches: Int
    let allowedDifficulties: Set<ExerciseDifficulty>
    let bodyweightFirst: Bool
    let avoidHighImpactWhenAlternativesExist: Bool
    let lowerImpactBias: Bool
    let balanceMobilityBias: Bool
    let restBonusSeconds: Int
    let targetMultiplier: Double

    static func resolved(for input: PlanGenerationInput) -> PlanGenerationRules {
        let allowedDifficulties: Set<ExerciseDifficulty>
        switch input.fitnessLevel {
        case .beginner:
            allowedDifficulties = [.beginner]
        case .intermediate:
            allowedDifficulties = [.beginner, .intermediate]
        }

        let age = input.profile.age
        let agePolicy: AgePolicy
        switch age {
        case ..<18:
            agePolicy = AgePolicy(
                bodyweightFirst: true,
                avoidHighImpact: true,
                lowerImpactBias: true,
                balanceMobilityBias: true,
                restBonusSeconds: 15,
                targetMultiplier: 0.80
            )
        case 18...34:
            agePolicy = AgePolicy(
                bodyweightFirst: false,
                avoidHighImpact: false,
                lowerImpactBias: false,
                balanceMobilityBias: false,
                restBonusSeconds: 0,
                targetMultiplier: 1.0
            )
        case 35...49:
            let isBeginner = input.fitnessLevel == .beginner
            agePolicy = AgePolicy(
                bodyweightFirst: false,
                avoidHighImpact: false,
                lowerImpactBias: isBeginner,
                balanceMobilityBias: false,
                restBonusSeconds: isBeginner ? 15 : 5,
                targetMultiplier: isBeginner ? 0.95 : 1.0
            )
        case 50...64:
            agePolicy = AgePolicy(
                bodyweightFirst: false,
                avoidHighImpact: true,
                lowerImpactBias: true,
                balanceMobilityBias: false,
                restBonusSeconds: 20,
                targetMultiplier: 0.85
            )
        default:
            agePolicy = AgePolicy(
                bodyweightFirst: true,
                avoidHighImpact: true,
                lowerImpactBias: true,
                balanceMobilityBias: true,
                restBonusSeconds: 30,
                targetMultiplier: 0.75
            )
        }

        return PlanGenerationRules(
            maxExercises: input.sessionLength.maxExercises,
            maxCameraSwitches: input.sessionLength.maxCameraSwitches,
            allowedDifficulties: allowedDifficulties,
            bodyweightFirst: agePolicy.bodyweightFirst,
            avoidHighImpactWhenAlternativesExist: agePolicy.avoidHighImpact,
            lowerImpactBias: agePolicy.lowerImpactBias,
            balanceMobilityBias: agePolicy.balanceMobilityBias,
            restBonusSeconds: agePolicy.restBonusSeconds,
            targetMultiplier: agePolicy.targetMultiplier
        )
    }

    private struct AgePolicy {
        let bodyweightFirst: Bool
        let avoidHighImpact: Bool
        let lowerImpactBias: Bool
        let balanceMobilityBias: Bool
        let restBonusSeconds: Int
        let targetMultiplier: Double
    }
}
