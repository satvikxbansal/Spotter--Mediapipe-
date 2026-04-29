import XCTest
import CoreGraphics
@testable import VirtualTrainer

final class AngleCalculatorTests: XCTestCase {
    func testCenterJointNamesResolveToSyntheticMidpoints() {
        XCTAssertEqual(AngleCalculator.resolveJointName("hip_center", side: "right"), .root)
        XCTAssertEqual(AngleCalculator.resolveJointName("hip_center", side: "left"), .root)
        XCTAssertEqual(AngleCalculator.resolveJointName("shoulder_center", side: "right"), .neck)
        XCTAssertEqual(AngleCalculator.resolveJointName("shoulder_center", side: "left"), .neck)
    }

    func testSignedBodyLineDistinguishesSagFromPike() {
        let definition = testDefinition(
            angles: [
                AngleDefinition(
                    key: "bodyLineAngle",
                    label: "Body Line",
                    startJoint: "shoulder",
                    midJoint: "hip",
                    endJoint: "ankle",
                    side: .right
                )
            ],
            primary: "bodyLineAngle"
        )

        var joints: [JointName: CGPoint] = [
            .rightShoulder: CGPoint(x: 0, y: 0),
            .rightHip: CGPoint(x: 0.5, y: 0),
            .rightAnkle: CGPoint(x: 1, y: 0),
        ]
        XCTAssertEqual(AngleCalculator.computeAngles(joints: joints, for: definition)["bodyLineAngle"] ?? 0, 180, accuracy: 0.001)

        joints[.rightHip] = CGPoint(x: 0.5, y: 0.1)
        XCTAssertLessThan(AngleCalculator.computeAngles(joints: joints, for: definition)["bodyLineAngle"] ?? 180, 180)

        joints[.rightHip] = CGPoint(x: 0.5, y: -0.1)
        XCTAssertGreaterThan(AngleCalculator.computeAngles(joints: joints, for: definition)["bodyLineAngle"] ?? 180, 180)
    }

