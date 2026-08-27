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

    /// What the gate says, as a pure function of the two inputs, so a test can read it back
    /// (same shape as `AuthenticationStatusPolicy.presentation`). The view renders it; it
    /// does not decide it.
    ///
    /// Device pass 2026-08-17 (fix 2): wave 3b taught the home banner and the profile card
    /// to say "your request is waiting", but the FAMILY TAB was left behind — an unconsented
    /// child with a live pending request saw the same "join a family with a share code"
    /// screen as a child who had sent nothing, on the one surface they would actually go to
    /// in order to check. Nothing is added to the flow; only the copy changes.
    struct Presentation: Equatable, Sendable {
        var titleKey: String
        var bodyKey: String
        /// FR-28f: share-code entry is the child's ONLY route into a family, so it survives
        /// every variant that has one. A stale or misdirected request must never strand
        /// them — they can always send another code.
        var showsJoinFamilyButton: Bool
        /// `nil` = keep the feature's own icon. The waiting variant borrows the home
        /// banner's hourglass so the two surfaces read as one status, and so the state has a
        /// non-textual cue that is not a color.
        var iconOverride: String?
        /// Device pass 2026-08-26: badge > 0 must imply a reachable entry point. The
        /// Settings "Family" row badges pending invites for EVERY session, but an
        /// unconsented child routes HERE, not to `FamilyDashboard` — so the envelope the
        /// dashboard would have shown never renders, and the child sees a red badge they
        /// cannot open. This surface therefore lists the invites itself whenever any exist.
        /// Invites only, never approvals: approvals belong to captains, and a no-family
        /// child can have none.
        var showsPendingInvitesButton: Bool = false
    }

    static func presentation(
        state: GateState,
        isFamilyApprovalPending: Bool,
        pendingFamilyInvitesCount: Int = 0
    ) -> Presentation {
        // FR-28f's never-stranded rule extends to invites: whichever unconsented variant is
        // showing, an addressed invite is a route into a family and must stay reachable.
        let showsPendingInvites = pendingFamilyInvitesCount > 0
        switch state {
        case .unconsented where isFamilyApprovalPending:
            return Presentation(
                // Reuses the banner's waiting title verbatim — a child chasing "did my code
                // go through?" gets one answer on the home screen, in their profile, and
                // here.
                titleKey: "child_gate.family_prompt.pending_title",
                // The profile card's pending body, not the banner's subtitle: this screen
                // still shows the join button, and this is the string that explains it
                // ("You can enter a different family code if you need to").
                bodyKey: "auth_status.child.pending_guidance_body",
                showsJoinFamilyButton: true,
                iconOverride: "hourglass",
                showsPendingInvitesButton: showsPendingInvites
            )
        case .unconsented:
            return Presentation(
                titleKey: "child_gate.screen.join_title",
                bodyKey: "child_gate.screen.join_body",
                showsJoinFamilyButton: true,
                iconOverride: nil,
                showsPendingInvitesButton: showsPendingInvites
            )
        case .consented:
            // A consented child has a family, so there is nothing to wait for — the pending
            // flag is cleared the moment membership arrives. Ignoring it here means a flag
            // that somehow outlived its own clear cannot put "waiting" on top of a session
            // that is already in. Same for invites: this session reaches FamilyDashboard
            // (`.content`), which has its own envelope.
            return Presentation(
                titleKey: "child_gate.screen.friends_title",
                bodyKey: "child_gate.screen.friends_body",
                showsJoinFamilyButton: false,
                iconOverride: nil,
                showsPendingInvitesButton: false
            )
        }
    }

    let feature: FriendsFamilyGateFeature
    let state: GateState

    /// Carried through to the pending-invites sheet, whose Accept path is the FR-60 second
    /// consent exit. `RegisteredAccountGate`'s environment already provides it.
    @EnvironmentObject private var authService: FirebaseAuthService

    /// Observed, not snapshotted: `revision` is bumped on every mutation of the flag, so the
    /// gate flips to the waiting copy the moment a code is redeemed from the sheet this very
    /// screen presents — and back again when membership arrives — without a navigation
    /// round-trip. This is the same live-update seam the home banner uses.
    @ObservedObject private var childRestrictedMode: ChildRestrictedModeService

    /// Same live badge the Settings "Family" row renders — observing the one authority is
    /// what makes badge > 0 ⟹ entry-point-visible an invariant instead of a coincidence
    /// (`HomeSettingsAvatarButton` precedent).
    @ObservedObject private var socialInboxBadges = SocialInboxBadgeService.shared

    /// Preview / test override. Production passes `nil` so the button observes
    /// `SocialInboxBadgeService` (same seam as `HomeNavigationToolbar`).
    private let pendingInviteBadgeCountOverride: Int?

    @State private var showJoinFamilySheet = false
    @State private var showPendingInvitesSheet = false

    /// The service is injectable for previews only; production always gets the singleton
    /// every other child surface reads, so there is still exactly one pending flag.
    init(
        feature: FriendsFamilyGateFeature,
        state: GateState,
        childRestrictedMode: ChildRestrictedModeService = .shared,
        pendingInviteBadgeCountOverride: Int? = nil
    ) {
        self.feature = feature
        self.state = state
        _childRestrictedMode = ObservedObject(wrappedValue: childRestrictedMode)
        self.pendingInviteBadgeCountOverride = pendingInviteBadgeCountOverride
    }

    private var pendingFamilyInvitesCount: Int {
        pendingInviteBadgeCountOverride ?? socialInboxBadges.pendingFamilyInvitesCount
    }

    private var presentation: Presentation {
        Self.presentation(
            state: state,
            isFamilyApprovalPending: childRestrictedMode.isFamilyApprovalPending,
            pendingFamilyInvitesCount: pendingFamilyInvitesCount
        )
    }

    var body: some View {
        let presentation = self.presentation
        let title = presentation.titleKey.localized
        let bodyText = presentation.bodyKey.localized

        return AppBackgroundView {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: presentation.iconOverride ?? feature.iconName)
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

                    if presentation.showsJoinFamilyButton {
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

                    if presentation.showsPendingInvitesButton {
                        Button {
                            showPendingInvitesSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .accessibleDecorative()
                                Text("Pending Invites".localized)
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                Spacer()
                                BadgeView(count: pendingFamilyInvitesCount)
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(Color.Theme.primaryBlue)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.Theme.cardBackground)
                            )
                        }
                        .accessibleButton(
                            label: "family.a11y.pending_invites".localized(pendingFamilyInvitesCount),
                            hint: "family.a11y.opens_pending_invites".localized
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
        .sheet(isPresented: $showPendingInvitesSheet) {
            // Belt-and-braces explicit injection: the sheet's Accept path runs
            // `respondToFamilyInvite`, the FR-60 second consent exit, which needs the same
            // auth service every other consent surface uses.
            FamilyInvitesView()
                .environmentObject(authService)
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

/// Preview-only: the pending flag is device-local UserDefaults state, so the waiting variant
/// gets its own scratch suite rather than reaching into the shared singleton (or the
/// simulator's real child state).
@MainActor
private func previewPendingChildRestrictedMode() -> ChildRestrictedModeService {
    let defaults = UserDefaults(suiteName: "preview.childAccountGate.pending") ?? .standard
    let service = ChildRestrictedModeService(defaults: defaults)
    service.configure(
        currentUserIdProvider: { "preview-child" },
        activeFamilyIdProvider: { nil }
    )
    service.markFamilyApprovalPending()
    return service
}

#Preview("Child gate — waiting for approval") {
    NavigationStack {
        ChildAccountGateView(
            feature: .family,
            state: .unconsented,
            childRestrictedMode: previewPendingChildRestrictedMode()
        )
        .environmentObject(FirebaseAuthService())
    }
}

#Preview("Child gate — pending invite waiting") {
    NavigationStack {
        ChildAccountGateView(
            feature: .family,
            state: .unconsented,
            pendingInviteBadgeCountOverride: 1
        )
        .environmentObject(FirebaseAuthService())
    }
}

#Preview("Child gate — waiting, dark, large text") {
    NavigationStack {
        ChildAccountGateView(
            feature: .family,
            state: .unconsented,
            childRestrictedMode: previewPendingChildRestrictedMode()
        )
        .environmentObject(FirebaseAuthService())
    }
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility2)
}
