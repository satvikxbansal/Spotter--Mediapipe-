import XCTest
@testable import VirtualTrainer

final class CueNormalizerTests: XCTestCase {
    func testNormalizeBuildsCanonicalCueKeys() {
        let cases: [(input: String, expected: String)] = [
            ("", ""),
            ("   ", ""),
            ("  Keep your front knee steady  ", "front knee steady"),
            ("KEEP YOUR FRONT KNEE STEADY", "front knee steady"),
            ("Keep   your\tfront\nknee   steady!", "front knee steady"),
            ("The shoulders stay stacked.", "shoulders stay stacked"),
            ("A neutral wrist,", "neutral wrist"),
            ("An upright torso...", "upright torso"),
            ("Your heels flat!", "heels flat"),
            ("Lock your elbows out!!!", "elbows out"),
            ("Drive knees out over toes.", "knees out over toes"),
            ("Keep the chest up.", "chest up"),
            ("the keep your knee", "knee"),
            ("Lower with control", "lower with control"),
            ("Range of motion?", "range of motion"),
            ("Brace first; ", "brace first"),
            ("Stack shoulders over hands:", "stack shoulders over hands"),
            ("  breathe   through   the   rep.  ", "breathe through the rep"),
            ("your", ""),
            ("keep.", ""),
            ("Keep your wrists neutral).", "wrists neutral"),
            ("Drive   your   hips   back...", "hips back"),
            ("A\n\tsteady base!!!", "steady base"),
            ("The   RANGE   of   MOTION!!!", "range of motion"),
            ("Ankle over foot", "ankle over foot"),
            ("a", "")
        ]

        for testCase in cases {
            XCTAssertEqual(
                CueNormalizer.normalize(testCase.input),
                testCase.expected,
                "Expected '\(testCase.input)' to normalize to '\(testCase.expected)'"
            )
        }
    }
}
