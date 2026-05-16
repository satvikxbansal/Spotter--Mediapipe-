import SwiftUI

struct CalibrationIntroView: View {
    @EnvironmentObject private var appDependencies: AppDependencies
    @EnvironmentObject private var calibrationStore: CalibrationStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Spacer(minLength: Theme.Spacing.xl)

                    Text("Calibration")
                        .header(size: 42)

                    Text("Track 3 air squats to verify your space.")
                        .bodyText()
                        .foregroundStyle(Theme.Colors.textSecondary)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        CalibrationInfoRow(
                            icon: "camera.viewfinder",
                            title: "Camera placement",
                            detail: "Make sure your full body fits in frame."
                        )
                        CalibrationInfoRow(
                            icon: "figure.strengthtraining.traditional",
                            title: "Body tracking",
                            detail: "Spotter checks basic squat visibility before saving calibration."
                        )
                    }

                    if calibrationStore.status == .failed {
                        failureNotice
                    }

                    if let error = calibrationStore.persistenceError {
                        Text(error)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.danger)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }

                    NavigationLink {
                        CalibrationSessionView()
                    } label: {
                        Text("Start Calibration")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryCTAStyle())

                    Button("Skip for now") {
                        Task {
                            if await calibrationStore.saveSkipped(
                                notes: "Skipped during first-run calibration."
                            ) {
                                appDependencies.analytics.trackCalibrationCompleted(outcome: .skipped)
                            }
                        }
                    }
                    .buttonStyle(SecondaryCTAStyle())

                    Spacer(minLength: Theme.Spacing.xl)
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private var failureNotice: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Calibration did not finish")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(calibrationStore.record?.notes ?? "You can retry now or skip and use Spotter without calibration.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

struct CalibrationSessionView: View {
    @EnvironmentObject private var appDependencies: AppDependencies
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var calibrationStore: CalibrationStore
    @EnvironmentObject private var historyStore: WorkoutHistoryStore
    @EnvironmentObject private var trophyStore: TrophyStore

    var body: some View {
        CameraReadinessView(
            calibrationExerciseType: CalibrationDefaults.exerciseType,
            targetReps: CalibrationDefaults.targetReps,
            coach: coachPersonality,
            onCompleted: { record in
                Task {
                    if await calibrationStore.saveCompleted(record) {
                        let events = await trophyStore.updateAll(
                            history: historyStore.summaries,
                            calibrationStatus: calibrationStore.status
                        )
                        appDependencies.analytics.trackCalibrationCompleted(outcome: .completed)
                        appDependencies.analytics.trackTrophyUnlocks(events)
                    }
                }
            },
            onFailed: { record in
                Task {
                    if await calibrationStore.saveFailed(record) {
                        appDependencies.analytics.trackCalibrationCompleted(outcome: .failed)
                    }
                }
            }
        )
    }

    private var coachPersonality: CoachPersonality {
        onboardingStore.profile?.preferredCoach.coachPersonality ?? .good
    }
}

private struct CalibrationInfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

#Preview {
    CalibrationIntroView()
        .environmentObject(OnboardingStore())
        .environmentObject(CalibrationStore())
        .environmentObject(WorkoutHistoryStore())
        .environmentObject(TrophyStore())
        .environmentObject(AppDependencies.local())
}
