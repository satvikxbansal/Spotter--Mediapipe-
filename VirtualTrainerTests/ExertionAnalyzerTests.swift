import XCTest
@testable import VirtualTrainer

final class ExertionAnalyzerTests: XCTestCase {
    func testMissingJawOpenDoesNotCreateFalseClenchEffort() {
        let analyzer = ExertionAnalyzer()

        analyzer.update(blendshapes: ["browDownLeft": 0])

        XCTAssertLessThan(analyzer.effortScore, 0.01)
    }

    func testPresentBlendshapesUseOnlyAvailableWeights() {
        let analyzer = ExertionAnalyzer()

        analyzer.update(blendshapes: ["mouthFunnel": 0.8])

        XCTAssertGreaterThan(analyzer.effortScore, 0.1)
    }
}
