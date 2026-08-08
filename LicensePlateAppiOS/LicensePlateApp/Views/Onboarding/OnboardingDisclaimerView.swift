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

    private let agreementLabel =
        "I agree to the safe driving mandate, Terms of Service and Privacy Policy"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.Theme.accentYellow)
                        .accessibleDecorative()

                    Text("Important Safety Notice".localized)
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .multilineTextAlignment(.center)
                        .accessibleHeader("Important Safety Notice".localized)

                    SafeDrivingPolicyBody(
                        onShowTerms: { showTerms = true },
                        onShowPrivacy: { showPrivacy = true }
                    )
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
                                .accessibleDecorative()
                            Text(agreementLabel.localized)
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
                    .accessibleButton(label: agreementLabel.localized, hint: "Double tap to toggle".localized)
                }
                .padding(.vertical, 48)
                .padding(.bottom, 24)
            }

            Button {
                onAgree()
            } label: {
                Text("Continue".localized)
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
            .accessibleButton(label: "Continue".localized, hint: "Continues to next screen".localized)
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

/// Shared safe-driving policy copy for onboarding and quick-start flows.
struct SafeDrivingPolicyBody: View {
    let onShowTerms: () -> Void
    let onShowPrivacy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep Road Trips Fun — And Safe".localized)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            Text("RoadTrip Royale is designed to be enjoyed by passengers whenever possible.".localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)

            Text("If you're driving, keep your eyes on the road and your hands on the wheel. Never use RoadTrip Royale while operating a vehicle.".localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)

            VStack(alignment: .leading, spacing: 8) {
                Text("If you're the driver:".localized)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)

                bullet("Let a passenger handle the app.")
                bullet("Pull over safely before interacting with the game.")
                bullet("Follow all traffic laws and local regulations.")
            }

            Text("Nothing in RoadTrip Royale is worth risking your safety. Missing a license plate is always better than missing what's happening on the road.".localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)

            VStack(alignment: .leading, spacing: 4) {
                Text("By continuing, you acknowledge that you are responsible for using the app safely.".localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)

                HStack(spacing: 0) {
                    Text("You also agree to our ".localized)
                    Button("Terms of Service".localized) {
                        onShowTerms()
                    }
                    .buttonStyle(.plain)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .underline()
                    .accessibleButton(label: "Terms of Service".localized, hint: "Opens Terms of Service".localized)
                    Text(" and ".localized)
                    Button("Privacy Policy".localized) {
                        onShowPrivacy()
                    }
                    .buttonStyle(.plain)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .underline()
                    .accessibleButton(label: "Privacy Policy".localized, hint: "Opens Privacy Policy".localized)
                    Text(".")
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
            }
        }
    }

    private func bullet(_ key: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.primaryBlue)
                .accessibleDecorative()
            Text(key.localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    return OnboardingDisclaimerView(onAgree: {})
}
