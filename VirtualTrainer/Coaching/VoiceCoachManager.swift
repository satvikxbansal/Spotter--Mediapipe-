import Foundation
import Combine
import AVFoundation

// ────────────────────────────────────────────────────────────────────
// MARK: - VoiceCoachManager
// ────────────────────────────────────────────────────────────────────

/// Local baseline voice coaching for rep counts and motivation.
///
/// The API intentionally stays stable so remote TTS (for example
/// ElevenLabs) can be added later behind the same non-fatal surface.
@MainActor
final class VoiceCoachManager: ObservableObject {

    static let shared = VoiceCoachManager()

    @Published var voiceError: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var repPhrases: [Int: AVSpeechUtterance] = [:]
    private var lastCueSpokenAt: [String: Date] = [:]

    private init() {}

    func prefetchRepCounts(upTo count: Int, personality: CoachPersonality) {
        repPhrases = Dictionary(uniqueKeysWithValues: (1...count).map { value in
            (value, makeUtterance(text: "\(value)", personality: personality, kind: .repCount))
        })
    }

    func playRep(count: Int) {
        speak(repPhrases[count] ?? makeUtterance(text: "\(count)", personality: .good, kind: .repCount))
    }

    func playMotivation(text: String, personality: CoachPersonality) {
        speak(makeUtterance(text: text, personality: personality, kind: .motivation), interrupts: true)
    }

    func playCue(_ cue: CoachCue, personality: CoachPersonality) {
        let now = Date()
        if let lastSpoken = lastCueSpokenAt[cue.message],
           now.timeIntervalSince(lastSpoken) < cue.cooldownSeconds {
            return
        }

        lastCueSpokenAt[cue.message] = now
        speak(makeUtterance(text: cue.message, personality: personality, kind: .cue), interrupts: cue.severity >= .warning)
    }

    private enum UtteranceKind {
        case repCount
        case motivation
        case cue
    }

    private func speak(_ utterance: AVSpeechUtterance, interrupts: Bool = false) {
        if interrupts, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        } else if synthesizer.isSpeaking {
            return
        }

        voiceError = nil
        synthesizer.speak(utterance)
    }

    private func makeUtterance(
        text: String,
        personality: CoachPersonality,
        kind: UtteranceKind
    ) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        switch (personality, kind) {
        case (.drill, .repCount):
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.08
            utterance.pitchMultiplier = 0.9
            utterance.volume = 0.85
        case (.drill, _):
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
            utterance.pitchMultiplier = 0.85
            utterance.volume = 0.95
        case (.good, .repCount):
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0
            utterance.volume = 0.75
        case (.good, _):
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            utterance.pitchMultiplier = 1.05
            utterance.volume = 0.85
        }

        return utterance
    }
}
