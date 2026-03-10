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
        case avatarPicker
        case joinFamily
        case createFamily
        case premiumUpsell
        case permissions
        case getStarted
    }
    
    /// Navigation stack - acts like NavigationStack; back pops, forward pushes
    @Published private(set) var stepStack: [Step] = [.welcome]
    
    var currentStep: Step {
        stepStack.last ?? .welcome
    }
    
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
    
    // MARK: initial flow order:
    //[.welcome, .howItWorks, .features, .disclaimer, .userTypeAndBirthYear, .accountCreation]
    
    
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
            stepStack.append(.howItWorks)
        case .howItWorks:
            stepStack.append(.features)
        case .features:
            stepStack.append(.disclaimer)
        case .disclaimer:
            stepStack.append(.userTypeAndBirthYear)
        case .userTypeAndBirthYear:
            stepStack.append(.accountCreation)
        case .accountCreation:
            stepStack.append(.avatarPicker)
        case .avatarPicker:
            advanceFromAvatarPicker()
        case .joinFamily:
            advanceFromJoinFamily()
        case .createFamily:
            advanceFromCreateFamily()
        case .premiumUpsell:
            stepStack.append(.permissions)
        case .permissions:
            stepStack.append(.getStarted)
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
        guard stepStack.count > 1 else { return }
        stepStack.removeLast()
    }
    
    private func advanceFromAccountCreation() {
        // Always go to avatar picker next; advanceFromAvatarPicker handles flow after
        stepStack.append(.avatarPicker)
    }
    
    private func advanceFromAvatarPicker() {
        if !didLogIn {
            stepStack.append(.permissions)
            return
        }
        let hasFamily = (authService?.currentUser?.activeFamilyId != nil)
        if !hasFamily {
            stepStack.append(userType == .scout ? .joinFamily : .createFamily)
        } else if shouldShowPremiumUpsell {
            stepStack.append(.premiumUpsell)
        } else {
            stepStack.append(.permissions)
        }
    }
    
    private func advanceFromJoinFamily() {
        if didLogIn && shouldShowPremiumUpsell {
            stepStack.append(.premiumUpsell)
        } else {
            stepStack.append(.permissions)
        }
    }
    
    private func advanceFromCreateFamily() {
        if didLogIn && shouldShowPremiumUpsell {
            stepStack.append(.premiumUpsell)
        } else {
            stepStack.append(.permissions)
        }
    }
    
    // MARK: - Helpers
    
    var isFirstStep: Bool {
        stepStack.count <= 1
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
            self?.stepStack.append(.permissions)
        }
    }
    
    /// Switch from Create Family to Join Family screen
    func switchToJoinFamily() {
        isGoingForward = true
        DispatchQueue.main.async { [weak self] in
            self?.stepStack.append(.joinFamily)
        }
    }
}
