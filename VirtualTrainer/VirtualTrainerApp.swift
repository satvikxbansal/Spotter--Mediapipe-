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
    @StateObject private var featureFlagService: RemoteFeatureFlagService
    @StateObject private var designSystemV2Toggle: DesignSystemV2ToggleStore
    @State private var appLevelPresentation = AppLevelPresentationState()
    @State private var didTrackAppOpen = false
    @State private var didAttemptInitialFeatureFlagRefresh = false

    init() {
        let statusStore = BackendStatusStore()
#if DEBUG
        if statusStore.activeBackendMode == .firebase, !AppRuntime.isRunningUnitTests {
            FirebaseSmokeVerifier.runIfRequested()
        }
#endif

        let dependencies = AppDependencies.from(statusStore)
        let featureFlags = statusStore.activeBackendMode == .firebase
            ? RemoteFeatureFlagService.firebase()
            : RemoteFeatureFlagService.local()
        let designSystemV2Toggle = DesignSystemV2ToggleStore(
            remoteFlagSnapshotProvider: {
                featureFlags.snapshot().designSystemV2Enabled
            }
        )
        dependencies.crashReporting.configureLaunchContext(backendMode: dependencies.backendMode)
        _backendStatusStore = StateObject(wrappedValue: statusStore)
        _appDependencies = StateObject(wrappedValue: dependencies)
        _syncOrchestrator = StateObject(wrappedValue: SyncOrchestrator(dependencies: dependencies))
        _featureFlagService = StateObject(wrappedValue: featureFlags)
        _designSystemV2Toggle = StateObject(wrappedValue: designSystemV2Toggle)
    }

    var body: some Scene {
        WindowGroup {
            let isDesignSystemV2Enabled = designSystemV2Toggle.isEffectivelyEnabled
            let rootRoute = SpotterAppRootRoute.resolve(
                isDesignSystemV2Enabled: isDesignSystemV2Enabled,
                hasCompletedOnboarding: onboardingStore.hasCompletedOnboarding,
                shouldShowCalibrationGate: calibrationStore.shouldShowCalibrationGate
            )
            Group {
                switch rootRoute {
                case .v2Root:
                    V2RootView()
                case .v1Onboarding:
                    OnboardingFlowView()
                case .v1Calibration:
                    CalibrationIntroView()
                case .v1MainTabs:
                    MainTabView()
                }
            }
            .id(isDesignSystemV2Enabled)
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
            .environmentObject(featureFlagService)
            .environmentObject(designSystemV2Toggle)
            .environment(\.appLevelPresenter, $appLevelPresentation)
            .onAppear {
                trackAppOpenIfNeeded()
                syncStoresWithAccount()
                Task {
                    await refreshFeatureFlagsForLaunch()
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
            .onChange(of: featureFlagService.flags.backendSyncEnabled) { _, isEnabled in
                Task {
                    await handleBackendSyncFlagChange(isEnabled)
                }
            }
        }
    }

    @MainActor
    private func observeFirebaseAuthChangesIfNeeded() async {
        guard backendStatusStore.activeBackendMode == .firebase else { return }
        await refreshFeatureFlagsForLaunch()

        let coordinator = AccountClaimCoordinator(
            accountContext: accountContext,
            stores: accountAwareStores(),
            writeJournal: LocalWriteJournal()
        )

        do {
            let authChanges = try await appDependencies.auth.observeAuthChanges()
            for await uid in authChanges {
                await coordinator.handleAuthChange(uid)
                appDependencies.crashReporting.setAccountId(uid)
                if let uid {
                    guard featureFlagService.allowsBackendSync else {
                        await stopSyncListenersForRemoteDisable()
                        continue
                    }
                    await performFullSync(accountId: uid)
                } else {
                    await stopSyncListenersForRemoteDisable()
                }
            }
        } catch {
            accountContext.clearAccount()
            syncStoresWithAccount()
            appDependencies.crashReporting.setAccountId(nil)
            appDependencies.analytics.trackSyncError(domain: (error as NSError).domain)
            await stopSyncListenersForRemoteDisable()
        }
    }

    @MainActor
    private func handleBackendSyncFlagChange(_ isEnabled: Bool) async {
        guard backendStatusStore.activeBackendMode == .firebase else { return }
        configureStoreRemoteSync()
        if isEnabled, let accountId = accountContext.currentAccountId {
            await performFullSync(accountId: accountId)
        } else {
            await stopSyncListenersForRemoteDisable()
        }
    }

    @MainActor
    private func performFullSync(accountId: String) async {
        do {
            try await syncOrchestrator.performFullSync(accountId: accountId)
        } catch {
            appDependencies.analytics.trackSyncError(domain: (error as NSError).domain)
        }
    }

    @MainActor
    private func stopSyncListenersForRemoteDisable() async {
        do {
            try await syncOrchestrator.stopListeners()
        } catch {
            appDependencies.analytics.trackSyncError(domain: (error as NSError).domain)
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
        let effectiveBackendMode = featureFlagService.allowsBackendSync
            ? appDependencies.backendMode
            : .local
        onboardingStore.configureRemoteSync(
            backendMode: effectiveBackendMode,
            profileRepository: appDependencies.profile,
            autoObserve: false
        )
        themeStore.configureRemoteSync(
            backendMode: effectiveBackendMode,
            themeRepository: appDependencies.theme,
            autoObserve: false
        )
        calibrationStore.configureRemoteSync(
            backendMode: effectiveBackendMode,
            calibrationRepository: appDependencies.calibration,
            autoObserve: false
        )
        workoutHistoryStore.configureRemoteSync(
            backendMode: effectiveBackendMode,
            workoutRepository: appDependencies.workouts,
            autoObserve: false
        )
        trophyStore.configureRemoteSync(
            backendMode: effectiveBackendMode,
            trophyRepository: appDependencies.trophies,
            autoObserve: false
        )
        insightStore.configureRemoteSync(
            backendMode: effectiveBackendMode,
            insightRepository: appDependencies.insights,
            autoObserve: false
        )
        syncOrchestrator.configure(
            accountIdProvider: { accountContext.currentAccountId },
            profileStore: onboardingStore,
            calibrationStore: calibrationStore,
            workoutHistoryStore: workoutHistoryStore,
            trophyStore: trophyStore,
            insightStore: insightStore
        )
    }

    private func trackAppOpenIfNeeded() {
        guard !didTrackAppOpen else { return }
        didTrackAppOpen = true
        appDependencies.analytics.trackAppOpen()
    }

    @MainActor
    private func refreshFeatureFlagsForLaunch() async {
        if !didAttemptInitialFeatureFlagRefresh {
            await featureFlagService.refresh()
            didAttemptInitialFeatureFlagRefresh = true
        }
        configureStoreRemoteSync()
    }
}
