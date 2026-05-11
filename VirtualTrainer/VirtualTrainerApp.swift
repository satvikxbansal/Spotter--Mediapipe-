//
//  VirtualTrainerApp.swift
//  VirtualTrainer
//
//  Created by Satvik Bansal on 28/02/26.
//
import SwiftUI

@main
struct VirtualTrainerApp: App {
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
        let dependencies = AppDependencies.local()
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
            .environmentObject(appDependencies)
            .environmentObject(syncOrchestrator)
            .onAppear {
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
        }
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
}
