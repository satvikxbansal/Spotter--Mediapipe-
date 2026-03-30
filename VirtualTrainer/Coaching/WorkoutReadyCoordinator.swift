import Foundation
import Combine

// ────────────────────────────────────────────────────────────────────
// MARK: - Workout Ready State
// ────────────────────────────────────────────────────────────────────

/// The phases of the "are you ready?" flow before an exercise begins.
enum WorkoutReadyState: Equatable {
    /// Waiting for the user to position themselves.
    case positioning

    /// Coach is asking "Are you ready?" — waiting for thumbs up/down.
    case askingReady

    /// User gave thumbs up — counting down (3, 2, 1…).
    case countdown(secondsLeft: Int)

    /// User gave thumbs down — waiting before asking again.
    case waitingToRetry(secondsLeft: Int)

    /// Countdown finished — exercise is live.
    case exerciseActive

    /// User-facing prompt text.
    var displayMessage: String {
        switch self {
        case .positioning:
            return "Get into position"
        case .askingReady:
            return "Are you ready? 👍 to start"
        case .countdown(let seconds):
            return "\(seconds)"
        case .waitingToRetry(let seconds):
            return "No worries! Asking again in \(seconds)…"
        case .exerciseActive:
            return ""
        }
    }

    /// Secondary instruction text.
    var subtitle: String? {
        switch self {
        case .positioning:
            return "Make sure the camera can see your full body"
        case .askingReady:
            return "Give a thumbs up when you're ready, thumbs down if you need more time"
        case .countdown:
            return "Get set!"
        case .waitingToRetry:
            return "Take your time"
        case .exerciseActive:
            return nil
        }
    }
}

// ────────────────────────────────────────────────────────────────────
// MARK: - WorkoutReadyCoordinator
// ────────────────────────────────────────────────────────────────────

