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
    @discardableResult
    func saveProfile(_ profile: UserProfile, operationId: UUID) async throws -> UserProfile
    func observeProfile(accountId: String) async throws -> AsyncStream<UserProfile?>
}

@MainActor
protocol WorkoutRepository: AnyObject {
    @discardableResult
    func saveWorkoutSummary(_ summary: WorkoutSessionSummary, operationId: UUID) async throws -> WorkoutSessionSummary
    func loadRecentWorkouts(accountId: String, limit: Int, since: Date?) async throws -> [WorkoutSessionSummary]
    func loadWorkout(accountId: String, id: UUID) async throws -> WorkoutSessionSummary?
    func deleteWorkout(accountId: String, id: UUID, operationId: UUID) async throws
    func observeRecentWorkouts(accountId: String, limit: Int) async throws -> AsyncStream<[WorkoutSessionSummary]>
}

@MainActor
protocol TrophyRepository: AnyObject {
    func loadTrophyDefinitions() async throws -> [TrophyDefinition]
    func loadTrophyEvents(accountId: String, since: Date?) async throws -> [TrophyUnlockEvent]
    @discardableResult
    func saveTrophyEvent(_ event: TrophyUnlockEvent, operationId: UUID) async throws -> TrophyUnlockEvent
    func loadTrophyProgress(accountId: String) async throws -> [TrophyProgress]
    func observeTrophyEvents(accountId: String) async throws -> AsyncStream<[TrophyUnlockEvent]>
}

@MainActor
protocol InsightRepository: AnyObject {
    @discardableResult
    func saveInsights(_ insights: [AIInsight], operationId: UUID) async throws -> [AIInsight]
    func loadRecentInsights(accountId: String, limit: Int) async throws -> [AIInsight]
    func observeRecentInsights(accountId: String, limit: Int) async throws -> AsyncStream<[AIInsight]>
    @discardableResult
    func saveDeliveryRecord(_ record: InsightDeliveryRecord, operationId: UUID) async throws -> InsightDeliveryRecord
    func loadDeliveryRecords(accountId: String) async throws -> [InsightDeliveryRecord]
    func observeDeliveryRecords(accountId: String) async throws -> AsyncStream<[InsightDeliveryRecord]>
    @discardableResult
    func saveEngagementRecord(_ record: InsightEngagementRecord, operationId: UUID) async throws -> InsightEngagementRecord
    func loadEngagementRecords(accountId: String) async throws -> [InsightEngagementRecord]
    func observeEngagementRecords(accountId: String) async throws -> AsyncStream<[InsightEngagementRecord]>
    func invalidateInsight(accountId: String, dedupeKey: String, operationId: UUID) async throws
}

@MainActor
protocol ThemeRepository: AnyObject {
    func loadTheme(accountId: String) async throws -> SpotterThemeOption
    func saveTheme(_ theme: SpotterThemeOption, accountId: String, operationId: UUID) async throws
    func observeTheme(accountId: String) async throws -> AsyncStream<SpotterThemeOption>
}

@MainActor
protocol CalibrationRepository: AnyObject {
    func loadCalibrationRecord(accountId: String) async throws -> CalibrationRecord?
    @discardableResult
    func saveCalibrationRecord(_ record: CalibrationRecord, operationId: UUID) async throws -> CalibrationRecord
    func observeCalibrationRecord(accountId: String) async throws -> AsyncStream<CalibrationRecord?>
}

@MainActor
protocol PlanRepository: AnyObject {
    @discardableResult
    func saveActivePlan(_ plan: WorkoutPlanV2, accountId: String, operationId: UUID) async throws -> WorkoutPlanV2
    func loadActivePlan(accountId: String) async throws -> WorkoutPlanV2?
    func loadPlanHistory(accountId: String, limit: Int) async throws -> [WorkoutPlanV2]
}
