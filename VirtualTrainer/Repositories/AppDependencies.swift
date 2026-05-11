import Combine
import Foundation

@MainActor
final class AppDependencies: ObservableObject {
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
        AppDependencies(
            backendMode: .local,
            auth: LocalAuthRepository(),
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
