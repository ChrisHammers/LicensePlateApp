//
//  OnboardingFeaturesView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI

struct OnboardingFeaturesView: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    Text("Features")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    VStack(spacing: 16) {
                        FeatureRow(icon: "mic.fill", title: "Voice input", description: "Say state names to log plates quickly")
                        FeatureRow(icon: "person.2.fill", title: "Friends & Family", description: "Compete and share with your crew")
                        FeatureRow(icon: "map.fill", title: "Trip tracking", description: "Track every road trip on the map")
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
            Button {
                onNext()
            } label: {
                Text("Continue")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(Color.Theme.primaryBlue)
                    )
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.Theme.primaryBlue)
                .frame(width: 44, height: 44)
                .background(Color.Theme.primaryBlue.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            
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
