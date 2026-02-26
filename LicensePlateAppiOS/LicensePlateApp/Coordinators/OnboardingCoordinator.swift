//
//  OnboardingCoordinator.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI
import Combine

/// User type for onboarding flow branching
enum OnboardingUserType: String, CaseIterable {
    case captain  // Parent - can create families
    case scout    // Child - must join family
}

/// Coordinator for onboarding flow with branching (Captain vs Scout, Sign In vs Create)
@MainActor
final class OnboardingCoordinator: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case howItWorks
        case features
        case disclaimer
        case userTypeAndBirthYear
        case accountCreation
        case joinFamily
        case createFamily
        case premiumUpsell
        case permissions
        case getStarted
    }
    
    @Published var currentStep: Step = .welcome
    @Published var isGoingForward = true
    @Published var userType: OnboardingUserType?
    @Published var didLogIn = false
    @Published var isExistingAccount = false
    
    @AppStorage("onboardingBirthYear") var birthYear: Int = 0
    
    private weak var appCoordinator: AppCoordinator?
    
    init(appCoordinator: AppCoordinator? = nil) {
        self.appCoordinator = appCoordinator
    }
    
    func setAppCoordinator(_ coordinator: AppCoordinator) {
        self.appCoordinator = coordinator
    }
    
    // MARK: - Step Order (for linear flow before branching)
    
    private var linearSteps: [Step] {
        [.welcome, .howItWorks, .features, .disclaimer, .userTypeAndBirthYear, .accountCreation]
    }
    
    // MARK: - Navigation
    
    /// Advance to next step (defer step change so view updates direction first, ensuring both views use same transition)
    func nextStep() {
        isGoingForward = true
        DispatchQueue.main.async { [weak self] in
            self?.performNextStep()
        }
    }
    
    private func performNextStep() {
        switch currentStep {
        case .welcome:
            currentStep = .howItWorks
        case .howItWorks:
            currentStep = .features
        case .features:
            currentStep = .disclaimer
        case .disclaimer:
            currentStep = .userTypeAndBirthYear
        case .userTypeAndBirthYear:
            currentStep = .accountCreation
        case .accountCreation:
            advanceFromAccountCreation()
        case .joinFamily:
            advanceFromJoinFamily()
        case .createFamily:
            advanceFromCreateFamily()
        case .premiumUpsell:
            currentStep = .permissions
        case .permissions:
            currentStep = .getStarted
        case .getStarted:
            appCoordinator?.completeOnboarding()
        }
    }
    
    /// Go back one step (defer step change so view updates direction first, ensuring both views use same transition)
    func previousStep() {
        isGoingForward = false
        DispatchQueue.main.async { [weak self] in
            self?.performPreviousStep()
        }
    }
    
    private func performPreviousStep() {
        switch currentStep {
        case .welcome:
            break
        case .howItWorks:
            currentStep = .welcome
        case .features:
            currentStep = .howItWorks
        case .disclaimer:
            currentStep = .features
        case .userTypeAndBirthYear:
            currentStep = .disclaimer
        case .accountCreation:
            currentStep = .userTypeAndBirthYear
        case .joinFamily:
            currentStep = .accountCreation
        case .createFamily:
            currentStep = .accountCreation
        case .premiumUpsell:
            // Came from account creation (existing account) - go back there
            currentStep = .accountCreation
        case .permissions:
            currentStep = .premiumUpsell
        case .getStarted:
            currentStep = .permissions
        }
    }
    
    private func advanceFromAccountCreation() {
        if isExistingAccount {
            // Sign In path: skip Create/Join Family → Premium Upsell (if not premium) → Permissions
            if didLogIn && shouldShowPremiumUpsell {
                currentStep = .premiumUpsell
            } else {
                currentStep = .permissions
            }
        } else {
            // New account or guest: Create Family (Captain) or Join Family (Scout)
            if userType == .scout {
                currentStep = .joinFamily
            } else {
                currentStep = .createFamily
            }
        }
    }
    
    private func advanceFromJoinFamily() {
        if didLogIn && shouldShowPremiumUpsell {
            currentStep = .premiumUpsell
        } else {
            currentStep = .permissions
        }
    }
    
    private func advanceFromCreateFamily() {
        if didLogIn && shouldShowPremiumUpsell {
            currentStep = .premiumUpsell
        } else {
            currentStep = .permissions
        }
    }
    
    // MARK: - Helpers
    
    var isFirstStep: Bool {
        currentStep == .welcome
    }
    
    var isLastStep: Bool {
        currentStep == .getStarted
    }
    
    /// Whether to show premium upsell (logged in and not already premium)
    var shouldShowPremiumUpsell: Bool {
        didLogIn && !hasPremium  // TODO: check hasPremium when paid tier exists
    }
    
    private var hasPremium: Bool {
        false  // Placeholder until paid tier exists
    }
    
    /// Skip premium upsell and go to permissions
    func skipPremiumUpsell() {
        isGoingForward = true
        DispatchQueue.main.async { [weak self] in
            self?.currentStep = .permissions
        }
    }
}
