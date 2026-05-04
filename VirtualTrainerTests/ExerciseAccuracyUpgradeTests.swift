import XCTest
import CoreGraphics
@testable import VirtualTrainer

final class ExerciseAccuracyUpgradeTests: XCTestCase {
    func testAllIsometricExercisesHaveValidHoldBands() {
        for definition in ExerciseLibrary.all where definition.movementType == .isometric {
            XCTAssertNotNil(definition.holdAngleRange, "\(definition.id) isometric exercise needs a hold band")
            if let range = definition.holdAngleRange {
                XCTAssertLessThan(range.lowerBound, range.upperBound, "\(definition.id) hold band must be ordered")
                XCTAssertGreaterThanOrEqual(range.lowerBound, 0, "\(definition.id) hold band cannot start below 0")
                XCTAssertLessThanOrEqual(range.upperBound, 220, "\(definition.id) hold band exceeds supported signed angle range")
            }
        }
    }

    func testBilateralTelemetryIncludesActiveSideAngleDefinitions() {
        let definition = accuracyTestDefinition(
            angles: [
                AngleDefinition(
                    key: "frontKneeAngle",
                    label: "Front Knee",
                    startJoint: "hip",
                    midJoint: "knee",
                    endJoint: "ankle",
                    side: .moreFlexed
                )
            ],
            primary: "frontKneeAngle"
        )

        let bilateral = AngleCalculator.computeBilateralAngles(joints: lungeJoints(), for: definition)

        XCTAssertNotNil(bilateral["frontKneeAngle"]?.left)
        XCTAssertNotNil(bilateral["frontKneeAngle"]?.right)
        XCTAssertEqual(bilateral["frontKneeAngle"]?.selectedSide(preferSmaller: true), "right")
    }

    func testActiveSideLocksDuringUnilateralRep() {
        let definition = accuracyTestDefinition(
            angles: [
                AngleDefinition(
                    key: "frontKneeAngle",
                    label: "Front Knee",
                    startJoint: "hip",
                    midJoint: "knee",
                    endJoint: "ankle",
                    side: .moreFlexed
                )
            ],
            primary: "frontKneeAngle",
            down: PhaseThreshold(angleKey: "frontKneeAngle", enterBelow: 120, enterAbove: nil),
            up: PhaseThreshold(angleKey: "frontKneeAngle", enterBelow: nil, enterAbove: 155)
        )
        let counter = UniversalRepCounter(definition: definition)

        _ = counter.processJoints(lungeJoints())
        _ = counter.processJoints(lungeJoints())

        XCTAssertEqual(counter.currentPhase, .down)
        XCTAssertEqual(counter.lastActiveSide, "right")

        _ = counter.processJoints(swappedLungeJoints())

        XCTAssertEqual(counter.lastActiveSide, "right", "active side should not switch mid-rep")
    }

    func testNewPositionalChecksProduceResults() {
        let checks: [PositionalCheck] = [
            check("stance", .stanceWidth, threshold: 1.4),
            check("kneeFoot", .kneeOverFootLine, threshold: 0.2),
            check("kneeAnkle", .kneeOverAnkle, threshold: 0.15),
            check("hips", .hipBetweenKnees, threshold: 0.05),
            check("pelvis", .pelvisLevel, threshold: 0.1),
            check("trunk", .trunkLean, threshold: 0.2),
            check("wristElbow", .wristOverElbow, threshold: 0.2),
            check("support", .shoulderOverSupport, threshold: 0.2),
        ]

        let results = AngleCalculator.evaluatePositionalChecks(
            checks,
            joints2D: fullBodyJoints(),
            joints3D: [:]
        )

        for check in checks {
            XCTAssertNotNil(results[check.id], "\(check.id) should be wired in AngleCalculator")
        }
    }

    func testRiskyPoseContradictoryChecksAreNotRegistered() {
        let disallowed = Set([
            "triangle_shoulders",
            "sideplank_shoulders",
            "calfraise_foot_contact",
            "situp_control",
            "vup_trunk_control",
            "reversecrunch_control",
            "cobra_neck_proxy",
            "dd_heel_reach",
            "frontrise_torso_sway",
        ])

        for definition in ExerciseLibrary.all {
            for check in definition.positionalChecks {
                XCTAssertFalse(disallowed.contains(check.id), "\(definition.id) still includes risky check \(check.id)")
            }
        }
    }

    func testKneeOverAnkleUsesWorkingLegWhenOneKneeIsClearlyMoreFlexed() {
        let check = check("kneeAnkle", .kneeOverAnkle, threshold: 0.30)

        let results = AngleCalculator.evaluatePositionalChecks(
            [check],
            joints2D: sideViewLungeWithStraightTrailLeg(),
            joints3D: [:]
        )

        XCTAssertEqual(results["kneeAnkle"]?.violated, false)
    }

