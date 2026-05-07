import Foundation

nonisolated enum CueNormalizer {
    private static let leadingTokens: Set<String> = [
        "the",
        "a",
        "an",
        "your",
        "keep",
        "lock",
        "drive"
    ]

    static func normalize(_ cue: String) -> String {
        var normalized = cue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        while let lastScalar = normalized.unicodeScalars.last,
              CharacterSet.punctuationCharacters.contains(lastScalar) {
            normalized.removeLast()
        }

        let tokens = normalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)

        let canonicalTokens = Array(tokens.drop(while: { leadingTokens.contains($0) }))
        return canonicalTokens.joined(separator: " ")
    }
}