    func testMoreFlexedAndLessFlexedSelectExpectedSide() {
        let moreFlexed = testDefinition(
            angles: [
                AngleDefinition(
                    key: "kneeAngle",
                    label: "Knee",
                    startJoint: "hip",
                    midJoint: "knee",
                    endJoint: "ankle",
                    side: .moreFlexed
                )
            ],
            primary: "kneeAngle"
        )
        let lessFlexed = testDefinition(
            angles: [
                AngleDefinition(
                    key: "kneeAngle",
                    label: "Knee",
                    startJoint: "hip",
                    midJoint: "knee",
                    endJoint: "ankle",
                    side: .lessFlexed
                )
            ],
            primary: "kneeAngle"
        )

        let joints: [JointName: CGPoint] = [
            .leftHip: CGPoint(x: 0, y: 0),
            .leftKnee: CGPoint(x: 0, y: 1),
            .leftAnkle: CGPoint(x: 1, y: 1),
            .rightHip: CGPoint(x: 2, y: 0),
            .rightKnee: CGPoint(x: 2, y: 1),
            .rightAnkle: CGPoint(x: 2, y: 2),
        ]

        XCTAssertEqual(AngleCalculator.computeAngles(joints: joints, for: moreFlexed)["kneeAngle"] ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(AngleCalculator.computeAngles(joints: joints, for: lessFlexed)["kneeAngle"] ?? 0, 180, accuracy: 0.001)
    }

    func testBestAvailableUsesHigherVisibilityWhenBothSidesExist() {
        let definition = testDefinition(
            angles: [
                AngleDefinition(
                    key: "kneeAngle",
                    label: "Knee",
                    startJoint: "hip",
                    midJoint: "knee",
                    endJoint: "ankle",
                    side: .bestAvailable
                )
            ],
            primary: "kneeAngle"
        )

        let joints: [JointName: CGPoint] = [
            .leftHip: CGPoint(x: 0, y: 0),
            .leftKnee: CGPoint(x: 0, y: 1),
            .leftAnkle: CGPoint(x: 1, y: 1),
            .rightHip: CGPoint(x: 2, y: 0),
            .rightKnee: CGPoint(x: 2, y: 1),
            .rightAnkle: CGPoint(x: 2, y: 2),
        ]
        let visibility: [JointName: Float] = [
            .leftHip: 0.95, .leftKnee: 0.95, .leftAnkle: 0.95,
            .rightHip: 0.55, .rightKnee: 0.55, .rightAnkle: 0.55,
        ]

        XCTAssertEqual(
            AngleCalculator.computeAngles(
                joints: joints,
                jointVisibility: visibility,
                for: definition
            )["kneeAngle"] ?? 0,
            90,
            accuracy: 0.001
        )
    }

    func testKneeValgusUses3DWhenAvailable() {
        let check = PositionalCheck(
            id: "valgus",
            checkType: .kneeValgus,
            threshold: 0.15,
            jointA: nil,
            jointB: nil,
            activeDuringPhases: [],
            feedbackGood: "good",
            feedbackDrill: "drill",
            severity: "warning",
            cooldownSeconds: 1
        )
        let joints3D: [JointName: SIMD3<Float>] = [
            .leftHip: SIMD3<Float>(-0.2, 0, 0),
            .rightHip: SIMD3<Float>(0.2, 0, 0),
            .leftKnee: SIMD3<Float>(0.05, -0.5, 0),
            .leftAnkle: SIMD3<Float>(-0.2, -1, 0),
            .rightKnee: SIMD3<Float>(0.2, -0.5, 0),
            .rightAnkle: SIMD3<Float>(0.2, -1, 0),
        ]

        let results = AngleCalculator.evaluatePositionalChecks(
            [check],
            joints2D: [:],
            joints3D: joints3D
        )

        XCTAssertEqual(results["valgus"]?.violated, true)
        XCTAssertGreaterThan(results["valgus"]?.value ?? 0, 0.15)
    }

    func testBodyLineUses3DSignedMeasurementWhenAvailable() {
        let definition = testDefinition(
            angles: [
                AngleDefinition(
                    key: "bodyLineAngle",
                    label: "Body Line",
                    startJoint: "shoulder",
                    midJoint: "hip",
                    endJoint: "ankle",
                    side: .right
                )
            ],
            primary: "bodyLineAngle"
        )
        let joints2D: [JointName: CGPoint] = [
            .rightShoulder: CGPoint(x: 0, y: 0),
            .rightHip: CGPoint(x: 0.5, y: 0),
            .rightAnkle: CGPoint(x: 1, y: 0),
        ]
        let joints3D: [JointName: SIMD3<Float>] = [
            .rightShoulder: SIMD3<Float>(0, 0, 0),
            .rightHip: SIMD3<Float>(0.5, -0.1, 0),
            .rightAnkle: SIMD3<Float>(1, 0, 0),
        ]

        let angle = AngleCalculator.computeAngles3D(
            joints2D: joints2D,
            joints3D: joints3D,
            for: definition
        )["bodyLineAngle"]

        XCTAssertGreaterThan(angle ?? 0, 180)
    }
}

private func testDefinition(
    angles: [AngleDefinition],
    primary: String,
    movementType: MovementType = .repetition,
    holdRange: ClosedRange<Double>? = nil
) -> ExerciseDefinition {
    ExerciseDefinition(
        id: "test",
        displayName: "Test",
        category: .fullBody,
        movementType: movementType,
        cameraPosition: .side,
        setupInstruction: "Test",
        requiredJoints: [],
        visibilityHint: "Test",
        angles: angles,
        primaryAngleKey: primary,
        downThreshold: PhaseThreshold(angleKey: primary, enterBelow: 100, enterAbove: nil),
        upThreshold: PhaseThreshold(angleKey: primary, enterBelow: nil, enterAbove: 160),
        qualityTarget: nil,
        qualityTargetIsMinimum: false,
        formRules: [],
        targetMuscles: [],
        holdAngleRange: holdRange
    )
}
