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

/// Which surface `RegisteredAccountGate` shows. Extracted from the view body so the
/// child's route INTO a family is pinned by a test: only `.childGate(.unconsented)` and
/// `.content` carry share-code entry, and an unconsented child must land on the former.
enum FriendsFamilyGateRouting: Equatable {
    case signUpGate
    case childGate(ChildAccountGateView.GateState)
    case content

    /// COPPA FR-85 (F-42): child status is resolved BEFORE the guest gate, and this order
    /// is load-bearing. FR-60 made BOTH child postures guest-like at the auth layer — an
    /// unconsented child has no Firebase account at all, and a consented child holds an
    /// ANONYMOUS one — so a registration-first test routes every child to a sign-up screen
    /// they can never satisfy: the consented child loses the family surface they were
    /// admitted to, and the unconsented child loses share-code entry, the only path to
    /// consent. Registration is no longer a proxy for "legitimate member"; for a consented
    /// child, family membership IS the credential (OD-2).
    ///
    /// This is a UI route, not an authorization decision: every callable behind it keeps its
    /// own server gate (`assertRegisteredAccountOrDeclaredChild` / `assertCallerIsNotChild`)
    /// and the family data behind `.content` is still fetched under `firestore.rules`.
    /// Friends stay closed to consented children (FR-14/24) exactly as before, and an adult
    /// guest still meets the sign-up gate.
    static func destination(
        isGuestLike: Bool,
        childState: ChildRestrictedModeService.ChildSessionState,
        feature: FriendsFamilyGateFeature
    ) -> FriendsFamilyGateRouting {
        switch childState {
        case .unconsentedChild:
            // Both features route through consent: joining a family IS the path.
            return .childGate(.unconsented)
        case .consentedChild:
            // Friends are not part of child accounts (FR-14/24); family play is.
            return feature == .friends ? .childGate(.consented) : .content
        case .notChild:
            return isGuestLike ? .signUpGate : .content
        }
    }

    /// True when the surface offers share-code entry — the child's designated way in
    /// (FR-24 keeps `redeemShareCode` open to children server-side).
    var offersShareCodeEntry: Bool {
        switch self {
        case .childGate(let state): return state == .unconsented
        case .content: return true
        case .signUpGate: return false
        }
    }
}

struct RegisteredAccountGate<Content: View>: View {
    @EnvironmentObject var authService: FirebaseAuthService
    /// Re-renders the gate when the effective child signal changes mid-session (FR-23
    /// seam) — e.g. a server-side correction or re-grant arriving while this tab is on
    /// screen. `childSessionState` itself is computed fresh on every body evaluation;
    /// this only guarantees an evaluation happens at the flip.
    @ObservedObject private var postureCoordinator = ChildSessionPostureCoordinator.shared
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
        switch FriendsFamilyGateRouting.destination(
            isGuestLike: isGuestLike,
            childState: childState,
            feature: feature
        ) {
        case .signUpGate:
            FriendsFamilySignUpGateView(feature: feature)
        case .childGate(let state):
            ChildAccountGateView(feature: feature, state: state)
        case .content:
            content()
        }
    }
}

// MARK: - Child account gate (COPPA F-6 rework)

/// Non-punitive gate shown BEFORE any server rejection when a child session opens a
/// blocked Friends & Family entry point. Mirrors `FriendsFamilySignUpGateView`'s
/// visual pattern. Deliberately logs NO analytics: an event here would fire only for
/// child sessions on the child's own instance (forbidden by FR-21 / SRS §12).
struct ChildAccountGateView: View {
    enum GateState: Equatable {
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
