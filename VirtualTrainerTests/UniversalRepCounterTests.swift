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

    func testIsometricHoldDurationDoesNotPolluteRepCount() {
        let definition = counterDefinition(
            movementType: .isometric,
            down: PhaseThreshold(angleKey: "kneeAngle", enterBelow: 100, enterAbove: nil),
            up: PhaseThreshold(angleKey: "kneeAngle", enterBelow: nil, enterAbove: 150),
            holdRange: 80...100
        )
        let counter = UniversalRepCounter(definition: definition)

        _ = counter.process(angles: ["kneeAngle": 90])
        Thread.sleep(forTimeInterval: 1.05)
        let holding = counter.process(angles: ["kneeAngle": 90])

        XCTAssertTrue(holding.holdDuration >= 1)
        XCTAssertEqual(holding.repCount, 0)
    }

    func testIsometricHoldPausesWhenPrimaryAngleDropsOut() {
        let definition = counterDefinition(
            movementType: .isometric,
            down: PhaseThreshold(angleKey: "kneeAngle", enterBelow: 100, enterAbove: nil),
            up: PhaseThreshold(angleKey: "kneeAngle", enterBelow: nil, enterAbove: 150),
            holdRange: 80...100
        )
        let counter = UniversalRepCounter(definition: definition)

        _ = counter.process(angles: ["kneeAngle": 90])
        Thread.sleep(forTimeInterval: 1.05)
        let pausedWithoutAngle = counter.process(angles: [:])
        Thread.sleep(forTimeInterval: 0.2)
        let stillPausedWithoutAngle = counter.process(angles: [:])

        XCTAssertTrue(pausedWithoutAngle.holdDuration >= 1)
        XCTAssertLessThan(stillPausedWithoutAngle.holdDuration - pausedWithoutAngle.holdDuration, 0.1)
        XCTAssertEqual(pausedWithoutAngle.repCount, 0)
        XCTAssertFalse(pausedWithoutAngle.isHolding)
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

    func testTrackingLossAbandonsIncompleteRepWithoutClearingCompletedReps() {
        let definition = counterDefinition(
            down: PhaseThreshold(angleKey: "kneeAngle", enterBelow: 150, enterAbove: nil),
            up: PhaseThreshold(angleKey: "kneeAngle", enterBelow: nil, enterAbove: 160)
        )
        let counter = UniversalRepCounter(definition: definition)

        _ = counter.process(angles: ["kneeAngle": 170])
        for _ in 0..<5 {
            _ = counter.process(angles: ["kneeAngle": 120])
        }
        XCTAssertEqual(counter.currentPhase, .down)

        counter.handleTrackingLoss()
        XCTAssertEqual(counter.currentPhase, .idle)
        XCTAssertEqual(counter.repCount, 0)

        _ = counter.process(angles: ["kneeAngle": 190])
        _ = counter.process(angles: ["kneeAngle": 190])
        XCTAssertEqual(counter.repCount, 0)

        for _ in 0..<5 {
            _ = counter.process(angles: ["kneeAngle": 120])
        }

        var output = counter.process(angles: ["kneeAngle": 190])
        for _ in 0..<4 {
            output = counter.process(angles: ["kneeAngle": 190])
        }

        XCTAssertEqual(output.repCount, 1)
    }

    func testRussianTwistMagnitudeCountsEachSideExcursion() {
        let definition = counterDefinition(
            down: PhaseThreshold(angleKey: "trunkTwistMagnitude", enterBelow: nil, enterAbove: 25),
            up: PhaseThreshold(angleKey: "trunkTwistMagnitude", enterBelow: 10, enterAbove: nil),
            primary: "trunkTwistMagnitude"
        )
        let counter = UniversalRepCounter(definition: definition)

        feed(counter, value: 0, frames: 3)
        feed(counter, value: 30, frames: 5)
        feed(counter, value: 0, frames: 5)
        feed(counter, value: 30, frames: 5)
        feed(counter, value: 0, frames: 5)

        XCTAssertEqual(counter.repCount, 2)
    }
}

private func counterDefinition(
    movementType: MovementType = .repetition,
    down: PhaseThreshold,
    up: PhaseThreshold,
    primary: String = "kneeAngle",
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
                key: primary,
                label: "Knee",
                startJoint: "hip",
                midJoint: "knee",
                endJoint: "ankle",
                side: .right
            )
        ],
        primaryAngleKey: primary,
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

private func feed(_ counter: UniversalRepCounter, value: Double, frames: Int) {
    for _ in 0..<frames {
        _ = counter.process(angles: ["trunkTwistMagnitude": value])
    }
}
