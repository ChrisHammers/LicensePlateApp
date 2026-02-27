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
    @State private var hasAgreedToSafeDriving = false
    
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
                    
                    Button {
                        hasAgreedToSafeDriving.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: hasAgreedToSafeDriving ? "checkmark.square.fill" : "square")
                                .font(.system(size: 24))
                                .foregroundStyle(hasAgreedToSafeDriving ? Color.Theme.primaryBlue : Color.Theme.softBrown)
                            Text("I agree to the safe driving mandate, Terms of Service and Privacy Policy".localized)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.Theme.primaryBlue)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }
            
            Button {
                onAgree()
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
            .disabled(!hasAgreedToSafeDriving)
            .opacity(hasAgreedToSafeDriving ? 1 : 0.6)
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
