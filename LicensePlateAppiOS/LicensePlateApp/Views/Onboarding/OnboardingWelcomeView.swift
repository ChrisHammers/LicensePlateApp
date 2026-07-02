//
//  OnboardingWelcomeView.swift
//  LicensePlateApp
//
//  Combined welcome + product overview (fixed layout, no scroll).
//

import SwiftUI

struct OnboardingWelcomeView: View {
    @EnvironmentObject private var authService: FirebaseAuthService
    let onNext: () -> Void
    
    private let overviewRows: [(icon: String, titleKey: String, descriptionKey: String)] = [
        ("mic.fill", "onboarding.intro.spot_voice.title", "onboarding.intro.spot_voice.description"),
        ("map.fill", "onboarding.intro.map_trips.title", "onboarding.intro.map_trips.description"),
        ("globe.americas.fill", "onboarding.intro.regions.title", "onboarding.intro.regions.description"),
        ("person.2.fill", "onboarding.intro.friends_family.title", "onboarding.intro.friends_family.description")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            
            VStack(spacing: 16) {
                Image(systemName: "car.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibleDecorative()
                
                VStack(spacing: 8) {
                    Text("RoadTrip Royale".localized)
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibleHeader("RoadTrip Royale".localized)
                    
                    Text("Spot license plates, conquer the map, and rule the open road!".localized)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                VStack(spacing: 10) {
                    ForEach(Array(overviewRows.enumerated()), id: \.offset) { _, row in
                        WelcomeOverviewRow(
                            icon: row.icon,
                            title: row.titleKey.localized,
                            description: row.descriptionKey.localized
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
            
            Spacer(minLength: 0)
            
            Button {
                onNext()
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
            .accessibleButton(label: "Get Started".localized, hint: "Continues to next screen".localized)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .onAppear {
            FirstSessionAnalyticsService.shared.recordOnboardingStarted(
                flowVariant: .legacy,
                offline: !authService.isOnline
            )
            FirstSessionAnalyticsService.shared.recordOnboardingStepViewed(
                stepId: "welcome",
                stepIndex: 0,
                flowVariant: .legacy
            )
        }
    }
}

private struct WelcomeOverviewRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.Theme.primaryBlue)
                .frame(width: 32, height: 32)
                .background(Color.Theme.primaryBlue.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .accessibleDecorative()
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                Text(description)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
}

#Preview("Welcome + Overview") {
    OnboardingWelcomeView(onNext: {})
        .environmentObject(FirebaseAuthService())
}
