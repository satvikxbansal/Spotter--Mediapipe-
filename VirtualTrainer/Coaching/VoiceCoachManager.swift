import Foundation
import Combine

// ────────────────────────────────────────────────────────────────────
// MARK: - VoiceCoachManager
// ────────────────────────────────────────────────────────────────────

/// Placeholder for future voice coaching (TTS rep counts,
/// motivational prompts). Currently a silent no-op so the
/// rest of the codebase can reference it without crashing.
final class VoiceCoachManager: ObservableObject {

    static let shared = VoiceCoachManager()

    @Published var voiceError: String?

    private init() {}

    func prefetchRepCounts(upTo count: Int, personality: CoachPersonality) async {
        // Future: pre-cache TTS audio for rep counts
    }

    func playRep(count: Int) async {
        // Future: speak rep count aloud
    }

    func playMotivation(text: String, personality: CoachPersonality) async {
        // Future: speak motivational message
    }
}
