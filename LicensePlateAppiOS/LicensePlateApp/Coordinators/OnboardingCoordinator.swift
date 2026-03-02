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
    private weak var authService: FirebaseAuthService?
    
    init(appCoordinator: AppCoordinator? = nil) {
        self.appCoordinator = appCoordinator
    }
    
    func setAppCoordinator(_ coordinator: AppCoordinator) {
        self.appCoordinator = coordinator
    }
    
    func setAuthService(_ service: FirebaseAuthService) {
        self.authService = service
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
            // Guest skipped family and premium → go back to account; else came from premium
            currentStep = didLogIn ? .premiumUpsell : .accountCreation
        case .getStarted:
            currentStep = .permissions
        }
    }
    
    private func advanceFromAccountCreation() {
        if !didLogIn {
            // Guest: skip family screens
            currentStep = .permissions
            return
        }
        
        // Create or Sign In: use activeFamilyId to determine if we need family setup
        let hasFamily = (authService?.currentUser?.activeFamilyId != nil)
        if !hasFamily {
            if userType == .scout {
                currentStep = .joinFamily
            } else {
                currentStep = .createFamily
            }
        } else if shouldShowPremiumUpsell {
            currentStep = .premiumUpsell
        } else {
            currentStep = .permissions
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
    
    /// Whether to show premium upsell (logged in, not already premium, and not a Child/Scout account)
    var shouldShowPremiumUpsell: Bool {
        didLogIn && !hasPremium && userType != .scout  // Children cannot purchase; skip store
    }
    
    private var hasPremium: Bool {
        false  // TODO: Placeholder until paid tier exists
    }
    
    /// Skip premium upsell and go to permissions
    func skipPremiumUpsell() {
        isGoingForward = true
        DispatchQueue.main.async { [weak self] in
            self?.currentStep = .permissions
        }
    }
}
