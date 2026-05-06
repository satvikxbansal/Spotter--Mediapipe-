import Foundation

nonisolated struct InsightNarrativeBuilder {
    func buildInsight(
        from candidate: InsightCandidate,
        userValueScore: Double,
        surface: InsightSurface,
        createdAt: Date? = nil
    ) -> AIInsight {
        let resolvedCreatedAt = createdAt ?? candidate.createdAt
        let headline = sanitize(candidate.candidateHeadline)
        let fullMessage = sanitize(message(for: candidate))
        let shortMessage = sanitize(shortMessage(for: candidate))
        let surfaceMessage = surface == .dashboard ? shortMessage : fullMessage

        return AIInsight(
            type: candidate.type,
            headline: headline,
            message: surfaceMessage,
            shortMessage: shortMessage,
            evidence: candidate.evidence,
            recommendedAction: candidate.candidateAction,
            severity: candidate.severity,
            emotionalIntent: candidate.emotionalIntent,
            userValueScore: userValueScore,
            confidence: candidate.confidence,
            surfaces: candidate.surfaces,
            relatedExerciseType: candidate.relatedExerciseType,
            relatedGoal: candidate.relatedGoal,
            createdAt: resolvedCreatedAt,
            expiresAt: candidate.expiresAt,
            dedupeKey: candidate.dedupeKey
        )
    }
}

