import XCTest
@testable import VirtualTrainer

final class OnboardingModelTests: XCTestCase {
    func testAgeBracketMapping() {
        XCTAssertEqual(UserProfile.ageBracket(for: 18), .teen)
        XCTAssertEqual(UserProfile.ageBracket(for: 20), .youngAdult)
        XCTAssertEqual(UserProfile.ageBracket(for: 35), .adult)
        XCTAssertEqual(UserProfile.ageBracket(for: 50), .midlife)
        XCTAssertEqual(UserProfile.ageBracket(for: 65), .senior)
    }
}
