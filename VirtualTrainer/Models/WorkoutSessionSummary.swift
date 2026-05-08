import Foundation

nonisolated enum WorkoutSessionSummaryMode: String, Codable, Equatable {
    case freeAnalysis
    case plannedWorkout

    var displayName: String {
        switch self {
        case .freeAnalysis:
            return "Free Analysis"
        case .plannedWorkout:
            return "Planned Workout"
        }
    }
}

nonisolated enum WorkoutOutcome: String, Codable, Equatable {
    case completed
    case partial
    case cancelled
    case freeAnalysisSaved
}

nonisolated struct CueEvent: Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let exerciseType: ExerciseType
    let cueMessage: String
    let severity: CoachCue.Severity
    let setIndex: Int?
    let repIndex: Int?
    let secondsIntoSet: TimeInterval?
    let formScoreAtEvent: Int?
    let metricKey: String?
    let metricValue: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        exerciseType: ExerciseType,
        cueMessage: String,
        severity: CoachCue.Severity,
        setIndex: Int? = nil,
        repIndex: Int? = nil,
        secondsIntoSet: TimeInterval? = nil,
        formScoreAtEvent: Int? = nil,
        metricKey: String? = nil,
        metricValue: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.exerciseType = exerciseType
        self.cueMessage = cueMessage
        self.severity = severity
        self.setIndex = setIndex
        self.repIndex = repIndex
        self.secondsIntoSet = secondsIntoSet.map { max($0, 0) }
        self.formScoreAtEvent = formScoreAtEvent.map { max(0, min($0, 100)) }
        self.metricKey = metricKey
        self.metricValue = metricValue
    }

    func withContextDefaults(
        setIndex: Int?,
        repIndex: Int? = nil,
        secondsIntoSet: TimeInterval? = nil,
        formScoreAtEvent: Int? = nil
    ) -> CueEvent {
        CueEvent(
            id: id,
            timestamp: timestamp,
            exerciseType: exerciseType,
            cueMessage: cueMessage,
            severity: severity,
            setIndex: self.setIndex ?? setIndex,
            repIndex: self.repIndex ?? repIndex,
            secondsIntoSet: self.secondsIntoSet ?? secondsIntoSet,
            formScoreAtEvent: self.formScoreAtEvent ?? formScoreAtEvent,
            metricKey: metricKey,
            metricValue: metricValue
        )
    }
}

nonisolated extension CueEvent {
    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case exerciseType
        case cueMessage
        case severity
        case setIndex
        case repIndex
        case secondsIntoSet
        case formScoreAtEvent
        case metricKey
        case metricValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        exerciseType = try container.decode(ExerciseType.self, forKey: .exerciseType)
        cueMessage = try container.decode(String.self, forKey: .cueMessage)
        severity = try container.decode(CoachCue.Severity.self, forKey: .severity)
        setIndex = try container.decodeIfPresent(Int.self, forKey: .setIndex)
        repIndex = try container.decodeIfPresent(Int.self, forKey: .repIndex)
        secondsIntoSet = try container.decodeIfPresent(TimeInterval.self, forKey: .secondsIntoSet)
        formScoreAtEvent = try container.decodeIfPresent(Int.self, forKey: .formScoreAtEvent)
        metricKey = try container.decodeIfPresent(String.self, forKey: .metricKey)
        metricValue = try container.decodeIfPresent(Double.self, forKey: .metricValue)
    }
}

