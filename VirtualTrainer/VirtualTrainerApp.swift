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

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingStore.hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingFlowView()
                }
            }
            .environmentObject(onboardingStore)
        }
    }
}
