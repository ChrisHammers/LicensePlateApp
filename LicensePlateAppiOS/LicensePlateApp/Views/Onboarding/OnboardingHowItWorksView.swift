//
//  OnboardingHowItWorksView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI

struct OnboardingHowItWorksView: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    Text("How It Works")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    VStack(alignment: .leading, spacing: 24) {
                        HowItWorksRow(
                            number: 1,
                            title: "Spot plates",
                            description: "Look for license plates as you travel"
                        )
                        HowItWorksRow(
                            number: 2,
                            title: "Mark on map",
                            description: "Log each plate you find on the interactive map"
                        )
                        HowItWorksRow(
                            number: 3,
                            title: "Conquer regions",
                            description: "Track progress across US, Canada, and Mexico"
                        )
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
            Button("Continue") {
                onNext()
            }
            .font(.system(.body, design: .rounded))
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.Theme.primaryBlue, in: Capsule())
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }
}

private struct HowItWorksRow: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.Theme.primaryBlue, in: Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                Text(description)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}
