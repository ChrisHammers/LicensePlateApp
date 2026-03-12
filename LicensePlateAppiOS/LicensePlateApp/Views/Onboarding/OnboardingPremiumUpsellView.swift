//
//  OnboardingPremiumUpsellView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow. Uses PaywallView for offerings and purchase/restore.
//

import SwiftUI

struct OnboardingPremiumUpsellView: View {
    @StateObject private var paywallViewModel = PaywallViewModel()
    @ObservedObject var coordinator: OnboardingCoordinator
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        PaywallView(
            viewModel: paywallViewModel,
            onDismiss: onSkip,
            primaryActionTitle: "Continue".localized,
            primaryAction: onNext
        )
    }
}
