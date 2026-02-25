//
//  OnboardingWelcomeView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI

struct OnboardingWelcomeView: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "car.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.Theme.primaryBlue)
            
            VStack(spacing: 12) {
                Text("RoadTrip Royale")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("Spot license plates, conquer the map, and rule the open road!")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button("Get Started") {
                onNext()
            }
            .font(.system(.body, design: .rounded))
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.Theme.primaryBlue, in: Capsule())
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}
