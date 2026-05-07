import XCTest
@testable import VirtualTrainer

final class CueClusterTaxonomyTests: XCTestCase {
    func testClusterTaxonomySeparatesCueFamilies() {
        let cases: [(input: String, expected: CueCluster)] = [
            ("Keep your front knee steady", .kneeTracking),
            ("Knee is drifting inward", .kneeTracking),
            ("Valgus collapse", .kneeTracking),
            ("Hinge from the hips", .hipHinge),
            ("Push hips back", .hipHinge),
            ("Squeeze glutes at the top", .hipHinge),
            ("Brace your core", .trunkBrace),
            ("Ribs down", .trunkBrace),
            ("Keep your back straight", .trunkBrace),
            ("Straight line from head to heels", .trunkBrace),
            ("Stack shoulders over hands", .shoulderStack),
            ("Relax your traps", .shoulderStack),
            ("Squeeze shoulder blades", .shoulderStack),
            ("Keep elbows at about 45 degrees", .elbowAlign),
            ("Elbows pinned to sides", .elbowAlign),
            ("Maintain a 90-degree elbow bend", .elbowAlign),
            ("Wrists stacked over elbows", .wristNeutral),
            ("Neutral wrist under shoulder", .wristNeutral),
            ("Keep wrists over elbows", .wristNeutral),
            ("Go a bit deeper", .depthRange),
            ("Full range of motion", .depthRange),
            ("Lower until the front knee is close to 90 degrees", .depthRange),
            ("Raise your arms to shoulder height", .depthRange),
            ("Lock it out!", .depthRange),
            ("Lower toward the floor", .other),
            ("Slow and controlled", .tempoControl),
            ("Stop rushing the reps", .tempoControl),
            ("Stay balanced", .balanceStability),
            ("Keep hips level", .balanceStability),
            ("Keep head neutral", .headNeck),
            ("Eyes forward", .headNeck),
            ("Breathe through the rep", .breathing),
            ("Exhale at the top", .breathing),
            ("Keep heels flat", .footPlacement),
            ("Widen your stance", .footPlacement),
            ("Open the feet wider", .footPlacement),
            ("Smile at the camera", .other)
        ]

        for testCase in cases {
            XCTAssertEqual(
                CueClusterTaxonomy.cluster(for: CueNormalizer.normalize(testCase.input)),
                testCase.expected,
                "Expected '\(testCase.input)' to map to \(testCase.expected)"
            )
        }
    }
}
