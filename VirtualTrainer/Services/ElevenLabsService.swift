import Foundation

// ────────────────────────────────────────────────────────────────────
// MARK: - ElevenLabsService
// ────────────────────────────────────────────────────────────────────

/// Thin networking layer for the ElevenLabs text-to-speech REST API.
///
/// Returns raw MPEG audio `Data` that can be fed directly into
/// `AVAudioPlayer(data:)`.
///
/// The service is intentionally stateless — caching and playback
/// are handled by `VoiceCoachManager`.
///
/// Opted out of the project-wide `@MainActor` default — network
/// requests must be free to run on any executor.
nonisolated final class ElevenLabsService: Sendable {

    static let shared = ElevenLabsService()

    // MARK: - Configuration

    private let baseURL = "https://api.elevenlabs.io/v1/text-to-speech"

    /// Replace with your actual ElevenLabs API key.
    /// In production, load from Keychain or a secure config — never ship in source.
    private let apiKey = "sk_78ebb615180b759740ad51b08e8a950b3b9dfee9e0e90935"

    /// Turbo v2 gives the lowest latency for real-time coaching.
    private let modelID = "eleven_turbo_v2_5"

    // MARK: - Errors

    enum ServiceError: LocalizedError {
        case badURL
        case httpError(statusCode: Int)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .badURL:
                "Invalid ElevenLabs URL."
            case .httpError(let code):
                "ElevenLabs returned HTTP \(code)."
            case .emptyResponse:
                "ElevenLabs returned empty audio data."
            }
        }
    }

    // MARK: - Public API

    /// Calls the ElevenLabs TTS endpoint and returns raw MPEG audio bytes.
    ///
    /// - Parameters:
    ///   - text: The phrase to synthesize (e.g. "3", "Keep pushing!").
    ///   - voiceId: An ElevenLabs voice ID string.
    /// - Returns: Audio `Data` suitable for `AVAudioPlayer(data:)`.
    func fetchAudio(for text: String, voiceId: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/\(voiceId)") else {
            throw ServiceError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelID,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ServiceError.httpError(statusCode: http.statusCode)
        }

        guard !data.isEmpty else {
            throw ServiceError.emptyResponse
        }

        return data
    }
}
