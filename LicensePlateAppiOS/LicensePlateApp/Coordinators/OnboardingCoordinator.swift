//
//  OnboardingCoordinator.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI
import Combine

/// Coordinator for onboarding flow (Sign In vs Create, optional family setup)
@MainActor
final class OnboardingCoordinator: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case disclaimer
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
    @Published var didLogIn = false
    @Published var isExistingAccount = false
    
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
    // [.welcome, .disclaimer, .accountCreation]
    
    
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
            stepStack.append(.disclaimer)
        case .disclaimer:
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
            let offline = !(authService?.isOnline ?? true)
            FirstSessionAnalyticsService.shared.recordOnboardingCompleted(flowVariant: .legacy, offline: offline)
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
    
    private func advanceFromAvatarPicker() {
        if !didLogIn {
            stepStack.append(.permissions)
            return
        }
        let hasFamily = (authService?.currentUser?.activeFamilyId != nil)
        if !hasFamily {
            stepStack.append(.createFamily)//(userType == .scout ? .joinFamily : .createFamily)
        } else if shouldShowPremiumUpsell {
            stepStack.append(.premiumUpsell)
        } else {
            stepStack.append(.permissions)
        }
    }
    
    private func advanceFromJoinFamily() {
        if shouldShowPremiumUpsell {
            stepStack.append(.premiumUpsell)
        } else {
            stepStack.append(.permissions)
        }
    }
    
    private func advanceFromCreateFamily() {
        if shouldShowPremiumUpsell {
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
    
    /// Whether to show premium upsell during onboarding (disabled until product re-enables).
    var shouldShowPremiumUpsell: Bool {
        false
        // TODO: re-enable onboarding premium upsell
        // didLogIn && !hasPremium
    }
    
    private var hasPremium: Bool {
        RevenueCatEntitlementBridge.shared.hasActiveEntitlement(for: .gold)
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
