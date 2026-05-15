import Combine
import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    /// Runtime-selected backend mode. Phase 16G uses Firebase Auth plus
    /// Firestore repositories for profile, calibration, active plan cache,
    /// workouts, trophy events, and insight memory. Local mode keeps using
    /// the local repositories with no Firebase config required.
    let backendMode: BackendMode
    let auth: any AuthRepository
    let profile: any ProfileRepository
    let workouts: any WorkoutRepository
    let trophies: any TrophyRepository
    let insights: any InsightRepository
    let theme: any ThemeRepository
    let calibration: any CalibrationRepository
    let plans: any PlanRepository

    init(
        backendMode: BackendMode,
        auth: any AuthRepository,
        profile: any ProfileRepository,
        workouts: any WorkoutRepository,
        trophies: any TrophyRepository,
        insights: any InsightRepository,
        theme: any ThemeRepository,
        calibration: any CalibrationRepository,
        plans: any PlanRepository
    ) {
        self.backendMode = backendMode
        self.auth = auth
        self.profile = profile
        self.workouts = workouts
        self.trophies = trophies
        self.insights = insights
        self.theme = theme
        self.calibration = calibration
        self.plans = plans
    }

    static func local() -> AppDependencies {
        localRepositories(taggedAs: .local)
    }

    static func firebaseAuthOnly() -> AppDependencies {
        localRepositories(taggedAs: .firebase, auth: FirebaseAuthRepository())
    }

    static func firebasePartial() -> AppDependencies {
        let firestore = FirebaseFirestoreDocumentDatabase()
        return AppDependencies(
            backendMode: .firebase,
            auth: FirebaseAuthRepository(),
            profile: FirestoreProfileRepository(database: firestore),
            workouts: FirestoreWorkoutRepository(database: firestore),
            trophies: FirestoreTrophyRepository(database: firestore),
            insights: FirestoreInsightRepository(database: firestore),
            theme: FirestoreThemeRepository(database: firestore),
            calibration: FirestoreCalibrationRepository(database: firestore),
            plans: FirestorePlanRepository(database: firestore)
        )
    }

    static func from(_ statusStore: BackendStatusStore) -> AppDependencies {
        switch statusStore.activeBackendMode {
        case .local, .supabase:
            return local()
        case .firebase:
            return firebasePartial()
        }
    }

    private static func localRepositories(
        taggedAs backendMode: BackendMode,
        auth: (any AuthRepository)? = nil
    ) -> AppDependencies {
        AppDependencies(
            backendMode: backendMode,
            auth: auth ?? LocalAuthRepository(),
            profile: LocalProfileRepository(),
            workouts: LocalWorkoutRepository(),
            trophies: LocalTrophyRepository(),
            insights: LocalInsightRepository(),
            theme: LocalThemeRepository(),
            calibration: LocalCalibrationRepository(),
            plans: LocalPlanRepository()
        )
    }
}
