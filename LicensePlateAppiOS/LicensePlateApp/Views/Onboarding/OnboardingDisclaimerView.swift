//
//  OnboardingDisclaimerView.swift
//  LicensePlateApp
//
//  Created for Onboarding flow
//

import SwiftUI

struct OnboardingDisclaimerView: View {
    let onAgree: () -> Void
    @State private var showTerms = false
    @State private var showPrivacy = false
    
    var body: some View {
        VStack(spacing: 0) {
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
                        
                        HStack(spacing: 0) {
                            Text("By continuing, you agree to our ")
                            Button("Terms of Service") {
                                showTerms = true
                            }
                            .buttonStyle(.plain)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                            .underline()
                            Text(" and ")
                            Button("Privacy Policy") {
                                showPrivacy = true
                            }
                            .buttonStyle(.plain)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                            .underline()
                            Text(".")
                        }
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    }
                    .padding()
                    .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
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
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showTerms) {
            NavigationStack {
                TermsView()
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                PrivacyView()
            }
        }
    }
}
