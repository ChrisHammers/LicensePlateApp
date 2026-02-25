//
//  OnboardingContainerView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI
import SwiftData

struct OnboardingContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var authService: FirebaseAuthService
    @ObservedObject var coordinator: OnboardingCoordinator
    let appCoordinator: AppCoordinator
    
    init(coordinator: OnboardingCoordinator, appCoordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.appCoordinator = appCoordinator
        coordinator.setAppCoordinator(appCoordinator)
    }
    
    var body: some View {
        ZStack {
            Color.Theme.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Content area
                Group {
                    switch coordinator.currentStep {
                    case .welcome:
                        OnboardingWelcomeView(onNext: { coordinator.nextStep() })
                    case .howItWorks:
                        OnboardingHowItWorksView(onNext: { coordinator.nextStep() })
                    case .features:
                        OnboardingFeaturesView(onNext: { coordinator.nextStep() })
                    case .disclaimer:
                        OnboardingDisclaimerView(onAgree: { coordinator.nextStep() })
                    case .userTypeAndBirthYear:
                        OnboardingUserTypeView(
                            coordinator: coordinator,
                            onNext: { coordinator.nextStep() }
                        )
                    case .accountCreation:
                        OnboardingAccountCreationView(
                            coordinator: coordinator,
                            onNext: { coordinator.nextStep() }
                        )
                    case .joinFamily:
                        OnboardingJoinFamilyView(
                            coordinator: coordinator,
                            onNext: { coordinator.nextStep() }
                        )
                    case .createFamily:
                        OnboardingCreateFamilyView(
                            coordinator: coordinator,
                            onNext: { coordinator.nextStep() }
                        )
                    case .premiumUpsell:
                        OnboardingPremiumUpsellView(
                            coordinator: coordinator,
                            onNext: { coordinator.nextStep() },
                            onSkip: { coordinator.skipPremiumUpsell() }
                        )
                    case .permissions:
                        OnboardingPermissionsView(
                            coordinator: coordinator,
                            onNext: { coordinator.nextStep() }
                        )
                    case .getStarted:
                        OnboardingGetStartedView(onComplete: {
                            coordinator.nextStep()
                        })
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                
                Spacer(minLength: 0)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: coordinator.currentStep)
    }
}
