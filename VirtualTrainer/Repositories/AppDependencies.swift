import Combine
import Foundation

@MainActor
final class AppDependencies: ObservableObject {
<<<<<<< HEAD
    /// Runtime-selected backend mode. Phase 16F uses Firebase Auth plus
    /// Firestore repositories for profile, theme, calibration, plan cache,
    /// trophies, and insight memory. Workouts remain local until their
    /// dedicated sync phase ships.
=======
    /// Runtime-selected backend mode. Phase 16D uses Firebase Auth plus the
    /// lowest-risk Firestore repositories. Trophies and insights remain local
    /// until their dedicated phases ship.
>>>>>>> 7b383eb8cd6e04e19d45807bc31fc441348b786c
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
<<<<<<< HEAD
            workouts: LocalWorkoutRepository(),
            trophies: FirestoreTrophyRepository(database: firestore),
            insights: FirestoreInsightRepository(database: firestore),
=======
            workouts: FirestoreWorkoutRepository(database: firestore),
            trophies: LocalTrophyRepository(),
            insights: LocalInsightRepository(),
>>>>>>> 7b383eb8cd6e04e19d45807bc31fc441348b786c
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
