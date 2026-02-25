//
//  OnboardingPremiumUpsellView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI

struct OnboardingPremiumUpsellView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onNext: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text("Upgrade to Premium")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("Get more from RoadTrip Royale with premium features.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    Text("Premium benefits coming soon")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                
                VStack(spacing: 12) {
                    Button("Continue") {
                        onNext()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.Theme.primaryBlue, in: Capsule())
                    
                    Button("Skip") {
                        onSkip()
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 48)
        }
    }
}
