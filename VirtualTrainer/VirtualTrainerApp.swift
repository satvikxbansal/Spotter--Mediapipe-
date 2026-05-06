//
//  VirtualTrainerApp.swift
//  VirtualTrainer
//
//  Created by Satvik Bansal on 28/02/26.
//
import SwiftUI

@main
struct VirtualTrainerApp: App {
    @StateObject private var onboardingStore = OnboardingStore()
    @StateObject private var calibrationStore = CalibrationStore()
    @StateObject private var workoutHistoryStore = WorkoutHistoryStore()
    @StateObject private var trophyStore = TrophyStore()
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var insightStore = InsightStore()

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
            .environmentObject(onboardingStore)
            .environmentObject(calibrationStore)
            .environmentObject(workoutHistoryStore)
            .environmentObject(trophyStore)
            .environmentObject(themeStore)
            .environmentObject(insightStore)
            .onAppear {
                themeStore.sync(with: onboardingStore.profile)
            }
            .onChange(of: onboardingStore.profile) {
                themeStore.sync(with: onboardingStore.profile)
            }
        }
    }
}
