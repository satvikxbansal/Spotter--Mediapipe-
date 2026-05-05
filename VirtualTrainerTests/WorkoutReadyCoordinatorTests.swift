import XCTest
@testable import VirtualTrainer

final class WorkoutReadyCoordinatorTests: XCTestCase {
    func testBodyLostCancelsCountdownBeforeActivation() {
        let coordinator = WorkoutReadyCoordinator()

        coordinator.bodyIsVisible()
        coordinator.thumbsUpDetected()

        guard case .countdown = coordinator.state else {
            return XCTFail("Expected countdown after thumbs up")
        }

        coordinator.bodyLost()

        XCTAssertEqual(coordinator.state, .positioning)
    }

    func testBodyLostCancelsRetryWaitBeforeAskingAgain() {
        let coordinator = WorkoutReadyCoordinator()

        coordinator.bodyIsVisible()
        coordinator.thumbsDownDetected()

        guard case .waitingToRetry = coordinator.state else {
            return XCTFail("Expected retry wait after thumbs down")
        }

        coordinator.bodyLost()

        XCTAssertEqual(coordinator.state, .positioning)
    }

    func testHeldThumbsUpStartsCountdownWhenBodyBecomesVisible() {
        let coordinator = WorkoutReadyCoordinator()

        coordinator.bodyIsVisible(currentGesture: .thumbsUp)

        guard case .countdown = coordinator.state else {
            return XCTFail("Expected held thumbs up to start countdown")
        }
    }

    func testHeldThumbsDownStartsRetryWhenBodyBecomesVisible() {
        let coordinator = WorkoutReadyCoordinator()

        coordinator.bodyIsVisible(currentGesture: .thumbsDown)

        guard case .waitingToRetry = coordinator.state else {
            return XCTFail("Expected held thumbs down to start retry wait")
        }
    }
}
