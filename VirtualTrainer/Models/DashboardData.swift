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
    let smartStart: DashboardPlanSummary
    let dailyPlan: DashboardPlanSummary
    let quickActions: [DashboardQuickAction]
    let trophyTeaserText: String
    let recentWorkout: DashboardRecentWorkout?
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
        recentWorkoutHistory: [RecentWorkoutHistoryItem] = []
    ) -> DashboardContent {
        let smartStart = planService.generateSmartStart(profile: profile)
        let dailyPlan = planService.generateDailyPlan(profile: profile)

        return DashboardContent(
            greeting: timeBasedGreeting(at: now),
            athleteName: profile.firstName,
            streak: DashboardStreak(dayCount: currentStreakDays(from: recentWorkoutHistory, now: now)),
            smartStart: DashboardPlanSummary(plan: smartStart),
            dailyPlan: DashboardPlanSummary(plan: dailyPlan),
            quickActions: Self.quickActions,
            trophyTeaserText: "Milestones will unlock as you train.",
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
}