nonisolated struct ExerciseSetSummary: Codable, Equatable {
    let exerciseType: ExerciseType
    let setIndex: Int?
    let target: WorkoutTarget?
    let achievedReps: Int
    let achievedHoldSeconds: Int
    let averageFormScore: Double?
    let cueEvents: [CueEvent]
    let restExtended: Bool
    let skipped: Bool
    let qualitySummary: SetQualitySummary?
    let repQualityEvents: [RepQualityEvent]
    let completionSource: PlannedSetCompletionSource?
    let completedAt: Date?
    let durationSeconds: Int?
    let peakEffort: Double?
    let bestCue: String?
    let worstCue: String?

    init(
        exerciseType: ExerciseType,
        setIndex: Int? = nil,
        target: WorkoutTarget? = nil,
        achievedReps: Int,
        achievedHoldSeconds: Int,
        averageFormScore: Double?,
        cueEvents: [CueEvent] = [],
        restExtended: Bool = false,
        skipped: Bool = false,
        qualitySummary: SetQualitySummary? = nil,
        repQualityEvents: [RepQualityEvent] = [],
        completionSource: PlannedSetCompletionSource? = nil,
        completedAt: Date? = nil,
        durationSeconds: Int? = nil,
        peakEffort: Double? = nil,
        bestCue: String? = nil,
        worstCue: String? = nil
    ) {
        self.exerciseType = exerciseType
        self.setIndex = setIndex
        self.target = target
        self.achievedReps = achievedReps
        self.achievedHoldSeconds = achievedHoldSeconds
        self.averageFormScore = averageFormScore
        self.cueEvents = cueEvents
        self.restExtended = restExtended
        self.skipped = skipped
        self.qualitySummary = qualitySummary
        self.repQualityEvents = repQualityEvents
        self.completionSource = completionSource
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds.map { max($0, 0) }
        self.peakEffort = peakEffort.map { max(0, min($0, 1)) }
        self.bestCue = bestCue
        self.worstCue = worstCue
    }
}

nonisolated extension ExerciseSetSummary {
    private enum CodingKeys: String, CodingKey {
        case exerciseType
        case setIndex
        case target
        case achievedReps
        case achievedHoldSeconds
        case averageFormScore
        case cueEvents
        case restExtended
        case skipped
        case qualitySummary
        case repQualityEvents
        case completionSource
        case completedAt
        case durationSeconds
        case peakEffort
        case bestCue
        case worstCue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseType = try container.decode(ExerciseType.self, forKey: .exerciseType)
        setIndex = try container.decodeIfPresent(Int.self, forKey: .setIndex)
        target = try container.decodeIfPresent(WorkoutTarget.self, forKey: .target)
        achievedReps = try container.decode(Int.self, forKey: .achievedReps)
        achievedHoldSeconds = try container.decode(Int.self, forKey: .achievedHoldSeconds)
        averageFormScore = try container.decodeIfPresent(Double.self, forKey: .averageFormScore)
        cueEvents = try container.decodeIfPresent([CueEvent].self, forKey: .cueEvents) ?? []
        restExtended = try container.decodeIfPresent(Bool.self, forKey: .restExtended) ?? false
        skipped = try container.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
        qualitySummary = try container.decodeIfPresent(SetQualitySummary.self, forKey: .qualitySummary)
        repQualityEvents = try container.decodeIfPresent([RepQualityEvent].self, forKey: .repQualityEvents) ?? []
        completionSource = try container.decodeIfPresent(PlannedSetCompletionSource.self, forKey: .completionSource)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        peakEffort = try container.decodeIfPresent(Double.self, forKey: .peakEffort)
        bestCue = try container.decodeIfPresent(String.self, forKey: .bestCue)
        worstCue = try container.decodeIfPresent(String.self, forKey: .worstCue)
    }
}

