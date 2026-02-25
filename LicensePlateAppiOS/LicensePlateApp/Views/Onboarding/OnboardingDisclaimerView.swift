//
//  OnboardingDisclaimerView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI

struct OnboardingDisclaimerView: View {
    let onAgree: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.Theme.accentYellow)
                
                Text("Important Safety Notice")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Do not use this app while driving.")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("Only use RoadTrip Royale when you are a passenger or when the vehicle is safely parked. Your safety and the safety of others is our top priority.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("By continuing, you agree to our Terms of Service and Privacy Policy.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding()
                .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                
                Button("I Agree") {
                    onAgree()
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.Theme.primaryBlue, in: Capsule())
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .padding(.vertical, 48)
        }
    }
}
