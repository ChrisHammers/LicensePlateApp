//
//  AppCoordinator.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI
import Combine

/// Root-level coordinator for app flow: Splash → Onboarding (if first launch) → Main App
@MainActor
final class AppCoordinator: ObservableObject {
    enum RootView: Equatable {
        case splash
        case onboarding
        case main
    }
    
    @Published var rootView: RootView = .splash
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding = false
    
    // MARK: - Navigation Methods
    
    /// Transition from splash to next view (onboarding or main)
    func transitionFromSplash() {
        if hasSeenOnboarding {
            showMainApp()
        } else {
            showOnboarding()
        }
    }
    
    /// Show onboarding flow
    func showOnboarding() {
        rootView = .onboarding
    }
    
    /// Complete onboarding and show main app
    func completeOnboarding() {
        hasSeenOnboarding = true
        showMainApp()
    }
    
    /// Show main app (ContentView)
    func showMainApp() {
        rootView = .main
    }
}