nonisolated struct WorkoutSessionSummary: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 2

    let id: UUID
    let accountId: String?
    let summarySchemaVersion: Int
    let appBuildVersion: String?
    let mode: WorkoutSessionSummaryMode
    let planId: UUID?
    let planTitle: String?
    let title: String
    let goal: String?
    let coach: CoachPersonality
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let totalReps: Int
    let totalHoldSeconds: Int
    let averageFormScore: Double?
    let completionPercent: Double?
    let exerciseSummaries: [ExerciseSetSummary]
    let topCue: CueEvent?
    let effortSummary: String
    let workoutOutcome: WorkoutOutcome
    let structuredEffortSummary: StructuredEffortSummary?
    let totalGoodFormReps: Int
    let totalExcellentFormReps: Int
    let totalHighSeverityCues: Int
    let createdAt: Date
    let deletedAt: Date?

    init(
        id: UUID = UUID(),
        accountId: String? = nil,
        summarySchemaVersion: Int = WorkoutSessionSummary.currentSchemaVersion,
        appBuildVersion: String? = WorkoutSessionSummary.defaultAppBuildVersion,
        mode: WorkoutSessionSummaryMode,
        planId: UUID? = nil,
        planTitle: String? = nil,
        title: String,
        goal: String? = nil,
        coach: CoachPersonality,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        totalReps: Int,
        totalHoldSeconds: Int,
        averageFormScore: Double?,
        completionPercent: Double? = nil,
        exerciseSummaries: [ExerciseSetSummary],
        topCue: CueEvent?,
        effortSummary: String,
        workoutOutcome: WorkoutOutcome? = nil,
        structuredEffortSummary: StructuredEffortSummary? = nil,
        totalGoodFormReps: Int? = nil,
        totalExcellentFormReps: Int? = nil,
        totalHighSeverityCues: Int? = nil,
        createdAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.accountId = AccountOwnership.normalizedAccountId(accountId)
        self.summarySchemaVersion = summarySchemaVersion
        self.appBuildVersion = appBuildVersion
        self.mode = mode
        self.planId = planId
        self.planTitle = planTitle
        self.title = title
        self.goal = goal
        self.coach = coach
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = max(durationSeconds, 0)
        self.totalReps = max(totalReps, 0)
        self.totalHoldSeconds = max(totalHoldSeconds, 0)
        self.averageFormScore = averageFormScore
        self.completionPercent = completionPercent
        self.exerciseSummaries = exerciseSummaries
        self.topCue = topCue
        self.effortSummary = effortSummary
        self.workoutOutcome = workoutOutcome ?? Self.defaultOutcome(
            mode: mode,
            completionPercent: completionPercent
        )
        self.structuredEffortSummary = structuredEffortSummary
        self.totalGoodFormReps = totalGoodFormReps ?? Self.totalGoodFormReps(in: exerciseSummaries)
        self.totalExcellentFormReps = totalExcellentFormReps ?? Self.totalExcellentFormReps(in: exerciseSummaries)
        self.totalHighSeverityCues = totalHighSeverityCues ?? Self.totalHighSeverityCues(in: exerciseSummaries)
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    var primaryExerciseType: ExerciseType? {
        exerciseSummaries.first?.exerciseType
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    func markedDeleted(at date: Date) -> WorkoutSessionSummary {
        copy(accountId: accountId, deletedAt: date)
    }

    func restored() -> WorkoutSessionSummary {
        copy(accountId: accountId, deletedAt: nil)
    }

    func withAccountId(_ accountId: String?) -> WorkoutSessionSummary {
        copy(accountId: accountId, deletedAt: deletedAt)
    }
}

nonisolated extension WorkoutSessionSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case accountId
        case summarySchemaVersion
        case appBuildVersion
        case mode
        case planId
        case planTitle
        case title
        case goal
        case coach
        case startedAt
        case endedAt
        case durationSeconds
        case totalReps
        case totalHoldSeconds
        case averageFormScore
        case completionPercent
        case exerciseSummaries
        case topCue
        case effortSummary
        case workoutOutcome
        case structuredEffortSummary
        case totalGoodFormReps
        case totalExcellentFormReps
        case totalHighSeverityCues
        case createdAt
        case deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedMode = try container.decode(WorkoutSessionSummaryMode.self, forKey: .mode)
        let decodedCompletion = try container.decodeIfPresent(Double.self, forKey: .completionPercent)
        let decodedExerciseSummaries = try container.decode([ExerciseSetSummary].self, forKey: .exerciseSummaries)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        accountId = try container.decodeIfPresent(String.self, forKey: .accountId)
        summarySchemaVersion = try container.decodeIfPresent(Int.self, forKey: .summarySchemaVersion) ?? 1
        appBuildVersion = try container.decodeIfPresent(String.self, forKey: .appBuildVersion)
        mode = decodedMode
        planId = try container.decodeIfPresent(UUID.self, forKey: .planId)
        planTitle = try container.decodeIfPresent(String.self, forKey: .planTitle)
        title = try container.decode(String.self, forKey: .title)
        goal = try container.decodeIfPresent(String.self, forKey: .goal)
        coach = try container.decode(CoachPersonality.self, forKey: .coach)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        durationSeconds = max(try container.decode(Int.self, forKey: .durationSeconds), 0)
        totalReps = max(try container.decode(Int.self, forKey: .totalReps), 0)
        totalHoldSeconds = max(try container.decode(Int.self, forKey: .totalHoldSeconds), 0)
        averageFormScore = try container.decodeIfPresent(Double.self, forKey: .averageFormScore)
        completionPercent = decodedCompletion
        exerciseSummaries = decodedExerciseSummaries
        topCue = try container.decodeIfPresent(CueEvent.self, forKey: .topCue)
        effortSummary = try container.decode(String.self, forKey: .effortSummary)
        workoutOutcome = try container.decodeIfPresent(WorkoutOutcome.self, forKey: .workoutOutcome)
            ?? Self.defaultOutcome(mode: decodedMode, completionPercent: decodedCompletion)
        structuredEffortSummary = try container.decodeIfPresent(StructuredEffortSummary.self, forKey: .structuredEffortSummary)
        totalGoodFormReps = try container.decodeIfPresent(Int.self, forKey: .totalGoodFormReps)
            ?? Self.totalGoodFormReps(in: decodedExerciseSummaries)
        totalExcellentFormReps = try container.decodeIfPresent(Int.self, forKey: .totalExcellentFormReps)
            ?? Self.totalExcellentFormReps(in: decodedExerciseSummaries)
        totalHighSeverityCues = try container.decodeIfPresent(Int.self, forKey: .totalHighSeverityCues)
            ?? Self.totalHighSeverityCues(in: decodedExerciseSummaries)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? endedAt
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

nonisolated private extension WorkoutSessionSummary {
    func copy(accountId: String?, deletedAt: Date?) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            id: id,
            accountId: accountId,
            summarySchemaVersion: summarySchemaVersion,
            appBuildVersion: appBuildVersion,
            mode: mode,
            planId: planId,
            planTitle: planTitle,
            title: title,
            goal: goal,
            coach: coach,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            totalReps: totalReps,
            totalHoldSeconds: totalHoldSeconds,
            averageFormScore: averageFormScore,
            completionPercent: completionPercent,
            exerciseSummaries: exerciseSummaries,
            topCue: topCue,
            effortSummary: effortSummary,
            workoutOutcome: workoutOutcome,
            structuredEffortSummary: structuredEffortSummary,
            totalGoodFormReps: totalGoodFormReps,
            totalExcellentFormReps: totalExcellentFormReps,
            totalHighSeverityCues: totalHighSeverityCues,
            createdAt: createdAt,
            deletedAt: deletedAt
        )
    }
}