nonisolated private extension InsightNarrativeBuilder {
    func message(for candidate: InsightCandidate) -> String {
        switch candidate.type {
        case .formCorrection:
            return formCorrectionMessage(candidate)
        case .growthCelebration:
            return growthMessage(candidate)
        case .planAdjustment:
            return planAdjustmentMessage(candidate)
        case .recovery:
            return recoveryMessage(candidate)
        case .safety:
            return safetyMessage(candidate)
        case .trophyProgress:
            return trophyMessage(candidate)
        case .consistency:
            return consistencyMessage(candidate)
        case .planSpecific:
            return planSpecificMessage(candidate)
        case .workoutSpecific:
            return workoutSpecificMessage(candidate)
        case .dayOverDayTrend:
            return dayOverDayMessage(candidate)
        }
    }

    func shortMessage(for candidate: InsightCandidate) -> String {
        let exercise = candidate.context["exercise"]?.nilIfEmpty ?? candidate.relatedExerciseType?.displayName
        let value = candidate.context["value"]?.nilIfEmpty ?? candidate.evidence.first?.value
        let cue = candidate.context["cue"]?.nilIfEmpty

        switch candidate.type {
        case .formCorrection:
            if let exercise, let rep = candidate.context["breakdownRep"]?.nilIfEmpty {
                return "\(exercise) form dropped after rep \(rep). \(shortAction(candidate.candidateAction, exercise: exercise))"
            }
            if let cue {
                return "Cue focus: \(cue). Use it before adding reps."
            }
            return "\(exercise ?? "Form") needs a tighter target next time."
        case .growthCelebration:
            if let exercise, let rep = candidate.context["improvementRep"]?.nilIfEmpty {
                return "\(exercise) stabilized after rep \(rep). Progress stays earned."
            }
            return "\(exercise ?? "Form") is trending cleaner. Keep the quality bar."
        case .recovery:
            if candidate.context["signalType"] == TrainingSignalType.fatigue.rawValue {
                return "Recent strain signals are up. Keep the next plan short and clean."
            }
            return "\(exercise ?? "Volume") needs more recovery room today."
        case .safety:
            return "\(exercise ?? "Today") stays conservative around your saved limits."
        case .trophyProgress:
            let trophy = candidate.context["trophy"]?.nilIfEmpty ?? "A trophy"
            let remaining = candidate.context["remaining"]?.nilIfEmpty
            let unit = candidate.context["unit"]?.nilIfEmpty ?? "units"
            if let remaining {
                return "\(trophy): \(remaining) \(unit) to go."
            }
            return "\(trophy) is within reach."
        case .consistency:
            return "\(value ?? "Consistency is building"). Keep today's plan clean."
        case .planSpecific:
            return planSpecificShortMessage(candidate)
        case .planAdjustment:
            return "\(exercise ?? "Next target") should adjust from today's evidence."
        case .workoutSpecific:
            return "\(exercise ?? "Today's session") gave the next plan a clear signal."
        case .dayOverDayTrend:
            return "\(value ?? "Recent training") is the story. Match volume to quality."
        }
    }

    func formCorrectionMessage(_ candidate: InsightCandidate) -> String {
        let exercise = candidate.context["exercise"]?.nilIfEmpty ?? "This movement"
        let setText = candidate.context["setText"]?.nilIfEmpty ?? "the set"
        let cue = candidate.context["cue"]?.nilIfEmpty

        if let rep = candidate.context["breakdownRep"]?.nilIfEmpty {
            let cueText = cue.map { " The focus cue is: \($0)." } ?? ""
            return "\(exercise) form dropped after rep \(rep) in \(setText).\(cueText) Because quality changed late, next time \(actionPhrase(candidate.candidateAction, exercise: exercise))"
        }

        if let cue {
            let count = candidate.context["count"]?.nilIfEmpty ?? "multiple"
            return "The cue \"\(cue)\" showed up \(count) times around \(exercise). Because it repeated, next session should make that the first focus before target or tempo increases."
        }

        return "\(exercise) showed repeated form friction. Because the signal is about quality, next time \(actionPhrase(candidate.candidateAction, exercise: exercise))"
    }

    func growthMessage(_ candidate: InsightCandidate) -> String {
        let exercise = candidate.context["exercise"]?.nilIfEmpty ?? "This movement"
        let setText = candidate.context["setText"]?.nilIfEmpty ?? "the set"

        if let rep = candidate.context["improvementRep"]?.nilIfEmpty {
            return "Your \(exercise) form improved after rep \(rep) and held through \(setText). Because control stabilized, the next plan can \(actionPhrase(candidate.candidateAction, exercise: exercise))"
        }

        if let value = candidate.context["value"]?.nilIfEmpty,
           let comparison = candidate.context["comparison"]?.nilIfEmpty {
            return "\(exercise) is moving better: \(value) against \(comparison). Because that growth is backed by recent sessions, Spotter should keep the movement and progress only while form holds."
        }

        return "\(exercise) is becoming a stronger movement. Because quality is trending up, Spotter should keep it in the rotation and progress gradually."
    }

    func planAdjustmentMessage(_ candidate: InsightCandidate) -> String {
        let exercise = candidate.context["exercise"]?.nilIfEmpty ?? "This target"
        let completion = candidate.context["completion"]?.nilIfEmpty
        let form = candidate.context["form"]?.nilIfEmpty
        let count = candidate.context["count"]?.nilIfEmpty

        if let completion, let form {
            return "You finished \(completion) of the plan with \(form) average form. Because completion and quality were both high, the next block can \(actionPhrase(candidate.candidateAction, exercise: exercise, targetUnit: candidate.context["targetUnit"]))"
        }

        if let count {
            return "\(exercise) had \(count) skipped set\(count == "1" ? "" : "s"). Because skipped work is a signal, not a failure, repeat the target before adding volume."
        }

        return "\(exercise) gave enough evidence to adjust the next target. Because the goal is clean progress, \(actionPhrase(candidate.candidateAction, exercise: exercise))"
    }

    func recoveryMessage(_ candidate: InsightCandidate) -> String {
        let exercise = candidate.context["exercise"]?.nilIfEmpty ?? "This session"
        let count = candidate.context["count"]?.nilIfEmpty ?? candidate.evidence.first?.value

        if candidate.context["signalType"] == TrainingSignalType.fatigue.rawValue {
            return "Recent sessions show higher late-session strain signals. Because quality matters more than chasing volume, keep the next block short and lower the target if form fades."
        }

        if let count {
            return "Rest extended \(count) around \(exercise). Because recovery demand rose, next time add rest or trim volume before form quality breaks."
        }

        return "\(exercise) is showing higher late-session strain signals. Because form matters more than chasing volume, keep the next block short and sharp."
    }

    func safetyMessage(_ candidate: InsightCandidate) -> String {
        let exercise = candidate.context["exercise"]?.nilIfEmpty ?? "This plan"
        let limitations = candidate.context["limitations"]?.nilIfEmpty ?? "your saved limitations"

        if candidate.candidateAction == .swapExerciseLater {
            return "\(exercise) overlaps with \(limitations). Because saved limits matter, swap to an easier variant before starting instead of forcing the planned target."
        }

        return "Today stays conservative around \(limitations), with \(exercise) as a supported option. Because the goal is durable progress, keep the plan and let clean reps decide progression."
    }

    func trophyMessage(_ candidate: InsightCandidate) -> String {
        let trophy = candidate.context["trophy"]?.nilIfEmpty
            ?? candidate.candidateHeadline.replacingOccurrences(of: " trophy is within reach", with: "")
        let remaining = candidate.context["remaining"]?.nilIfEmpty
        let unit = candidate.context["unit"]?.nilIfEmpty

        if let remaining, let unit {
            return "You are \(remaining) \(unit) away from \(trophy). Because the unlock is close, one focused session should aim for quality first and let the trophy follow."
        }

        return "\(trophy) is close. Because progress is already banked, keep the next session specific instead of chasing random extra volume."
    }

    func consistencyMessage(_ candidate: InsightCandidate) -> String {
        let value = candidate.context["value"]?.nilIfEmpty ?? candidate.evidence.first?.value ?? "Your consistency is building"
        let comparison = candidate.context["comparison"]?.nilIfEmpty

        if let comparison {
            return "\(value), with \(comparison). Because consistency is peaking, the next workout should protect form before adding volume."
        }

        return "\(value). Because the habit is alive, use the next plan to protect quality and keep the streak realistic."
    }

    func planSpecificMessage(_ candidate: InsightCandidate) -> String {
        if candidate.candidateAction == .protectStreakWithSmartStart {
            return "Smart Start is short today because the current streak needs a clean restart. The goal is to protect consistency without overloading the first session back."
        }

        if candidate.candidateAction == .focusCue,
           let value = candidate.context["value"]?.nilIfEmpty {
            return "\(value). Because camera setup has repeated, start by fixing the frame before chasing reps."
        }

        let planTitle = candidate.context["planTitle"]?.nilIfEmpty ?? "Today"
        return "\(planTitle) has one clear job: turn recent training evidence into a cleaner next session. Because the insight is specific, follow the recommended focus before adding volume."
    }

    func workoutSpecificMessage(_ candidate: InsightCandidate) -> String {
        let exercise = candidate.context["exercise"]?.nilIfEmpty ?? "This session"
        return "\(exercise) gave a clear workout signal. Because the next plan should respond to evidence, use the recommended action before increasing difficulty."
    }

    func dayOverDayMessage(_ candidate: InsightCandidate) -> String {
        let value = candidate.context["value"]?.nilIfEmpty ?? candidate.evidence.first?.value ?? "Recent training changed"
        let comparison = candidate.context["comparison"]?.nilIfEmpty

        if let comparison {
            return "\(value), compared with \(comparison). Because the story spans multiple sessions, the next workout should match volume to form quality."
        }

        return "\(value). Because this is a trend, not a one-off metric, use it to guide the next plan choice."
    }

    func planSpecificShortMessage(_ candidate: InsightCandidate) -> String {
        if candidate.candidateAction == .protectStreakWithSmartStart {
            return "Smart Start is short to restart cleanly without overload."
        }
        if candidate.candidateAction == .focusCue {
            return "Fix camera setup first so the reps can count cleanly."
        }
        return "Today's plan has one evidence-backed focus."
    }

    func actionPhrase(_ action: InsightAction, exercise: String) -> String {
        actionPhrase(action, exercise: exercise, targetUnit: nil)
    }

    func actionPhrase(_ action: InsightAction, exercise: String, targetUnit: String?) -> String {
        switch action {
        case .continuePlan:
            return "keep \(exercise) in the plan and protect the same quality."
        case .repeatTarget:
            return "repeat the target before adding volume."
        case .increaseTarget:
            if targetUnit == "hold" {
                return "add a few seconds per hold only if form stays clean."
            }
            if targetUnit == "timed" {
                return "add a small work-time increase only if form stays clean."
            }
            return "add one rep per set only if form stays clean."
        case .decreaseTarget:
            return "lower the target before quality breaks."
        case .increaseRest:
            return "add rest before adding more work."
        case .reduceRest:
            return "trim rest only if form stays steady."
        case .swapExerciseLater:
            return "swap to a safer option before starting."
        case .useEasierVariant:
            if exercise.lowercased().contains("push") {
                return "start with incline push-ups, then earn regular push-ups back when alignment holds."
            }
            return "use the easier variant first, then progress when form holds."
        case .useHarderVariant:
            return "try a harder variant only after the first set stays clean."
        case .focusCue:
            return "make the repeated cue the first focus before adding reps."
        case .takeMobilityDay:
            return "use a mobility day and come back when movement quality is ready."
        case .protectStreakWithSmartStart:
            return "use Smart Start to keep the streak alive without overload."
        case .celebrate:
            return "celebrate the progress and keep the next action specific."
        case .noActionNeeded:
            return "keep training normally."
        }
    }

    func shortAction(_ action: InsightAction, exercise: String) -> String {
        switch action {
        case .useEasierVariant:
            return exercise.lowercased().contains("push") ? "Start incline next." : "Use the easier variant next."
        case .focusCue:
            return "Make the cue first."
        case .increaseRest:
            return "Add rest next."
        case .decreaseTarget:
            return "Lower the next target."
        case .repeatTarget:
            return "Repeat before progressing."
        case .increaseTarget:
            return "Add one rep only if clean."
        case .continuePlan:
            return "Keep the same focus."
        default:
            return "Use the recommended adjustment."
        }
    }

    func sanitize(_ text: String) -> String {
        let blockedTerms = [
            "heart-rate",
            "heart rate",
            "bpm",
            "calorie",
            "calories",
            "fat loss",
            "fat-loss",
            "weight loss",
            "weight-loss"
        ]
        let normalized = text.lowercased()
        guard !blockedTerms.contains(where: { normalized.contains($0) }) else {
            return "This insight uses only supported local workout, form, cue, rest, and trophy evidence."
        }
        return text
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
