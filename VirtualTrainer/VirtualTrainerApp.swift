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
        }
    }
}
