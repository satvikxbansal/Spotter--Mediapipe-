import Foundation

nonisolated struct RepQualityEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let exerciseType: ExerciseType
    let setIndex: Int?
    let repIndex: Int
    let timestamp: Date
    let secondsIntoSet: TimeInterval
    let formScore: Int?
    let formGrade: String?
    let phase: String?
    let cueMessageNearRep: String?
    let cueSeverityNearRep: CoachCue.Severity?
    let effortAtRep: Double?

    init(
        id: UUID = UUID(),
        exerciseType: ExerciseType,
        setIndex: Int? = nil,
        repIndex: Int,
        timestamp: Date = Date(),
        secondsIntoSet: TimeInterval,
        formScore: Int? = nil,
        formGrade: String? = nil,
        phase: String? = nil,
        cueMessageNearRep: String? = nil,
        cueSeverityNearRep: CoachCue.Severity? = nil,
        effortAtRep: Double? = nil
    ) {
        self.id = id
        self.exerciseType = exerciseType
        self.setIndex = setIndex
        self.repIndex = max(repIndex, 0)
        self.timestamp = timestamp
        self.secondsIntoSet = max(secondsIntoSet, 0)
        self.formScore = formScore.map { max(0, min($0, 100)) }
        self.formGrade = formGrade
        self.phase = phase
        self.cueMessageNearRep = cueMessageNearRep
        self.cueSeverityNearRep = cueSeverityNearRep
        self.effortAtRep = effortAtRep.map { max(0, min($0, 1)) }
    }
}

nonisolated enum SetQualityTrend: String, Codable, Equatable {
    case improved
    case faded
    case stable
    case unknown
}

nonisolated struct SetQualitySummary: Codable, Equatable {
    let totalScoredReps: Int
    let goodFormReps: Int
    let excellentFormReps: Int
    let minFormScore: Double?
    let maxFormScore: Double?
    let averageFormScore: Double?
    let firstHalfAverageFormScore: Double?
    let secondHalfAverageFormScore: Double?
    let breakdownRepIndex: Int?
    let improvementRepIndex: Int?
    let highSeverityCueCount: Int
    let mostRepeatedCue: String?
    let qualityTrend: SetQualityTrend

    init(
        totalScoredReps: Int,
        goodFormReps: Int,
        excellentFormReps: Int,
        minFormScore: Double?,
        maxFormScore: Double?,
        averageFormScore: Double?,
        firstHalfAverageFormScore: Double?,
        secondHalfAverageFormScore: Double?,
        breakdownRepIndex: Int?,
        improvementRepIndex: Int?,
        highSeverityCueCount: Int,
        mostRepeatedCue: String?,
        qualityTrend: SetQualityTrend
    ) {
        self.totalScoredReps = max(totalScoredReps, 0)
        self.goodFormReps = max(goodFormReps, 0)
        self.excellentFormReps = max(excellentFormReps, 0)
        self.minFormScore = minFormScore
        self.maxFormScore = maxFormScore
        self.averageFormScore = averageFormScore
        self.firstHalfAverageFormScore = firstHalfAverageFormScore
        self.secondHalfAverageFormScore = secondHalfAverageFormScore
        self.breakdownRepIndex = breakdownRepIndex
        self.improvementRepIndex = improvementRepIndex
        self.highSeverityCueCount = max(highSeverityCueCount, 0)
        self.mostRepeatedCue = mostRepeatedCue
        self.qualityTrend = qualityTrend
    }
}