/// Orchestrates the pre-exercise ready-check flow:
///
/// ```
///  positioning
///      │ (body visible)
///      ▼
///  askingReady ◄────────────┐
///      │                    │
///      ├── 👍 thumbs up     │
///      │      │             │
///      │      ▼             │
///      │  countdown(3)      │
///      │  countdown(2)      │
///      │  countdown(1)      │
///      │      │             │
///      │      ▼             │
///      │  exerciseActive    │
///      │                    │
///      └── 👎 thumbs down   │
///             │             │
///             ▼             │
///         waitingToRetry(3) │
///         waitingToRetry(2) │
///         waitingToRetry(1) │
///             └─────────────┘
/// ```
///
/// ## Coach Personality Integration
///
/// The messages adapt to the selected coach personality:
///   - **Good Coach**: warm, encouraging prompts
///   - **Drill Sergeant**: impatient, aggressive prompts
final class WorkoutReadyCoordinator: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: WorkoutReadyState = .positioning
    @Published private(set) var coachMessage: String = ""

    // MARK: - Configuration

    private let countdownDuration: Int = 3
    private let retryWaitDuration: Int = 3

    /// How many times the user has declined (thumbs down).
    private var declineCount: Int = 0

    private var personality: CoachPersonality
    private var countdownTimer: Timer?
    private var countdownValue: Int = 0

    // MARK: - Ready Check Messages

    private let goodReadyMessages = [
        "Alright! Are you ready to crush this? Give me a thumbs up!",
        "Let's do this! Thumbs up when you're set!",
        "Looking good! Ready to go? Show me a thumbs up!",
        "Time to work! Thumbs up when you're ready, champ!",
    ]

    private let drillReadyMessages = [
        "Are you ready or are you just standing there? THUMBS UP!",
        "I don't have all day. Thumbs up. NOW.",
        "You better be ready. Thumbs up or get out.",
        "Stop wasting time. Thumbs up if you've got the guts.",
    ]

    private let goodCountdownMessages = [
        "Here we go!",
        "Let's get it!",
        "You've got this!",
    ]

    private let drillCountdownMessages = [
        "No backing out now!",
        "Pain is coming!",
        "Time to suffer!",
    ]

    private let goodDeclineMessages = [
        "No rush! Take your time.",
        "All good — get comfortable first!",
        "Whenever you're ready, no pressure!",
    ]

    private let drillDeclineMessages = [
        "Scared already? Fine, take a moment.",
        "Even my grandmother would be ready by now.",
        "You're stalling. I'll ask again.",
    ]

    private let goodRetryMessages = [
        "Okay, let's try this again! Thumbs up?",
        "Ready now? Show me that thumbs up!",
        "Take two! Are you ready this time?",
    ]

    private let drillRetryMessages = [
        "Back again. Thumbs up or I'm leaving.",
        "Last chance. Are you READY?",
        "I SAID thumbs up. Do it.",
    ]

    // MARK: - Init

    init(personality: CoachPersonality = .good) {
        self.personality = personality
        coachMessage = ""
    }

    // MARK: - Public API

    /// Call when the body becomes fully visible in camera.
    func bodyIsVisible() {
        guard state == .positioning else { return }
        transitionTo(.askingReady)
    }

    /// Call when the body is no longer visible.
    func bodyLost() {
        // Only go back to positioning if we haven't started yet
        guard state == .askingReady else { return }
        transitionTo(.positioning)
    }

    /// Call when a thumbs-up gesture is confirmed.
    func thumbsUpDetected() {
        guard state == .askingReady else { return }
        startCountdown()
    }

    /// Call when a thumbs-down gesture is confirmed.
    func thumbsDownDetected() {
        guard state == .askingReady else { return }
        declineCount += 1
        startRetryWait()
    }

    /// Update the coach personality (call before starting).
    func setPersonality(_ personality: CoachPersonality) {
        self.personality = personality
    }

    /// Reset everything (call when leaving the workout screen).
    func reset() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownValue = 0
        declineCount = 0
        state = .positioning
        coachMessage = ""
    }

    // MARK: - State Transitions

    private func transitionTo(_ newState: WorkoutReadyState) {
        state = newState

        switch newState {
        case .positioning:
            coachMessage = ""

        case .askingReady:
            if declineCount > 0 {
                coachMessage = randomMessage(
                    good: goodRetryMessages,
                    drill: drillRetryMessages
                )
            } else {
                coachMessage = randomMessage(
                    good: goodReadyMessages,
                    drill: drillReadyMessages
                )
            }

        case .countdown(let seconds):
            if seconds == countdownDuration {
                coachMessage = randomMessage(
                    good: goodCountdownMessages,
                    drill: drillCountdownMessages
                )
            }

        case .waitingToRetry(let seconds):
            if seconds == retryWaitDuration {
                coachMessage = randomMessage(
                    good: goodDeclineMessages,
                    drill: drillDeclineMessages
                )
            }

        case .exerciseActive:
            coachMessage = ""
            HapticsEngine.shared.successRipple()
        }
    }

    // MARK: - Countdown

    private func startCountdown() {
        countdownValue = countdownDuration
        transitionTo(.countdown(secondsLeft: countdownValue))
        HapticsEngine.shared.repTick()

        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            self.countdownValue -= 1

            if self.countdownValue > 0 {
                self.transitionTo(.countdown(secondsLeft: self.countdownValue))
                HapticsEngine.shared.repTick()
            } else {
                timer.invalidate()
                self.countdownTimer = nil
                self.transitionTo(.exerciseActive)
            }
        }
    }

    // MARK: - Retry Wait

    private func startRetryWait() {
        countdownValue = retryWaitDuration
        transitionTo(.waitingToRetry(secondsLeft: countdownValue))

        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            self.countdownValue -= 1

            if self.countdownValue > 0 {
                self.transitionTo(.waitingToRetry(secondsLeft: self.countdownValue))
            } else {
                timer.invalidate()
                self.countdownTimer = nil
                self.transitionTo(.askingReady)
            }
        }
    }

    // MARK: - Helpers

    private func randomMessage(good: [String], drill: [String]) -> String {
        let pool = personality == .good ? good : drill
        return pool.randomElement() ?? pool[0]
    }
}
