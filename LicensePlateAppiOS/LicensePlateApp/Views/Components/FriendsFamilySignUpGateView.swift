//
//  FriendsFamilySignUpGateView.swift
//  LicensePlateApp
//
//  Sign-up prompt when guest-like users attempt Friends & Family features.
//

import SwiftUI
import Combine

enum FriendsFamilyGateFeature {
    case friends
    case family

    var navigationTitle: String {
        switch self {
        case .friends: return "Friends".localized
        case .family: return "Family".localized
        }
    }

    var iconName: String {
        switch self {
        case .friends: return "person.2.fill"
        case .family: return "house.fill"
        }
    }

    var analyticsFeatureName: String {
        switch self {
        case .friends: return "friends"
        case .family: return "family"
        }
    }
}

@MainActor
final class FriendsFamilySignUpGateViewModel: ObservableObject {
    let feature: FriendsFamilyGateFeature

    init(feature: FriendsFamilyGateFeature) {
        self.feature = feature
    }

    func onAppear() {
        AnalyticsService.shared.log(.friendsFamilySignUpGateShown(feature: feature.analyticsFeatureName))
    }
}

struct FriendsFamilySignUpPrompt: View {
    @EnvironmentObject var authService: FirebaseAuthService
    var showsIcon: Bool = true

    var body: some View {
        VStack(spacing: 16) {
            if showsIcon {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.Theme.accentYellow)
                    .accessibleDecorative()
            }

            Text("Sign up for Friends & Family".localized)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .multilineTextAlignment(.center)
                .accessibleHeader("Sign up for Friends & Family".localized)
                .supportsDynamicType()

            Text("Create a free account to add friends, join families, and play shared road trips.".localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .multilineTextAlignment(.center)
                .supportsDynamicType()

            Button {
                authService.showSignInSheet = true
            } label: {
                HStack {
                    Text("Sign In or Create Account".localized)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.Theme.primaryBlue)
                )
            }
            .accessibleButton(
                label: "Sign In or Create Account".localized,
                hint: "Opens sign in or account creation".localized
            )
        }
    }
}

struct FriendsFamilySignUpGateView: View {
    @EnvironmentObject var authService: FirebaseAuthService
    let feature: FriendsFamilyGateFeature
    @StateObject private var viewModel: FriendsFamilySignUpGateViewModel

    init(feature: FriendsFamilyGateFeature) {
        self.feature = feature
        _viewModel = StateObject(wrappedValue: FriendsFamilySignUpGateViewModel(feature: feature))
    }

    private var combinedAccessibilityLabel: String {
        [
            "Sign up for Friends & Family".localized,
            "Create a free account to add friends, join families, and play shared road trips.".localized
        ].joined(separator: ". ")
    }

    var body: some View {
        AppBackgroundView {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: feature.iconName)
                    .font(.system(size: 60))
                    .foregroundStyle(Color.Theme.accentYellow)
                    .accessibleDecorative()

                FriendsFamilySignUpPrompt(showsIcon: false)
                    .padding(.horizontal, 24)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(combinedAccessibilityLabel)
        }
        .navigationTitle(feature.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.onAppear()
        }
    }
}

struct RegisteredAccountGate<Content: View>: View {
    @EnvironmentObject var authService: FirebaseAuthService
    let feature: FriendsFamilyGateFeature
    @ViewBuilder let content: () -> Content

    private var isGuestLike: Bool {
        !FriendsFamilyAccessPolicy.shared.canUseFriendsAndFamily(for: authService.currentUser)
    }

    var body: some View {
        if isGuestLike {
            FriendsFamilySignUpGateView(feature: feature)
        } else {
            content()
        }
    }
}

#Preview("Friends gate") {
    NavigationStack {
        FriendsFamilySignUpGateView(feature: .friends)
            .environmentObject(FirebaseAuthService())
    }
}

#Preview("Registered gate wrapper") {
    NavigationStack {
        RegisteredAccountGate(feature: .family) {
            Text("Family content")
        }
        .environmentObject(FirebaseAuthService())
    }
}

#Preview("Compact prompt") {
    FriendsFamilySignUpPrompt()
        .environmentObject(FirebaseAuthService())
        .padding()
}