nonisolated extension SetQualitySummary {
    static func build(
        repQualityEvents: [RepQualityEvent],
        cueEvents: [CueEvent] = []
    ) -> SetQualitySummary {
        let scoredEvents = repQualityEvents
            .filter { $0.formScore != nil }
            .sorted { lhs, rhs in
                if lhs.repIndex == rhs.repIndex {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.repIndex < rhs.repIndex
            }
        let scores = scoredEvents.compactMap(\.formScore).map(Double.init)
        let firstHalfCount = scores.isEmpty ? 0 : max(scores.count / 2, 1)
        let firstHalfScores = Array(scores.prefix(firstHalfCount))
        let secondHalfScores = Array(scores.dropFirst(firstHalfCount))
        let firstAverage = average(firstHalfScores)
        let secondAverage = average(secondHalfScores)

        let cueMessages = repQualityEvents.compactMap(\.cueMessageNearRep) + cueEvents.map(\.cueMessage)
        let mostRepeatedCue = cueMessages
            .reduce(into: [String: Int]()) { counts, message in
                counts[message, default: 0] += 1
            }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .first?
            .key

        let highSeverityCueMessages = Set(cueEvents.filter { $0.severity >= .warning }.map(\.cueMessage))
        let highSeverityCueEvents = highSeverityCueMessages.count
        let highSeverityRepCues = repQualityEvents.filter {
            guard let severity = $0.cueSeverityNearRep else { return false }
            if let cueMessage = $0.cueMessageNearRep,
               highSeverityCueMessages.contains(cueMessage) {
                return false
            }
            return severity >= .warning
        }.count

        return SetQualitySummary(
            totalScoredReps: scores.count,
            goodFormReps: scores.filter { $0 >= 80 }.count,
            excellentFormReps: scores.filter { $0 >= 90 }.count,
            minFormScore: scores.min(),
            maxFormScore: scores.max(),
            averageFormScore: average(scores),
            firstHalfAverageFormScore: firstAverage,
            secondHalfAverageFormScore: secondAverage,
            breakdownRepIndex: firstAdjacentChangeIndex(in: scoredEvents, minimumDelta: -8),
            improvementRepIndex: firstAdjacentChangeIndex(in: scoredEvents, minimumDelta: 8),
            highSeverityCueCount: highSeverityCueEvents + highSeverityRepCues,
            mostRepeatedCue: mostRepeatedCue,
            qualityTrend: qualityTrend(firstAverage: firstAverage, secondAverage: secondAverage)
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func firstAdjacentChangeIndex(
        in events: [RepQualityEvent],
        minimumDelta: Double
    ) -> Int? {
        guard events.count >= 2 else { return nil }

        for index in events.indices.dropFirst() {
            guard let previousScore = events[events.index(before: index)].formScore,
                  let currentScore = events[index].formScore
            else { continue }

            let delta = Double(currentScore - previousScore)
            if minimumDelta >= 0, delta >= minimumDelta {
                return events[index].repIndex
            }
            if minimumDelta < 0, delta <= minimumDelta {
                return events[index].repIndex
            }
        }

        return nil
    }

    private static func qualityTrend(
        firstAverage: Double?,
        secondAverage: Double?
    ) -> SetQualityTrend {
        guard let firstAverage, let secondAverage else { return .unknown }

        let delta = secondAverage - firstAverage
        if delta >= 5 { return .improved }
        if delta <= -5 { return .faded }
        return .stable
    }
}

nonisolated enum EffortTrend: String, Codable, Equatable {
    case rising
    case steady
    case falling
    case unavailable
}

nonisolated enum EffortSource: String, Codable, Equatable {
    case faceBlendshapeProxy
    case unavailable
}

nonisolated struct StructuredEffortSummary: Codable, Equatable {
    let averageEffort: Double?
    let peakEffort: Double?
    let trend: EffortTrend
    let source: EffortSource

    init(
        averageEffort: Double?,
        peakEffort: Double?,
        trend: EffortTrend,
        source: EffortSource
    ) {
        self.averageEffort = averageEffort.map { max(0, min($0, 1)) }
        self.peakEffort = peakEffort.map { max(0, min($0, 1)) }
        self.trend = trend
        self.source = source
    }
}

nonisolated extension StructuredEffortSummary {
    static func build(
        repQualityEvents: [RepQualityEvent],
        peakEffort fallbackPeakEffort: Double? = nil
    ) -> StructuredEffortSummary {
        let efforts = repQualityEvents
            .compactMap(\.effortAtRep)
            .filter { $0 > 0 }
        let fallbackPeak = fallbackPeakEffort.map { max(0, min($0, 1)) }
        let peakEffort = efforts.max() ?? fallbackPeak
        let source: EffortSource = (peakEffort ?? 0) > 0 ? .faceBlendshapeProxy : .unavailable

        return StructuredEffortSummary(
            averageEffort: efforts.isEmpty ? nil : efforts.reduce(0, +) / Double(efforts.count),
            peakEffort: peakEffort,
            trend: effortTrend(from: efforts),
            source: source
        )
    }

    private static func effortTrend(from efforts: [Double]) -> EffortTrend {
        guard efforts.count >= 2 else { return .unavailable }

        let firstHalfCount = max(efforts.count / 2, 1)
        let firstAverage = efforts.prefix(firstHalfCount).reduce(0, +) / Double(firstHalfCount)
        let secondEfforts = efforts.dropFirst(firstHalfCount)
        guard !secondEfforts.isEmpty else { return .unavailable }

        let secondAverage = secondEfforts.reduce(0, +) / Double(secondEfforts.count)
        let delta = secondAverage - firstAverage
        if delta >= 0.08 { return .rising }
        if delta <= -0.08 { return .falling }
        return .steady
    }
}
