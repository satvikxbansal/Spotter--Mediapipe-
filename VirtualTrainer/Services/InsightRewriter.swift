import Foundation

nonisolated struct RewriteResult: Codable, Equatable {
    let headline: String?
    let message: String?
    let shortMessage: String?

    init(
        headline: String? = nil,
        message: String? = nil,
        shortMessage: String? = nil
    ) {
        self.headline = headline
        self.message = message
        self.shortMessage = shortMessage
    }
}

nonisolated protocol InsightRewriter {
    func rewrite(_ context: InsightLLMContext) async throws -> RewriteResult?
}

nonisolated struct NoopInsightRewriter: InsightRewriter {
    func rewrite(_ context: InsightLLMContext) async throws -> RewriteResult? {
        nil
    }
}

nonisolated struct RewriteValidator {
    func sanitized(_ result: RewriteResult) -> RewriteResult {
        RewriteResult(
            headline: sanitizedField(result.headline),
            message: sanitizedField(result.message),
            shortMessage: sanitizedField(result.shortMessage)
        )
    }

    func canAdopt(
        _ proposedInsight: AIInsight,
        replacing originalInsight: AIInsight,
        context: InsightLLMContext
    ) -> Bool {
        hasRewriteChange(proposedInsight, from: originalInsight) &&
            coversExercise(proposedInsight, context: context) &&
            coversRecommendedAction(proposedInsight, context: context) &&
            coversEvidenceFact(proposedInsight, originalInsight: originalInsight)
    }

    private func sanitizedField(_ field: String?) -> String? {
        guard let field else { return nil }
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let sanitized = InsightTextSanitizer.sanitize(trimmed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }

    private func hasRewriteChange(_ proposedInsight: AIInsight, from originalInsight: AIInsight) -> Bool {
        proposedInsight.headline != originalInsight.headline ||
            proposedInsight.message != originalInsight.message ||
            proposedInsight.shortMessage != originalInsight.shortMessage
    }

    private func coversExercise(_ insight: AIInsight, context: InsightLLMContext) -> Bool {
        guard let exercise = context.exerciseDisplayName else { return true }
        let textTokens = Set(tokens(in: combinedText(for: insight)))
        let exerciseTokens = tokens(in: exercise)
            .filter { $0.count >= 3 }
            .flatMap { [$0, singularized($0)] }
        return exerciseTokens.contains { textTokens.contains($0) }
    }

    private func coversRecommendedAction(_ insight: AIInsight, context: InsightLLMContext) -> Bool {
        let textTokens = Set(tokens(in: combinedText(for: insight)))
        return actionTerms(for: context.action).contains { textTokens.contains($0) }
    }

    private func coversEvidenceFact(
        _ insight: AIInsight,
        originalInsight: AIInsight
    ) -> Bool {
        let normalizedText = normalized(combinedText(for: insight))
        return evidenceAnchors(for: originalInsight).contains { anchor in
            let normalizedAnchor = normalized(anchor)
            return !normalizedAnchor.isEmpty && normalizedText.contains(normalizedAnchor)
        }
    }

    private func combinedText(for insight: AIInsight) -> String {
        "\(insight.headline) \(insight.message) \(insight.shortMessage)"
    }

    private func actionTerms(for action: InsightAction) -> [String] {
        switch action {
        case .continuePlan:
            return ["continue", "keep", "steady", "protect"]
        case .repeatTarget:
            return ["repeat", "hold", "same"]
        case .increaseTarget:
            return ["increase", "add", "progress"]
        case .decreaseTarget:
            return ["decrease", "lower", "pull"]
        case .increaseRest:
            return ["increase", "add", "rest"]
        case .reduceRest:
            return ["reduce", "trim", "cut"]
        case .swapExerciseLater:
            return ["swap", "replace"]
        case .useEasierVariant:
            return ["use", "easier", "start", "incline"]
        case .useHarderVariant:
            return ["use", "harder", "try"]
        case .focusCue:
            return ["focus", "cue", "make"]
        case .takeMobilityDay:
            return ["mobility", "recover"]
        case .protectStreakWithSmartStart:
            return ["protect", "smart", "start"]
        case .celebrate:
            return ["celebrate", "earned"]
        case .noActionNeeded:
            return ["keep"]
        }
    }

    private func evidenceAnchors(for insight: AIInsight) -> [String] {
        insight.evidence.flatMap { evidence in
            [
                evidence.value,
                evidence.comparison,
                evidence.repIndex.map { "rep \($0)" },
                evidence.setIndex.map { "set \($0)" },
                evidence.setIndex.map { "set \($0 + 1)" }
            ].compactMap { $0 }
        }
    }

    private func tokens(in text: String) -> [String] {
        normalized(text).split(separator: " ").map(String.init)
    }

    private func normalized(_ text: String) -> String {
        let mapped = text.lowercased().map { character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(mapped)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func singularized(_ token: String) -> String {
        guard token.count > 3, token.hasSuffix("s") else { return token }
        return String(token.dropLast())
    }
}

nonisolated extension AIInsight {
    func applyingRewrite(_ result: RewriteResult) -> AIInsight {
        AIInsight(
            id: id,
            type: type,
            headline: result.headline ?? headline,
            message: result.message ?? message,
            shortMessage: result.shortMessage ?? shortMessage,
            evidence: evidence,
            recommendedAction: recommendedAction,
            severity: severity,
            emotionalIntent: emotionalIntent,
            userValueScore: userValueScore,
            confidence: confidence,
            surfaces: surfaces,
            relatedExerciseType: relatedExerciseType,
            relatedGoal: relatedGoal,
            createdAt: createdAt,
            sourcePolicyVersion: sourcePolicyVersion,
            expiresAt: expiresAt,
            dedupeKey: dedupeKey
        )
    }
}
