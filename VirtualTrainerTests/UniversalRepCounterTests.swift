import XCTest
@testable import VirtualTrainer

final class UniversalRepCounterTests: XCTestCase {
    func testCompletedRepLeavesObservableUpPhase() {
        let definition = counterDefinition(
            down: PhaseThreshold(angleKey: "kneeAngle", enterBelow: 150, enterAbove: nil),
            up: PhaseThreshold(angleKey: "kneeAngle", enterBelow: nil, enterAbove: 160)
        )
        let counter = UniversalRepCounter(definition: definition)

        _ = counter.process(angles: ["kneeAngle": 170])
        _ = counter.process(angles: ["kneeAngle": 120])
        _ = counter.process(angles: ["kneeAngle": 120])
        _ = counter.process(angles: ["kneeAngle": 120])
        _ = counter.process(angles: ["kneeAngle": 190])
        _ = counter.process(angles: ["kneeAngle": 190])
        let output = counter.process(angles: ["kneeAngle": 190])

        XCTAssertEqual(output.repCount, 1)
        XCTAssertEqual(output.phase, .up)
        XCTAssertEqual(counter.repRecords.count, 1)
    }

    func testIsometricHoldUsesValidBandWhenConfigured() {
        let definition = counterDefinition(
            movementType: .isometric,
            down: PhaseThreshold(angleKey: "kneeAngle", enterBelow: 100, enterAbove: nil),
            up: PhaseThreshold(angleKey: "kneeAngle", enterBelow: nil, enterAbove: 150),
            holdRange: 80...100
        )
        let counter = UniversalRepCounter(definition: definition)

        let holding = counter.process(angles: ["kneeAngle": 90])
        XCTAssertTrue(holding.isHolding)

        _ = counter.process(angles: ["kneeAngle": 70])
        _ = counter.process(angles: ["kneeAngle": 70])
        let outOfBand = counter.process(angles: ["kneeAngle": 70])
        XCTAssertFalse(outOfBand.isHolding)
    }

    func testHalfRepDoesNotCount() {
        let definition = counterDefinition(
            down: PhaseThreshold(angleKey: "kneeAngle", enterBelow: 150, enterAbove: nil),
            up: PhaseThreshold(angleKey: "kneeAngle", enterBelow: nil, enterAbove: 160)
        )
        let counter = UniversalRepCounter(definition: definition)

        _ = counter.process(angles: ["kneeAngle": 170])
        _ = counter.process(angles: ["kneeAngle": 120])
        _ = counter.process(angles: ["kneeAngle": 120])
        _ = counter.process(angles: ["kneeAngle": 120])

        XCTAssertEqual(counter.repCount, 0)
    }
}

private func counterDefinition(
    movementType: MovementType = .repetition,
    down: PhaseThreshold,
    up: PhaseThreshold,
    holdRange: ClosedRange<Double>? = nil
) -> ExerciseDefinition {
    ExerciseDefinition(
        id: "counterTest",
        displayName: "Counter Test",
        category: .fullBody,
        movementType: movementType,
        cameraPosition: .side,
        setupInstruction: "Test",
        requiredJoints: [],
        visibilityHint: "Test",
        angles: [
            AngleDefinition(
                key: "kneeAngle",
                label: "Knee",
                startJoint: "hip",
                midJoint: "knee",
                endJoint: "ankle",
                side: .right
            )
        ],
        primaryAngleKey: "kneeAngle",
        downThreshold: down,
        upThreshold: up,
        qualityTarget: nil,
        qualityTargetIsMinimum: false,
        formRules: [],
        targetMuscles: [],
        minRepDuration: 0,
        holdAngleRange: holdRange
    )
}
