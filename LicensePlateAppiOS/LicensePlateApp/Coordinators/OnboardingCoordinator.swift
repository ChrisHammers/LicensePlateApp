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
        case ageVerification
        case accountCreation
        case avatarPicker
        case joinFamily
        case createFamily
        case premiumUpsell
        case permissions
        case getStarted
    }

    /// F-6 (FR-27): age-gate reads, injected for tests. Owner placement: the age
    /// question sits AFTER the welcome/disclaimer intro and immediately BEFORE account
    /// creation — the user first sees what the game is, then is asked.
    var isAgeGateResolved: () -> Bool = { AgeGateStore.shared.isResolved }
    var ageGateCategory: () -> AgeGateCategory? = { AgeGateStore.shared.category }

    /// FR-27: the age step precedes account creation whenever this identity epoch has
    /// no answer (pure routing decision — unit tested).
    static func stepAfterDisclaimer(isAgeGateResolved: Bool) -> Step {
        isAgeGateResolved ? .accountCreation : .ageVerification
    }

    /// FR-27: under-13 routes join-family-only — a child never sees createFamily
    /// (server rejects child `createFamily` callers regardless, FR-24).
    static func familySetupStep(ageCategory: AgeGateCategory?) -> Step {
        ageCategory == .under13 ? .joinFamily : .createFamily
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
            stepStack.append(Self.stepAfterDisclaimer(isAgeGateResolved: isAgeGateResolved()))
        case .ageVerification:
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
            stepStack.append(Self.familySetupStep(ageCategory: ageGateCategory()))
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
    /// COPPA F-7 (FR-34-amended/D-14): child sessions are NOT skipped — the step view
    /// itself renders the informational child variant instead of the paywall, so a
    /// product re-enable here stays correct for children with no further change.
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
