//
//  VirtualTrainerApp.swift
//  VirtualTrainer
//
//  Created by Satvik Bansal on 28/02/26.
//
import SwiftUI

@main
struct VirtualTrainerApp: App {
    @StateObject private var backendStatusStore: BackendStatusStore
    @StateObject private var appDependencies: AppDependencies
    @StateObject private var syncOrchestrator: SyncOrchestrator
    @StateObject private var accountContext = AccountContext()
    @StateObject private var onboardingStore = OnboardingStore()
    @StateObject private var calibrationStore = CalibrationStore()
    @StateObject private var workoutHistoryStore = WorkoutHistoryStore()
    @StateObject private var trophyStore = TrophyStore()
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var insightStore = InsightStore()

    init() {
        let statusStore = BackendStatusStore()
#if DEBUG
        if statusStore.activeBackendMode == .firebase {
            FirebaseSmokeVerifier.runIfRequested()
        }
#endif

        let dependencies = AppDependencies.from(statusStore)
        _backendStatusStore = StateObject(wrappedValue: statusStore)
        _appDependencies = StateObject(wrappedValue: dependencies)
        _syncOrchestrator = StateObject(wrappedValue: SyncOrchestrator(dependencies: dependencies))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !onboardingStore.hasCompletedOnboarding {
                    OnboardingFlowView()
                } else if calibrationStore.shouldShowCalibrationGate {
                    CalibrationIntroView()
                } else {
                    MainTabView()
                }
            }
            .environmentObject(accountContext)
            .environmentObject(onboardingStore)
            .environmentObject(calibrationStore)
            .environmentObject(workoutHistoryStore)
            .environmentObject(trophyStore)
            .environmentObject(themeStore)
            .environmentObject(insightStore)
            .environmentObject(backendStatusStore)
            .environmentObject(appDependencies)
            .environmentObject(syncOrchestrator)
            .onAppear {
                configureStoreRemoteSync()
                syncStoresWithAccount()
                Task {
                    await themeStore.sync(with: onboardingStore.profile)
                }
            }
            .onChange(of: accountContext.currentAccountId) {
                syncStoresWithAccount()
                Task {
                    await themeStore.sync(with: onboardingStore.profile)
                }
            }
            .onChange(of: onboardingStore.profile) {
                Task {
                    await themeStore.sync(with: onboardingStore.profile)
                }
            }
            .task(id: backendStatusStore.activeBackendMode) {
                await observeFirebaseAuthChangesIfNeeded()
            }
        }
    }

    @MainActor
    private func observeFirebaseAuthChangesIfNeeded() async {
        guard backendStatusStore.activeBackendMode == .firebase else { return }

        let coordinator = AccountClaimCoordinator(
            accountContext: accountContext,
            stores: accountAwareStores(),
            writeJournal: LocalWriteJournal()
        )

        do {
            let authChanges = try await appDependencies.auth.observeAuthChanges()
            for await uid in authChanges {
                await coordinator.handleAuthChange(uid)
            }
        } catch {
            accountContext.clearAccount()
            syncStoresWithAccount()
        }
    }

    @MainActor
    private func accountAwareStores() -> AccountAwareStores {
        AccountAwareStores(
            onboardingStore: onboardingStore,
            workoutHistoryStore: workoutHistoryStore,
            trophyStore: trophyStore,
            insightStore: insightStore,
            calibrationStore: calibrationStore,
            themeStore: themeStore
        )
    }

    private func syncStoresWithAccount() {
        let accountId = accountContext.currentAccountId
        onboardingStore.setCurrentAccountId(accountId)
        calibrationStore.setCurrentAccountId(accountId)
        workoutHistoryStore.setCurrentAccountId(accountId)
        trophyStore.setCurrentAccountId(accountId)
        themeStore.setCurrentAccountId(accountId)
        insightStore.setCurrentAccountId(accountId)
    }

    private func configureStoreRemoteSync() {
        onboardingStore.configureRemoteSync(
            backendMode: appDependencies.backendMode,
            profileRepository: appDependencies.profile
        )
        themeStore.configureRemoteSync(
            backendMode: appDependencies.backendMode,
            themeRepository: appDependencies.theme
        )
        calibrationStore.configureRemoteSync(
            backendMode: appDependencies.backendMode,
            calibrationRepository: appDependencies.calibration
        )
        workoutHistoryStore.configureRemoteSync(
            backendMode: appDependencies.backendMode,
            workoutRepository: appDependencies.workouts
        )
        syncOrchestrator.configureWorkoutPush(
            localStore: workoutHistoryStore,
            workoutRepository: appDependencies.workouts
        )
    }
}
