import Foundation

nonisolated enum DashboardQuickActionKind: String, Equatable {
    case formCheck
    case runningAnalysis
    case trophies
}

nonisolated enum DashboardDestination: Equatable {
    case formCheckSelection
    case runningAnalysis
    case trophies
}

nonisolated struct DashboardQuickAction: Identifiable, Equatable {
    let kind: DashboardQuickActionKind
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    let statusLabel: String?
    let destination: DashboardDestination?

    var id: DashboardQuickActionKind { kind }
}

nonisolated struct DashboardPlanSummary: Identifiable, Equatable {
    let plan: WorkoutPlanV2

    var id: UUID { plan.id }
    var title: String { plan.title }
    var subtitle: String { plan.subtitle }
    var durationText: String { "\(plan.estimatedMinutes) min" }
    var reason: String { plan.planReason }
    var exerciseCount: Int { plan.blocks.flatMap(\.exercises).count }
}

nonisolated struct DashboardStreak: Equatable {
    let dayCount: Int

    var title: String {
        dayCount == 1 ? "1 day streak" : "\(dayCount) day streak"
    }

    var subtitle: String {
        dayCount > 0 ? "Keep it alive today." : "Complete a workout to start."
    }
}

nonisolated struct DashboardRecentWorkout: Identifiable, Equatable {
    let id: UUID
    let exerciseType: ExerciseType
    let completedAt: Date

    var title: String { exerciseType.displayName }
}

nonisolated struct DashboardContent: Equatable {
    let greeting: String
    let athleteName: String
    let streak: DashboardStreak
    let smartStartDeck: QuickStartDeck
    var selectedSmartStartIndex: Int
    let smartStartFallback: DashboardPlanSummary
    let dailyPlan: DashboardPlanSummary
    let quickActions: [DashboardQuickAction]
    let trophyTeaserText: String
    let recentWorkout: DashboardRecentWorkout?

    var currentSmartStart: QuickStartPlanVariant {
        smartStartDeck.variant(at: selectedSmartStartIndex) ?? QuickStartPlanVariant(
            id: smartStartFallback.plan.id.uuidString,
            title: smartStartFallback.title,
            subtitle: smartStartFallback.subtitle,
            intensityLabel: smartStartFallback.plan.difficulty == .beginner ? .beginner : .intermediate,
            plan: smartStartFallback.plan,
            reason: smartStartFallback.reason,
            deckIndex: 0
        )
    }

    var smartStart: DashboardPlanSummary {
        DashboardPlanSummary(plan: currentSmartStart.plan)
    }

    mutating func advanceSmartStartPlan() {
        selectedSmartStartIndex = smartStartDeck.index(after: selectedSmartStartIndex)
    }
}

nonisolated final class DashboardContentFactory {
    private let planService: PlanService
    private let calendar: Calendar

    init(
        planService: PlanService = PlanService(),
        calendar: Calendar = .current
    ) {
        self.planService = planService
        self.calendar = calendar
    }

    func makeContent(
        profile: UserProfile,
        now: Date = Date(),
        recentWorkoutHistory: [RecentWorkoutHistoryItem] = [],
        currentStreakDayCount: Int? = nil,
        trophySnapshot: TrophyProgressSnapshot? = nil
    ) -> DashboardContent {
        let smartStartDeck = planService.generateQuickStartDeck(
            profile: profile,
            recentWorkoutHistory: recentWorkoutHistory,
            now: now
        )
        let smartStartFallback = smartStartDeck.variants.first?.plan ?? planService.generateSmartStart(
            profile: profile,
            recentWorkoutHistory: recentWorkoutHistory
        )
        let dailyPlan = planService.generateDailyPlan(
            profile: profile,
            recentWorkoutHistory: recentWorkoutHistory
        )

        return DashboardContent(
            greeting: timeBasedGreeting(at: now),
            athleteName: profile.firstName,
            streak: DashboardStreak(
                dayCount: currentStreakDayCount ?? currentStreakDays(
                    from: recentWorkoutHistory,
                    now: now
                )
            ),
            smartStartDeck: smartStartDeck,
            selectedSmartStartIndex: 0,
            smartStartFallback: DashboardPlanSummary(plan: smartStartFallback),
            dailyPlan: DashboardPlanSummary(plan: dailyPlan),
            quickActions: Self.quickActions,
            trophyTeaserText: Self.trophyTeaserText(from: trophySnapshot),
            recentWorkout: mostRecentWorkout(from: recentWorkoutHistory)
        )
    }

    static let quickActions: [DashboardQuickAction] = [
        DashboardQuickAction(
            kind: .formCheck,
            title: "Form Check",
            subtitle: "Single move",
            systemImage: "camera.viewfinder",
            isEnabled: true,
            statusLabel: nil,
            destination: .formCheckSelection
        ),
        DashboardQuickAction(
            kind: .runningAnalysis,
            title: "Running Analysis",
            subtitle: "Gait and stride",
            systemImage: "figure.run",
            isEnabled: false,
            statusLabel: "Coming Soon",
            destination: .runningAnalysis
        ),
        DashboardQuickAction(
            kind: .trophies,
            title: "Trophies",
            subtitle: "Milestones",
            systemImage: "trophy.fill",
            isEnabled: true,
            statusLabel: "Teaser",
            destination: .trophies
        ),
    ]

    private func timeBasedGreeting(at date: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        case 17..<22:
            return "Good evening"
        default:
            return "Good late night"
        }
    }

    private func currentStreakDays(
        from history: [RecentWorkoutHistoryItem],
        now: Date
    ) -> Int {
        let workoutDays = Set(history.map { calendar.startOfDay(for: $0.completedAt) })
        guard !workoutDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var cursor = workoutDays.contains(today) ? today : yesterday
        var streak = 0

        while workoutDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }

        return streak
    }

    private func mostRecentWorkout(
        from history: [RecentWorkoutHistoryItem]
    ) -> DashboardRecentWorkout? {
        history.max { $0.completedAt < $1.completedAt }.map {
            DashboardRecentWorkout(
                id: $0.id,
                exerciseType: $0.exerciseType,
                completedAt: $0.completedAt
            )
        }
    }

    private static func trophyTeaserText(from snapshot: TrophyProgressSnapshot?) -> String {
        guard let snapshot else {
            return "Milestones will unlock as you train."
        }

        let earnedCount = snapshot.availableProgress.filter(\.earned).count
        let availableCount = snapshot.availableProgress.count
        if earnedCount > 0 {
            return "\(earnedCount)/\(availableCount) earned. Keep building the collection."
        }

        if let nearest = snapshot.nearestInProgress,
           let definition = TrophyDefinitionCatalog.definition(for: nearest.trophyId) {
            return "Closest: \(definition.title) - \(nearest.progressLabel)."
        }

        return "Save a workout to light up The Spark."
    }
}