    func testPelvisLevelDoesNotExplodeWhenHipWidthIsSmallInSideView() {
        let check = check("pelvis", .pelvisLevel, threshold: 0.18)

        let results = AngleCalculator.evaluatePositionalChecks(
            [check],
            joints2D: narrowSideViewPelvisJoints(),
            joints3D: [:]
        )

        XCTAssertEqual(results["pelvis"]?.violated, false)
    }

    func testLowVisibilitySuppressesPositionalFeedback() {
        let definition = positionalFeedbackDefinition()
        let feedbacks = FormFeedbackEngine().evaluate(
            joints: [
                .leftShoulder: CGPoint(x: 0.3, y: 0.2),
                .rightShoulder: CGPoint(x: 0.7, y: 0.4),
            ],
            angles: ["testAngle": 180],
            phase: .down,
            definition: definition,
            personality: .good,
            jointVisibility: [.leftShoulder: 0.95, .rightShoulder: 0.20]
        )

        XCTAssertTrue(feedbacks.isEmpty)
    }

    func testBothSideFormRuleRequiresBothSidesVisible() {
        let definition = bothSideFeedbackDefinition()
        let feedbacks = FormFeedbackEngine().evaluate(
            joints: [
                .leftShoulder: CGPoint(x: 0.2, y: 0.2),
                .leftElbow: CGPoint(x: 0.3, y: 0.4),
                .leftWrist: CGPoint(x: 0.4, y: 0.6),
                .rightShoulder: CGPoint(x: 0.8, y: 0.2),
                .rightElbow: CGPoint(x: 0.7, y: 0.4),
                .rightWrist: CGPoint(x: 0.6, y: 0.6),
            ],
            angles: ["elbowAngle": 120],
            phase: .down,
            definition: definition,
            personality: .good,
            jointVisibility: [
                .leftShoulder: 0.95, .leftElbow: 0.95, .leftWrist: 0.95,
                .rightShoulder: 0.95, .rightElbow: 0.40, .rightWrist: 0.95,
            ]
        )

        XCTAssertTrue(feedbacks.isEmpty)
    }
}

private func accuracyTestDefinition(
    angles: [AngleDefinition],
    primary: String,
    down: PhaseThreshold? = nil,
    up: PhaseThreshold? = nil
) -> ExerciseDefinition {
    ExerciseDefinition(
        id: "accuracyTest",
        displayName: "Accuracy Test",
        category: .fullBody,
        movementType: .repetition,
        cameraPosition: .side,
        setupInstruction: "Test",
        requiredJoints: [],
        visibilityHint: "Test",
        angles: angles,
        primaryAngleKey: primary,
        downThreshold: down ?? PhaseThreshold(angleKey: primary, enterBelow: 100, enterAbove: nil),
        upThreshold: up ?? PhaseThreshold(angleKey: primary, enterBelow: nil, enterAbove: 160),
        qualityTarget: nil,
        qualityTargetIsMinimum: false,
        formRules: [],
        targetMuscles: [],
        minRepDuration: 0
    )
}

private func check(
    _ id: String,
    _ type: PositionalCheck.CheckType,
    threshold: Double
) -> PositionalCheck {
    PositionalCheck(
        id: id,
        checkType: type,
        threshold: threshold,
        jointA: nil,
        jointB: nil,
        activeDuringPhases: [],
        feedbackGood: "good",
        feedbackDrill: "drill",
        severity: "info",
        cooldownSeconds: 1
    )
}

private func lungeJoints() -> [JointName: CGPoint] {
    [
        .leftHip: CGPoint(x: 0.2, y: 0.2),
        .leftKnee: CGPoint(x: 0.2, y: 0.6),
        .leftAnkle: CGPoint(x: 0.2, y: 1.0),
        .rightHip: CGPoint(x: 0.7, y: 0.2),
        .rightKnee: CGPoint(x: 0.7, y: 0.6),
        .rightAnkle: CGPoint(x: 0.95, y: 0.6),
    ]
}

private func swappedLungeJoints() -> [JointName: CGPoint] {
    [
        .leftHip: CGPoint(x: 0.2, y: 0.2),
        .leftKnee: CGPoint(x: 0.2, y: 0.6),
        .leftAnkle: CGPoint(x: 0.45, y: 0.6),
        .rightHip: CGPoint(x: 0.7, y: 0.2),
        .rightKnee: CGPoint(x: 0.7, y: 0.6),
        .rightAnkle: CGPoint(x: 0.78, y: 0.95),
    ]
}