nonisolated extension WorkoutSessionSummary {
    static func freeAnalysis(
        from summary: FreeAnalysisSummary,
        createdAt: Date = Date()
    ) -> WorkoutSessionSummary {
        let qualitySummary = summary.qualitySummary ?? SetQualitySummary.build(
            repQualityEvents: summary.repQualityEvents,
            cueEvents: summary.cueEvents
        )
        let exerciseSummary = ExerciseSetSummary(
            exerciseType: summary.exerciseType,
            achievedReps: summary.reps,
            achievedHoldSeconds: Int(summary.holdDuration.rounded()),
            averageFormScore: qualitySummary.averageFormScore ?? summary.latestFormScore.map { Double($0.score) },
            cueEvents: summary.cueEvents,
            qualitySummary: qualitySummary,
            repQualityEvents: summary.repQualityEvents,
            completedAt: summary.endedAt,
            durationSeconds: Int(summary.duration.rounded()),
            peakEffort: summary.peakEffort,
            bestCue: summary.lastCue?.message,
            worstCue: summary.lastCue?.message
        )
        let structuredEffortSummary = StructuredEffortSummary.build(
            repQualityEvents: summary.repQualityEvents,
            peakEffort: summary.peakEffort
        )

        return WorkoutSessionSummary(
            id: summary.id,
            mode: .freeAnalysis,
            title: summary.exerciseType.displayName,
            coach: summary.coach,
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            durationSeconds: Int(summary.duration.rounded()),
            totalReps: summary.reps,
            totalHoldSeconds: Int(summary.holdDuration.rounded()),
            averageFormScore: qualitySummary.averageFormScore ?? summary.latestFormScore.map { Double($0.score) },
            exerciseSummaries: [exerciseSummary],
            topCue: topCue(from: summary.cueEvents),
            effortSummary: effortSummary(peakEffort: summary.peakEffort),
            workoutOutcome: .freeAnalysisSaved,
            structuredEffortSummary: structuredEffortSummary,
            createdAt: createdAt
        )
    }

    static func plannedWorkout(
        id: UUID = UUID(),
        plan: WorkoutPlanV2,
        startedAt: Date,
        completedSets: [PlannedWorkoutSetSummary],
        restOutcomes: [UUID: PlannedWorkoutRestResult] = [:],
        completedAt fallbackCompletedAt: Date = Date(),
        createdAt: Date = Date()
    ) -> WorkoutSessionSummary {
        let plannedSetCount = plan.blocks
            .flatMap(\.exercises)
            .reduce(0) { $0 + $1.sets.count }

        let endedAt = completedSets.map(\.completedAt).max() ?? fallbackCompletedAt
        let activeDuration = completedSets.reduce(0) { $0 + max($1.duration, 0) }
        let wallDuration = max(endedAt.timeIntervalSince(startedAt), 0)
        let durationSeconds = Int(max(wallDuration, activeDuration).rounded())

        let exerciseSummaries = completedSets.map { setSummary in
            let cueEvents = normalizedCueEvents(from: setSummary)
            let restOutcome = restOutcomes[setSummary.id]
            let qualitySummary = setSummary.qualitySummary ?? SetQualitySummary.build(
                repQualityEvents: setSummary.repQualityEvents,
                cueEvents: cueEvents
            )
            return ExerciseSetSummary(
                exerciseType: setSummary.exerciseType,
                setIndex: setSummary.setIndex,
                target: setSummary.target,
                achievedReps: setSummary.reps,
                achievedHoldSeconds: Int(setSummary.holdDuration.rounded()),
                averageFormScore: qualitySummary.averageFormScore ?? setSummary.latestFormScore.map { Double($0.score) },
                cueEvents: cueEvents,
                restExtended: restOutcome?.restExtended ?? false,
                skipped: restOutcome?.skipped ?? false,
                qualitySummary: qualitySummary,
                repQualityEvents: setSummary.repQualityEvents,
                completionSource: setSummary.completionSource,
                completedAt: setSummary.completedAt,
                durationSeconds: Int(setSummary.duration.rounded()),
                peakEffort: setSummary.peakEffort,
                bestCue: setSummary.bestCue?.message,
                worstCue: setSummary.worstCue?.message
            )
        }

        let repFormScores = exerciseSummaries
            .flatMap(\.repQualityEvents)
            .compactMap(\.formScore)
        let latestFormScores = completedSets.compactMap { $0.latestFormScore?.score }
        let allCueEvents = exerciseSummaries.flatMap(\.cueEvents)
        let completionPercent = plannedSetCount > 0
            ? min(Double(completedSets.count) / Double(plannedSetCount), 1.0)
            : nil
        let allRepQualityEvents = exerciseSummaries.flatMap(\.repQualityEvents)
        let structuredEffortSummary = StructuredEffortSummary.build(
            repQualityEvents: allRepQualityEvents,
            peakEffort: completedSets.map(\.peakEffort).max()
        )

        return WorkoutSessionSummary(
            id: id,
            mode: .plannedWorkout,
            planId: plan.id,
            planTitle: plan.title,
            title: plan.title,
            goal: plan.goal,
            coach: plan.coach,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            totalReps: completedSets.reduce(0) { $0 + max($1.reps, 0) },
            totalHoldSeconds: Int(completedSets.reduce(0) { $0 + max($1.holdDuration, 0) }.rounded()),
            averageFormScore: averageScore(from: repFormScores.isEmpty ? latestFormScores : repFormScores),
            completionPercent: completionPercent,
            exerciseSummaries: exerciseSummaries,
            topCue: topCue(from: allCueEvents),
            effortSummary: effortSummary(
                peakEffort: completedSets.map(\.peakEffort).max() ?? 0
            ),
            workoutOutcome: plannedOutcome(completionPercent: completionPercent),
            structuredEffortSummary: structuredEffortSummary,
            createdAt: createdAt
        )
    }
}

