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
    /// COPPA F-7 (FR-34-amended/D-14) rendered projection.
    @ObservedObject private var childPostures = ChildSessionPostureCoordinator.shared
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        // Child sessions see the informational variant in the same step — never
        // pricing/purchase UI. Continue advances the flow exactly like the paywall's
        // primary action.
        switch ChildPremiumSheetVariant.variant(purchasesSuppressed: childPostures.arePurchasesSuppressed) {
        case .childInfo:
            ChildPremiumInfoView(
                context: .premiumIntro,
                primaryActionTitle: "Continue".localized,
                onDismiss: onNext
            )
        case .paywall:
            PaywallView(
                viewModel: paywallViewModel,
                onDismiss: onSkip,
                primaryActionTitle: "Continue".localized,
                primaryAction: onNext
            )
        }
    }
}
