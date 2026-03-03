import Foundation
import Combine

// ────────────────────────────────────────────────────────────────────
// MARK: - MotivationEngine
// ────────────────────────────────────────────────────────────────────

/// Kinematic-signal processor that detects fatigue from rep tempo
/// decay and fires motivational pushes when the user is struggling.
///
/// ## Detection Model
///
/// ```
/// ┌─────────────────────────────────────────────────────────────┐
/// │  Rep 1 ──── Rep 2 ──── Rep 3 ──── Rep 4 ──── Rep 5        │
/// │   t=0s       t=3s       t=3.2s     t=4.8s     t=5.1s      │
/// │                                                            │
/// │  Baseline = avg(rep1→2, rep2→3) = 3.1s                     │
/// │  Rep 4→5 gap = 5.1s  →  64% slower than baseline  →  FIRE │
/// └─────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Personality
///
/// Supports two coaching styles selected by the user:
///   - **Good Coach**: warm, supportive encouragement
///   - **Drill Sergeant**: brutal, condescending trash-talk
///
/// ## Rate Limiting
///
/// At most one motivational push every `cooldownInterval` seconds
/// to keep encouragement punchy, not nagging.
final class MotivationEngine: ObservableObject {

    // MARK: - Published State

    @Published private(set) var activeMessage: String?

    // MARK: - Personality

    var personality: CoachPersonality = .good

    // MARK: - Configuration

    private let tempoDecayThreshold: Double = 0.40
    private let cooldownInterval: TimeInterval = 15.0
    private let displayDuration: TimeInterval = 3.5

    // MARK: - Internal State

    private(set) var repTimestamps: [Date] = []
    private var lastMotivationTime: Date?
    private var lastPhraseIndex: Int?
    private var dismissWorkItem: DispatchWorkItem?

    // MARK: - Phrase Pools

    private let goodPhrases: [String] = [
        "Stay tight! Push through it!",
        "Breathe! You got this!",
        "One more — make it count!",
        "That bar isn't gonna lift itself!",
        "Dig deep, champion!",
        "Pain is just weakness leaving!",
        "You didn't come this far to quit!",
        "Lock in — this is your set!",
        "Strong legs, strong mind!",
        "Eyes up, chest proud — finish it!",
        "Your future self is watching!",
        "This is where champions are made!",
    ]

    private let drillPhrases: [String] = [
        "Get moving you lazy sack of shit!",
        "My grandma squats heavier than that!",
        "Someone else is out-working you right now!",
        "You call that a rep? Pathetic!",
        "Stop resting, your ex is watching!",
        "That was embarrassing. Do it again!",
        "You're softer than a marshmallow. PUSH!",
        "Quit whining and finish the damn set!",
        "Is that all you've got? Weak!",
        "Pain? That's just your excuses crying!",
        "Move it! Nobody cares about your feelings!",
        "You paid for this gym, now USE it!",
        "While you rest someone's hitting on your girl. MOVE!",
        "You want a body or a participation trophy?",
        "Get your ass down lower!",
        "Absolutely disgusting effort. Again!",
    ]

    private var activePhrases: [String] {
        switch personality {
        case .good:  goodPhrases
        case .drill: drillPhrases
        }
    }

    // MARK: - Public API

    @discardableResult
    func evaluateEffort(
        currentRepCount: Int,
        faceEffortScore: Double = 0
    ) -> String? {
        let now = Date()
        repTimestamps.append(now)

        guard let message = checkTempo(at: now) else { return nil }

        publishMessage(message)
        return message
    }

    func reset() {
        repTimestamps.removeAll()
        lastMotivationTime = nil
        lastPhraseIndex = nil
        dismissWorkItem?.cancel()
        activeMessage = nil
    }

    // MARK: - Tempo Analysis

    private func checkTempo(at now: Date) -> String? {
        let count = repTimestamps.count

        guard count >= 4 else { return nil }

        let gap1 = repTimestamps[1].timeIntervalSince(repTimestamps[0])
        let gap2 = repTimestamps[2].timeIntervalSince(repTimestamps[1])
        let baseline = (gap1 + gap2) / 2.0

        guard baseline > 0 else { return nil }

        let latestGap = repTimestamps[count - 1]
            .timeIntervalSince(repTimestamps[count - 2])
        let decayRatio = (latestGap - baseline) / baseline

        guard decayRatio > tempoDecayThreshold else { return nil }

        if let last = lastMotivationTime,
           now.timeIntervalSince(last) < cooldownInterval {
            return nil
        }

        lastMotivationTime = now
        return nextPhrase()
    }

    // MARK: - Phrase Selection

    private func nextPhrase() -> String {
        let pool = activePhrases
        var index: Int
        if let last = lastPhraseIndex {
            index = (last + 1) % pool.count
        } else {
            index = Int.random(in: 0..<pool.count)
        }
        lastPhraseIndex = index
        return pool[index]
    }

    // MARK: - Display Lifecycle

    private func publishMessage(_ message: String) {
        dismissWorkItem?.cancel()

        activeMessage = message
        HapticsEngine.shared.warningPulse()

        let currentPersonality = personality
        Task {
            await VoiceCoachManager.shared.playMotivation(
                text: message,
                personality: currentPersonality
            )
        }

        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.activeMessage = nil
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: work)
    }
}