nonisolated private extension WorkoutSessionSummary {
    static func normalizedCueEvents(
        from setSummary: PlannedWorkoutSetSummary
    ) -> [CueEvent] {
        if !setSummary.cueEvents.isEmpty {
            return setSummary.cueEvents.map {
                $0.withContextDefaults(setIndex: setSummary.setIndex)
            }
        }

        var uniqueCues: [CoachCue] = []
        for cue in [setSummary.worstCue, setSummary.lastCue, setSummary.bestCue].compactMap({ $0 }) {
            guard !uniqueCues.contains(where: {
                $0.message == cue.message && $0.severity == cue.severity
            }) else { continue }
            uniqueCues.append(cue)
        }

        return uniqueCues.map { cue in
            CueEvent(
                timestamp: setSummary.completedAt,
                exerciseType: setSummary.exerciseType,
                cueMessage: cue.message,
                severity: cue.severity,
                setIndex: setSummary.setIndex,
                repIndex: setSummary.reps > 0 ? setSummary.reps : nil,
                secondsIntoSet: setSummary.duration,
                formScoreAtEvent: setSummary.latestFormScore?.score
            )
        }
    }

    static func averageScore(from scores: [Int]) -> Double? {
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    static func topCue(from events: [CueEvent]) -> CueEvent? {
        events.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return lhs.timestamp < rhs.timestamp
        }.first
    }

    static func effortSummary(peakEffort: Double) -> String {
        let percent = Int((max(0, min(peakEffort, 1)) * 100).rounded())
        switch peakEffort {
        case 0.75...:
            return "Peak effort hit \(percent)%. High strain captured near the end."
        case 0.45..<0.75:
            return "Peak effort reached \(percent)%. Solid working intensity."
        case 0.01..<0.45:
            return "Peak effort stayed around \(percent)%. Controlled session."
        default:
            return "No face-effort signal was captured for this session."
        }
    }

    static var defaultAppBuildVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    static func defaultOutcome(
        mode: WorkoutSessionSummaryMode,
        completionPercent: Double?
    ) -> WorkoutOutcome {
        switch mode {
        case .freeAnalysis:
            return .freeAnalysisSaved
        case .plannedWorkout:
            guard let completionPercent else { return .partial }
            return completionPercent >= 1 ? .completed : .partial
        }
    }

    static func plannedOutcome(completionPercent: Double?) -> WorkoutOutcome {
        defaultOutcome(mode: .plannedWorkout, completionPercent: completionPercent)
    }

    static func totalGoodFormReps(in summaries: [ExerciseSetSummary]) -> Int {
        summaries.reduce(0) { total, summary in
            total + (summary.qualitySummary?.goodFormReps ?? summary.repQualityEvents.filter {
                guard let score = $0.formScore else { return false }
                return score >= 80
            }.count)
        }
    }

    static func totalExcellentFormReps(in summaries: [ExerciseSetSummary]) -> Int {
        summaries.reduce(0) { total, summary in
            total + (summary.qualitySummary?.excellentFormReps ?? summary.repQualityEvents.filter {
                guard let score = $0.formScore else { return false }
                return score >= 90
            }.count)
        }
    }

    static func totalHighSeverityCues(in summaries: [ExerciseSetSummary]) -> Int {
        summaries.reduce(0) { total, summary in
            let qualityCount = summary.qualitySummary?.highSeverityCueCount
            let eventCount = summary.cueEvents.filter { $0.severity >= .warning }.count
            let repCount = summary.repQualityEvents.filter {
                guard let severity = $0.cueSeverityNearRep else { return false }
                return severity >= .warning
            }.count
            return total + (qualityCount ?? (eventCount + repCount))
        }
    }
}
