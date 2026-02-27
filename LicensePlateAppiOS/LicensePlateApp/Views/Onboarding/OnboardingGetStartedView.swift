//
//  OnboardingGetStartedView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI

struct OnboardingGetStartedView: View {
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                Image(systemName: "car.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("You're All Set!".localized)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("Start spotting license plates and conquering the map.".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button {
                onComplete()
            } label: {
                Text("Get Started".localized)
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
