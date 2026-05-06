import XCTest
import CoreGraphics
@testable import VirtualTrainer

final class VisibilityAndExerciseInvariantTests: XCTestCase {
    func testBodyVisibilityRequiresExerciseJoints() {
        let result = BodyVisibilityChecker.evaluate(joints: [:], for: .squat)
        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.visibility, 0)
        XCTAssertFalse(result.missingJoints.isEmpty)
    }

    func testFrameAnalyzerFlagsTooCloseMask() {
        let mask = SegmentationMaskData(width: 10, height: 10, data: Array(repeating: Float(1), count: 100))
        let result = FramePositionAnalyzer.analyze(mask)
        XCTAssertEqual(result?.guidance, .bodyClipped(edges: [.top, .bottom, .left, .right]))
    }

    func testFrameAnalyzerRejectsMalformedMaskDataWithoutCrashing() {
        let mask = SegmentationMaskData(width: 10, height: 10, data: Array(repeating: Float(1), count: 20))
        XCTAssertNil(FramePositionAnalyzer.analyze(mask))
    }

    func testFrameAnalyzerHandlesSinglePixelMaskWithoutInvalidCentroid() throws {
        let mask = SegmentationMaskData(width: 1, height: 1, data: [1])
        let result = try XCTUnwrap(FramePositionAnalyzer.analyze(mask))
        XCTAssertTrue(result.centroid.x.isFinite)
        XCTAssertTrue(result.centroid.y.isFinite)
    }

    func testEveryExerciseTypeHasDefinition() {
        for type in ExerciseType.allCases {
            XCTAssertNotNil(type.definition, "\(type.rawValue) is missing an ExerciseLibrary definition")
        }
    }

    func testExerciseDefinitionsHaveConsistentPrimaryAnglesAndThresholds() {
        for definition in ExerciseLibrary.all {
            let angleKeys = Set(definition.angles.map(\.key))
            XCTAssertTrue(angleKeys.contains(definition.primaryAngleKey), "\(definition.id) primary angle is not defined")
            XCTAssertEqual(definition.downThreshold.angleKey, definition.primaryAngleKey, "\(definition.id) down threshold should use primary angle")
            XCTAssertEqual(definition.upThreshold.angleKey, definition.primaryAngleKey, "\(definition.id) up threshold should use primary angle")

            for rule in definition.formRules {
                XCTAssertTrue(angleKeys.contains(rule.angleKey), "\(definition.id) rule \(rule.id) references missing angle \(rule.angleKey)")
                if let min = rule.minAngle {
                    XCTAssertGreaterThanOrEqual(min, 0, "\(definition.id) rule \(rule.id) has invalid min angle")
                }
                if let max = rule.maxAngle, rule.angleKey != "bodyLineAngle" {
                    XCTAssertLessThanOrEqual(max, 180, "\(definition.id) rule \(rule.id) has impossible max angle")
                }
            }
        }
    }

    func testSelectableCategoryOptionsMapToDefinitions() {
        for category in BodyCategory.allCases {
            for option in category.exercises where option.available {
                XCTAssertNotNil(option.type?.definition, "\(option.name) is available but has no definition")
            }
        }
    }
}
