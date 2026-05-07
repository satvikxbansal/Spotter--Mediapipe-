import Foundation

nonisolated struct WorkoutDetailEvidenceModel: Equatable {
    let setEvidence: [SetEvidence]
    let timelineEvents: [TimelineEvent]

    init(summary: WorkoutSessionSummary) {
        setEvidence = summary.exerciseSummaries.enumerated().map { index, setSummary in
            SetEvidence(summary: setSummary, fallbackIndex: index)
        }
        timelineEvents = Self.timelineEvents(from: summary)
    }
}

nonisolated extension WorkoutDetailEvidenceModel {
    struct SetEvidence: Identifiable, Equatable {
        let id: String
        let summary: ExerciseSetSummary
        let formSamples: [FormSample]
        let topCue: String?
        let averageFormScore: Double?
        let excellentFormReps: Int
        let goodFormReps: Int
        let totalScoredReps: Int
        let breakdownRepIndex: Int?
        let improvementRepIndex: Int?
        let qualityTrend: SetQualityTrend
        let bestCue: String?
        let worstCue: String?
        let restIndicators: [RestIndicator]

        init(summary: ExerciseSetSummary, fallbackIndex: Int) {
            let qualitySummary = summary.qualitySummary ?? SetQualitySummary.build(
                repQualityEvents: summary.repQualityEvents,
                cueEvents: summary.cueEvents
            )
            let formSamples = Self.formSamples(from: summary.repQualityEvents)

            id = [
                summary.exerciseType.rawValue,
                String(summary.setIndex ?? fallbackIndex),
                String(fallbackIndex)
            ].joined(separator: "-")
            self.summary = summary
            self.formSamples = formSamples
            topCue = qualitySummary.mostRepeatedCue
                ?? summary.cueEvents.first?.cueMessage
                ?? summary.repQualityEvents.compactMap(\.cueMessageNearRep).first
            averageFormScore = qualitySummary.averageFormScore
                ?? summary.averageFormScore
                ?? Self.averageScore(from: formSamples)
            excellentFormReps = qualitySummary.excellentFormReps
            goodFormReps = qualitySummary.goodFormReps
            totalScoredReps = qualitySummary.totalScoredReps
            breakdownRepIndex = qualitySummary.breakdownRepIndex
            improvementRepIndex = qualitySummary.improvementRepIndex
            qualityTrend = qualitySummary.qualityTrend
            bestCue = summary.bestCue
            worstCue = summary.worstCue
            restIndicators = Self.restIndicators(from: summary)
        }

        var hasCueComparison: Bool {
            bestCue != nil || worstCue != nil
        }

        var hasRepEvidence: Bool {
            !formSamples.isEmpty
        }

        private static func formSamples(from events: [RepQualityEvent]) -> [FormSample] {
            events
                .filter { $0.formScore != nil }
                .sorted { lhs, rhs in
                    if lhs.repIndex == rhs.repIndex {
                        return lhs.timestamp < rhs.timestamp
                    }
                    return lhs.repIndex < rhs.repIndex
                }
                .compactMap { event in
                    guard let score = event.formScore else { return nil }
                    return FormSample(
                        repIndex: event.repIndex,
                        score: score
                    )
                }
        }

        private static func averageScore(from samples: [FormSample]) -> Double? {
            guard !samples.isEmpty else { return nil }
            let total = samples.reduce(0) { $0 + $1.score }
            return Double(total) / Double(samples.count)
        }

        private static func restIndicators(from summary: ExerciseSetSummary) -> [RestIndicator] {
            var indicators: [RestIndicator] = []
            if summary.restExtended {
                indicators.append(
                    RestIndicator(
                        kind: .extended,
                        title: "Rest extended",
                        rationale: "Rest extended after this set."
                    )
                )
            }
            if summary.skipped {
                indicators.append(
                    RestIndicator(
                        kind: .skipped,
                        title: "Rest skipped",
                        rationale: "Rest skipped after this set."
                    )
                )
            }
            return indicators
        }
    }

    struct FormSample: Identifiable, Equatable {
        let repIndex: Int
        let score: Int

        var id: String {
            "\(repIndex)-\(score)"
        }
    }

    struct RestIndicator: Identifiable, Equatable {
        enum Kind: Equatable {
            case extended
            case skipped
        }

        let kind: Kind
        let title: String
        let rationale: String

        var id: String {
            title
        }
    }

    struct TimelineEvent: Identifiable, Equatable {
        enum Kind: Equatable {
            case cue(CoachCue.Severity)
            case repQuality(score: Int?)
        }

        let id: String
        let kind: Kind
        let timestamp: Date
        let secondsIntoSession: TimeInterval
        let secondsIntoSet: TimeInterval?
        let exerciseType: ExerciseType
        let setIndex: Int?
        let repIndex: Int?
        let title: String
        let detail: String?
    }

    private static func timelineEvents(from summary: WorkoutSessionSummary) -> [TimelineEvent] {
        let cueEvents = summary.exerciseSummaries.flatMap { setSummary in
            setSummary.cueEvents.map { event in
                TimelineEvent(
                    id: "cue-\(event.id.uuidString)",
                    kind: .cue(event.severity),
                    timestamp: event.timestamp,
                    secondsIntoSession: max(event.timestamp.timeIntervalSince(summary.startedAt), 0),
                    secondsIntoSet: event.secondsIntoSet,
                    exerciseType: event.exerciseType,
                    setIndex: event.setIndex ?? setSummary.setIndex,
                    repIndex: event.repIndex,
                    title: event.cueMessage,
                    detail: cueDetail(for: event)
                )
            }
        }

        let repEvents = summary.exerciseSummaries.flatMap { setSummary in
            setSummary.repQualityEvents.map { event in
                TimelineEvent(
                    id: "rep-\(event.id.uuidString)",
                    kind: .repQuality(score: event.formScore),
                    timestamp: event.timestamp,
                    secondsIntoSession: max(event.timestamp.timeIntervalSince(summary.startedAt), 0),
                    secondsIntoSet: event.secondsIntoSet,
                    exerciseType: event.exerciseType,
                    setIndex: event.setIndex ?? setSummary.setIndex,
                    repIndex: event.repIndex,
                    title: "Rep \(event.repIndex) completed",
                    detail: repDetail(for: event)
                )
            }
        }

        return (cueEvents + repEvents).sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id < rhs.id
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    private static func cueDetail(for event: CueEvent) -> String? {
        var pieces: [String] = []
        pieces.append(event.severity.rawValue.capitalized)
        if let score = event.formScoreAtEvent {
            pieces.append("Form \(score)%")
        }
        if let metricKey = event.metricKey,
           let metricValue = event.metricValue {
            pieces.append("\(metricKey) \(formattedMetric(metricValue))")
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " / ")
    }

    private static func repDetail(for event: RepQualityEvent) -> String? {
        var pieces: [String] = []
        if let score = event.formScore {
            pieces.append("Score \(score)%")
        }
        if let grade = event.formGrade {
            pieces.append("Grade \(grade)")
        }
        if let effort = event.effortAtRep {
            pieces.append("Effort \(Int((effort * 100).rounded()))%")
        }
        if let cue = event.cueMessageNearRep {
            pieces.append("Cue: \(cue)")
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " / ")
    }

    private static func formattedMetric(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}
