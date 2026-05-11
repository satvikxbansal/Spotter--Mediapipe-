import Foundation

@MainActor
protocol AuthRepository: AnyObject {
    var currentAccountId: String? { get }

    func signInAnonymously() async throws -> String
    func linkAnonymousAccountWithApple(idToken: String, nonce: String) async throws -> String
    func signOut() async throws
    func deleteAccount() async throws
    func observeAuthChanges() async throws -> AsyncStream<String?>
}

@MainActor
protocol ProfileRepository: AnyObject {
    func loadProfile(accountId: String) async throws -> UserProfile?
    func saveProfile(_ profile: UserProfile, operationId: UUID) async throws
    func observeProfile(accountId: String) async throws -> AsyncStream<UserProfile?>
}

@MainActor
protocol WorkoutRepository: AnyObject {
    func saveWorkoutSummary(_ summary: WorkoutSessionSummary, operationId: UUID) async throws
    func loadRecentWorkouts(accountId: String, limit: Int, since: Date?) async throws -> [WorkoutSessionSummary]
    func loadWorkout(accountId: String, id: UUID) async throws -> WorkoutSessionSummary?
    func deleteWorkout(accountId: String, id: UUID, operationId: UUID) async throws
    func observeRecentWorkouts(accountId: String, limit: Int) async throws -> AsyncStream<[WorkoutSessionSummary]>
}

@MainActor
protocol TrophyRepository: AnyObject {
    func loadTrophyDefinitions() async throws -> [TrophyDefinition]
    func loadTrophyEvents(accountId: String, since: Date?) async throws -> [TrophyUnlockEvent]
    func saveTrophyEvent(_ event: TrophyUnlockEvent, operationId: UUID) async throws
    func loadTrophyProgress(accountId: String) async throws -> [TrophyProgress]
    func observeTrophyEvents(accountId: String) async throws -> AsyncStream<[TrophyUnlockEvent]>
}

@MainActor
protocol InsightRepository: AnyObject {
    func saveInsights(_ insights: [AIInsight], operationId: UUID) async throws
    func loadRecentInsights(accountId: String, limit: Int) async throws -> [AIInsight]
    func saveDeliveryRecord(_ record: InsightDeliveryRecord, operationId: UUID) async throws
    func loadDeliveryRecords(accountId: String) async throws -> [InsightDeliveryRecord]
    func saveEngagementRecord(_ record: InsightEngagementRecord, operationId: UUID) async throws
    func loadEngagementRecords(accountId: String) async throws -> [InsightEngagementRecord]
    func invalidateInsight(accountId: String, dedupeKey: String, operationId: UUID) async throws
}

@MainActor
protocol ThemeRepository: AnyObject {
    func loadTheme(accountId: String) async throws -> SpotterThemeOption
    func saveTheme(_ theme: SpotterThemeOption, accountId: String, operationId: UUID) async throws
}

@MainActor
protocol CalibrationRepository: AnyObject {
    func loadCalibrationRecord(accountId: String) async throws -> CalibrationRecord?
    func saveCalibrationRecord(_ record: CalibrationRecord, operationId: UUID) async throws
}

@MainActor
protocol PlanRepository: AnyObject {
    func saveActivePlan(_ plan: WorkoutPlanV2, accountId: String, operationId: UUID) async throws
    func loadActivePlan(accountId: String) async throws -> WorkoutPlanV2?
    func loadPlanHistory(accountId: String, limit: Int) async throws -> [WorkoutPlanV2]
}
