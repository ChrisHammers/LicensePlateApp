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

    /// F-6 rework: pre-emptive, advisory child gating composed with the guest gate
    /// (server callable gates remain the authority).
    private var childState: ChildRestrictedModeService.ChildSessionState {
        ChildRestrictedModeService.shared.childSessionState
    }

    var body: some View {
        if isGuestLike {
            FriendsFamilySignUpGateView(feature: feature)
        } else {
            switch childState {
            case .unconsentedChild:
                // Both features route through consent: joining a family IS the path.
                ChildAccountGateView(feature: feature, state: .unconsented)
            case .consentedChild where feature == .friends:
                // Friends are not part of child accounts (FR-14/24); family play is.
                ChildAccountGateView(feature: feature, state: .consented)
            default:
                content()
            }
        }
    }
}

// MARK: - Child account gate (COPPA F-6 rework)

/// Non-punitive gate shown BEFORE any server rejection when a child session opens a
/// blocked Friends & Family entry point. Mirrors `FriendsFamilySignUpGateView`'s
/// visual pattern. Deliberately logs NO analytics: an event here would fire only for
/// child sessions on the child's own instance (forbidden by FR-21 / SRS §12).
struct ChildAccountGateView: View {
    enum GateState {
        /// No family yet — joining one is how consent happens.
        case unconsented
        /// In a family — friends features simply are not part of child accounts.
        case consented
    }

    let feature: FriendsFamilyGateFeature
    let state: GateState

    @State private var showJoinFamilySheet = false

    private var title: String {
        switch state {
        case .unconsented: return "child_gate.screen.join_title".localized
        case .consented: return "child_gate.screen.friends_title".localized
        }
    }

    private var bodyText: String {
        switch state {
        case .unconsented: return "child_gate.screen.join_body".localized
        case .consented: return "child_gate.screen.friends_body".localized
        }
    }

    var body: some View {
        AppBackgroundView {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: feature.iconName)
                    .font(.system(size: 60))
                    .foregroundStyle(Color.Theme.accentYellow)
                    .accessibleDecorative()

                VStack(spacing: 16) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .multilineTextAlignment(.center)
                        .accessibleHeader(title)
                        .supportsDynamicType()

                    Text(bodyText)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .multilineTextAlignment(.center)
                        .supportsDynamicType()

                    if state == .unconsented {
                        Button {
                            showJoinFamilySheet = true
                        } label: {
                            HStack {
                                Text("Join a Family".localized)
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
                            label: "Join a Family".localized,
                            hint: "child_gate.screen.join_button_hint".localized
                        )
                    }
                }
                .padding(.horizontal, 24)
                .accessibilityElement(children: .contain)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(feature.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showJoinFamilySheet) {
            JoinFamilySheet()
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

#Preview("Child gate — join family") {
    NavigationStack {
        ChildAccountGateView(feature: .family, state: .unconsented)
            .environmentObject(FirebaseAuthService())
    }
}

#Preview("Child gate — friends unavailable") {
    NavigationStack {
        ChildAccountGateView(feature: .friends, state: .consented)
            .environmentObject(FirebaseAuthService())
    }
}
