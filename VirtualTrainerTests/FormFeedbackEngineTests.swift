import XCTest
@testable import VirtualTrainer

final class FormFeedbackEngineTests: XCTestCase {
    func testHigherSeverityFormRuleWinsEvenWhenListedLater() {
        let definition = feedbackDefinition(rules: [
            FormRule(
                id: "warning_rule",
                angleKey: "testAngle",
                minAngle: nil,
                maxAngle: 90,
                activeDuringPhases: ["down"],
                feedbackGood: "warning good",
                feedbackDrill: "warning drill",
                severity: "warning",
                cooldownSeconds: 1
            ),
            FormRule(
                id: "critical_rule",
                angleKey: "testAngle",
                minAngle: nil,
                maxAngle: 80,
                activeDuringPhases: ["down"],
                feedbackGood: "critical good",
                feedbackDrill: "critical drill",
                severity: "critical",
                cooldownSeconds: 1
            ),
        ])

        let feedbacks = FormFeedbackEngine().evaluate(
            joints: feedbackJoints(),
            angles: ["testAngle": 100],
            phase: .down,
            definition: definition,
            personality: .good
        )

        XCTAssertEqual(feedbacks.first?.ruleId, "critical_rule")
        XCTAssertEqual(feedbacks.first?.severity, .critical)
    }

    func testEqualSeverityFormRulesKeepFirstListedRule() {
        let definition = feedbackDefinition(rules: [
            FormRule(
                id: "first_warning",
                angleKey: "testAngle",
                minAngle: nil,
                maxAngle: 90,
                activeDuringPhases: ["down"],
                feedbackGood: "first good",
                feedbackDrill: "first drill",
                severity: "warning",
                cooldownSeconds: 1
            ),
            FormRule(
                id: "second_warning",
                angleKey: "testAngle",
                minAngle: nil,
                maxAngle: 85,
                activeDuringPhases: ["down"],
                feedbackGood: "second good",
                feedbackDrill: "second drill",
                severity: "warning",
                cooldownSeconds: 1
            ),
        ])

        let feedbacks = FormFeedbackEngine().evaluate(
            joints: feedbackJoints(),
            angles: ["testAngle": 100],
            phase: .down,
            definition: definition,
            personality: .good
        )

        XCTAssertEqual(feedbacks.first?.ruleId, "first_warning")
        XCTAssertEqual(feedbacks.first?.message, "first good")
    }

    func testHigherSeverityPositionalRuleWinsEvenWhenListedLater() {
        let definition = feedbackDefinition(
            rules: [],
            positionalChecks: [
                PositionalCheck(
                    id: "warning_position",
                    checkType: .jointAlignedX,
                    threshold: 0.05,
                    jointA: .rightShoulder,
                    jointB: .rightWrist,
                    activeDuringPhases: ["down"],
                    feedbackGood: "warning position good",
                    feedbackDrill: "warning position drill",
                    severity: "warning",
                    cooldownSeconds: 1
                ),
                PositionalCheck(
                    id: "critical_position",
                    checkType: .jointAboveJoint,
                    threshold: 0.05,
                    jointA: .rightShoulder,
                    jointB: .rightElbow,
                    activeDuringPhases: ["down"],
                    feedbackGood: "critical position good",
                    feedbackDrill: "critical position drill",
                    severity: "critical",
                    cooldownSeconds: 1
                ),
            ]
        )

        let feedbacks = FormFeedbackEngine().evaluate(
            joints: [
                .rightShoulder: CGPoint(x: 0.0, y: 0.0),
                .rightElbow: CGPoint(x: 0.5, y: 0.2),
                .rightWrist: CGPoint(x: 1.0, y: 0.1),
            ],
            angles: ["testAngle": 100],
            phase: .down,
            definition: definition,
            personality: .good
        )

        XCTAssertEqual(feedbacks.first?.ruleId, "critical_position")
        XCTAssertEqual(feedbacks.first?.severity, .critical)
    }
}

private func feedbackDefinition(
    rules: [FormRule],
    positionalChecks: [PositionalCheck] = []
) -> ExerciseDefinition {
    ExerciseDefinition(
        id: "feedbackTest",
        displayName: "Feedback Test",
        category: .fullBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Test",
        requiredJoints: [.rightShoulder, .rightElbow, .rightWrist],
        visibilityHint: "Test",
        angles: [
            AngleDefinition(
                key: "testAngle",
                label: "Test",
                startJoint: "shoulder",
                midJoint: "elbow",
                endJoint: "wrist",
                side: .right
            )
        ],
        primaryAngleKey: "testAngle",
        downThreshold: PhaseThreshold(angleKey: "testAngle", enterBelow: 90, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "testAngle", enterBelow: nil, enterAbove: 160),
        qualityTarget: nil,
        qualityTargetIsMinimum: false,
        formRules: rules,
        positionalChecks: positionalChecks,
        targetMuscles: []
    )
}

private func feedbackJoints() -> [JointName: CGPoint] {
    [
        .rightShoulder: CGPoint(x: 0, y: 0),
        .rightElbow: CGPoint(x: 0.5, y: 0),
        .rightWrist: CGPoint(x: 1, y: 0),
    ]
}
