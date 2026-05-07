import XCTest
@testable import VirtualTrainer

final class InsightRankerTests: XCTestCase {
    func testPrimaryGoalMatchOutranksGoalMismatchBySevenPoints() {
        let ranker = InsightRanker()
        let profile = makeProfile(goal: .strength)
        let matching = makeCandidate(
            dedupeKey: "matching",
            relatedGoal: .strength,
            signalType: .qualityPR
        )
        let mismatched = makeCandidate(
            dedupeKey: "mismatched",
            relatedGoal: .longevity,
            signalType: .qualityPR
        )

        let delta = ranker.score(matching, surface: .profile, profile: profile)
            - ranker.score(mismatched, surface: .profile, profile: profile)

        XCTAssertEqual(delta, 7, accuracy: 0.001)
    }

    func testStrengthGoalBoostsStrengthProgressionSignals() {
        let ranker = InsightRanker()
        let profile = makeProfile(goal: .strength)
        let progression = makeCandidate(
            dedupeKey: "progression",
            relatedGoal: .strength,
            signalType: .progressionReadiness
        )
        let neutral = makeCandidate(
            dedupeKey: "neutral",
            relatedGoal: .strength,
            signalType: .sessionFit
        )

        let delta = ranker.score(progression, surface: .profile, profile: profile)
            - ranker.score(neutral, surface: .profile, profile: profile)

        XCTAssertEqual(delta, 6, accuracy: 0.001)
    }

    func testLongevityGoalBoostsRecoveryAndPlanFitSignals() {
        let ranker = InsightRanker()
        let profile = makeProfile(goal: .longevity)
        let restResponse = makeCandidate(
            dedupeKey: "rest-response",
            type: .planAdjustment,
            relatedGoal: .longevity,
            signalType: .restResponse
        )
        let neutral = makeCandidate(
            dedupeKey: "neutral",
            type: .planAdjustment,
            relatedGoal: .longevity,
            signalType: .qualityPR
        )
        let recoveryInsight = makeInsight(dedupeKey: "recovery", type: .recovery, relatedGoal: .longevity)
        let neutralInsight = makeInsight(dedupeKey: "neutral-insight", type: .growthCelebration, relatedGoal: .longevity)

        XCTAssertEqual(
            ranker.score(restResponse, surface: .dashboard, profile: profile)
                - ranker.score(neutral, surface: .dashboard, profile: profile),
            8,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ranker.score(recoveryInsight, surface: .dashboard, profile: profile)
                - ranker.score(neutralInsight, surface: .dashboard, profile: profile),
            8,
            accuracy: 0.001
        )
    }

    func testPerformanceGoalBoostsQualityCapacityAndFormImprovementSignals() {
        let ranker = InsightRanker()
        let profile = makeProfile(goal: .performance)
        let qualityCapacity = makeCandidate(
            dedupeKey: "capacity",
            relatedGoal: .performance,
            signalType: .qualityCapacity
        )
        let formImprovement = makeCandidate(
            dedupeKey: "form",
            relatedGoal: .performance,
            signalType: .formImprovement
        )
        let neutral = makeCandidate(
            dedupeKey: "neutral",
            relatedGoal: .performance,
            signalType: .sessionFit
        )

        XCTAssertEqual(
            ranker.score(qualityCapacity, surface: .profile, profile: profile)
                - ranker.score(neutral, surface: .profile, profile: profile),
            6,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ranker.score(formImprovement, surface: .profile, profile: profile)
                - ranker.score(neutral, surface: .profile, profile: profile),
            6,
            accuracy: 0.001
        )
    }
}

private extension InsightRankerTests {
    func makeCandidate(
        dedupeKey: String,
        type: InsightType = .growthCelebration,
        relatedGoal: FitnessGoal?,
        signalType: TrainingSignalType?
    ) -> InsightCandidate {
        var context: [String: String] = [:]
        if let signalType {
            context["signalType"] = signalType.rawValue
        }
        return InsightCandidate(
            type: type,
            candidateHeadline: "\(dedupeKey) insight",
            candidateAction: .continuePlan,
            evidence: [
                InsightEvidence(
                    metric: "test",
                    value: "value",
                    exerciseType: .squat,
                    confidence: 0.9
                )
            ],
            rawScore: 80,
            confidence: 0.9,
            surfaces: [.dashboard, .profile],
            severity: .positive,
            emotionalIntent: .buildConfidence,
            relatedExerciseType: .squat,
            relatedGoal: relatedGoal,
            createdAt: Date(timeIntervalSince1970: 1_778_067_200),
            dedupeKey: dedupeKey,
            context: context
        )
    }

    func makeInsight(
        dedupeKey: String,
        type: InsightType,
        relatedGoal: FitnessGoal?
    ) -> AIInsight {
        AIInsight(
            type: type,
            headline: "\(dedupeKey) headline",
            message: "\(dedupeKey) message",
            shortMessage: "\(dedupeKey) short",
            evidence: [
                InsightEvidence(
                    metric: "test",
                    value: "value",
                    exerciseType: .squat,
                    confidence: 0.9
                )
            ],
            recommendedAction: .continuePlan,
            severity: .positive,
            emotionalIntent: .buildConfidence,
            userValueScore: 80,
            confidence: 0.9,
            surfaces: [.dashboard],
            relatedExerciseType: .squat,
            relatedGoal: relatedGoal,
            createdAt: Date(timeIntervalSince1970: 1_778_067_200),
            dedupeKey: dedupeKey
        )
    }

    func makeProfile(goal: FitnessGoal) -> UserProfile {
        let now = Date(timeIntervalSince1970: 1_778_067_200)
        return UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000007777") ?? UUID(),
            displayName: "Ranker Tester",
            genderIdentity: .preferNotToSay,
            age: 31,
            height: 170,
            heightUnit: .metric,
            weight: 70,
            weightUnit: .metric,
            primaryGoal: goal,
            fitnessLevel: .beginner,
            equipment: [.bodyweight],
            preferredCoach: .bennett,
            selectedTheme: .hyper,
            preferredSessionLength: .fifteen,
            timezoneIdentifier: "UTC",
            onboardingCompletedAt: now,
            createdAt: now,
            updatedAt: now
        )
    }
}