private func fullBodyJoints() -> [JointName: CGPoint] {
    [
        .neck: CGPoint(x: 0.5, y: 0.15),
        .root: CGPoint(x: 0.5, y: 0.45),
        .leftShoulder: CGPoint(x: 0.35, y: 0.16),
        .rightShoulder: CGPoint(x: 0.65, y: 0.16),
        .leftElbow: CGPoint(x: 0.34, y: 0.34),
        .rightElbow: CGPoint(x: 0.66, y: 0.34),
        .leftWrist: CGPoint(x: 0.33, y: 0.52),
        .rightWrist: CGPoint(x: 0.67, y: 0.52),
        .leftHip: CGPoint(x: 0.42, y: 0.45),
        .rightHip: CGPoint(x: 0.58, y: 0.45),
        .leftKnee: CGPoint(x: 0.38, y: 0.72),
        .rightKnee: CGPoint(x: 0.62, y: 0.72),
        .leftAnkle: CGPoint(x: 0.34, y: 0.95),
        .rightAnkle: CGPoint(x: 0.66, y: 0.95),
        .leftHeel: CGPoint(x: 0.33, y: 0.96),
        .rightHeel: CGPoint(x: 0.67, y: 0.96),
        .leftFootIndex: CGPoint(x: 0.31, y: 0.94),
        .rightFootIndex: CGPoint(x: 0.69, y: 0.94),
    ]
}

private func sideViewLungeWithStraightTrailLeg() -> [JointName: CGPoint] {
    [
        .leftHip: CGPoint(x: 0.10, y: 0.10),
        .leftKnee: CGPoint(x: 0.45, y: 0.50),
        .leftAnkle: CGPoint(x: 0.90, y: 0.90),
        .rightHip: CGPoint(x: 0.60, y: 0.10),
        .rightKnee: CGPoint(x: 0.60, y: 0.50),
        .rightAnkle: CGPoint(x: 0.90, y: 0.50),
    ]
}

private func narrowSideViewPelvisJoints() -> [JointName: CGPoint] {
    [
        .neck: CGPoint(x: 0.50, y: 0.20),
        .root: CGPoint(x: 0.50, y: 0.50),
        .leftShoulder: CGPoint(x: 0.35, y: 0.20),
        .rightShoulder: CGPoint(x: 0.65, y: 0.20),
        .leftHip: CGPoint(x: 0.49, y: 0.50),
        .rightHip: CGPoint(x: 0.51, y: 0.52),
    ]
}

private func positionalFeedbackDefinition() -> ExerciseDefinition {
    ExerciseDefinition(
        id: "positionalFeedback",
        displayName: "Positional Feedback",
        category: .fullBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Test",
        requiredJoints: [.leftShoulder, .rightShoulder],
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
        downThreshold: PhaseThreshold(angleKey: "testAngle", enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "testAngle", enterBelow: nil, enterAbove: 160),
        qualityTarget: nil,
        qualityTargetIsMinimum: false,
        formRules: [],
        positionalChecks: [
            PositionalCheck(
                id: "shoulders",
                checkType: .shoulderLevel,
                threshold: 0.04,
                jointA: nil,
                jointB: nil,
                activeDuringPhases: ["down"],
                feedbackGood: "good",
                feedbackDrill: "drill",
                severity: "warning",
                cooldownSeconds: 1
            )
        ],
        targetMuscles: []
    )
}

private func bothSideFeedbackDefinition() -> ExerciseDefinition {
    ExerciseDefinition(
        id: "bothSideFeedback",
        displayName: "Both Side Feedback",
        category: .upperBody,
        movementType: .repetition,
        cameraPosition: .front,
        setupInstruction: "Test",
        requiredJoints: [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist],
        visibilityHint: "Test",
        angles: [
            AngleDefinition(
                key: "elbowAngle",
                label: "Elbow",
                startJoint: "shoulder",
                midJoint: "elbow",
                endJoint: "wrist",
                side: .both
            )
        ],
        primaryAngleKey: "elbowAngle",
        downThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: "elbowAngle", enterBelow: nil, enterAbove: 160),
        qualityTarget: nil,
        qualityTargetIsMinimum: false,
        formRules: [
            FormRule(
                id: "both_rule",
                angleKey: "elbowAngle",
                minAngle: nil,
                maxAngle: 100,
                activeDuringPhases: ["down"],
                feedbackGood: "good",
                feedbackDrill: "drill",
                severity: "warning",
                cooldownSeconds: 1
            )
        ],
        targetMuscles: []
    )
}
