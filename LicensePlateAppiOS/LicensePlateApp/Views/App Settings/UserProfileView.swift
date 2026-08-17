//
//  UserProfileView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI
import SwiftData
import GoogleSignInSwift

// MARK: - Authentication Status state matrix (device pass 2026-08-16, bug 2)

/// Every session this app can actually be in, as the Authentication Status card has to
/// describe it. Deliberately a closed, mutually exclusive set rather than a chain of
/// `if` conditions in the view body — the reported defect was a HYBRID: the header
/// resolved off `isAnonymousUser || firebaseUID != nil` while the section below it
/// resolved off `ChildRestrictedModeService.childSessionState`, so a child holding a uid
/// got an adult's "Anonymous Account. Sign up to sync…" headline stacked on top of a
/// child's "join a family" body. Two independent classifications of one session can
/// always disagree; one classification cannot.
///
/// Ordering rule that kills that class of bug: CHILD states are decided before any
/// uid-shaped state, so no child session can ever fall through to an adult headline.
enum AuthenticationStatusState: String, CaseIterable, Equatable, Sendable {
    /// (1) Email/OAuth account, signed in. The only state with account controls.
    case registeredAdult
    /// Registered account, currently signed out (pre-existing branch; adults only).
    case signedOutRegisteredAdult
    /// (2) 13+ answered and provisioned — an anonymous uid with no credentials.
    case anonymousAdult
    /// (3) Restored anonymous uid with NO answer for this identity epoch. Exists only
    /// until F-30 lands; presented exactly as `anonymousAdult` because nothing about the
    /// session is known well enough to say anything else.
    case unresolvedRestoredSession
    /// Local guest with no uid and no under-13 answer (offline first launch, post-sign-out
    /// rebirth). Pre-existing "Local Account" branch.
    case localAdultGuest
    /// (8) A 13+/unknown session whose anonymous identity this device retired (FR-60(c)).
    /// Renders as an ordinary local account: the retirement is not the player's business.
    case detachedAdultSession
    /// (4) FR-60 local-first child: under-13, not in a family, with no live claim on any
    /// family's attention. A DETACHED child lands here too, by construction — that identity
    /// of outcome is the anti-hybrid invariant, and
    /// `theDetachedChildIsIndistinguishableFromAFreshLocalChild` pins it.
    ///
    /// Device pass 2026-08-17: this is also the FALLBACK for a child who holds a uid with no
    /// pending request and no family history — a declined code, or a reinstall that kept the
    /// Keychain uid and lost the UserDefaults flag. Their profile row may well be in the
    /// cloud, so "Local Account" is a slight understatement, but it is the honest end of the
    /// trade: the alternative was telling them a family was still deciding about a request
    /// that no longer exists (owner's rule — see `state(for:)`).
    case localUnconsentedChild
    /// (5) Provisioned child whose share code is with a family captain, and whose request is
    /// KNOWN to still be outstanding. `isFamilyApprovalPending` is the only way in: this
    /// state claims a live request exists, so it is never reached by elimination.
    case transientDeclaredChild
    /// (6) Anonymous child uid inside a family — consent granted.
    case consentedChild
    /// (7) Child whose membership was revoked. `isChildAccount` is sticky, so the session
    /// stays a child; only the family is gone.
    case postRevocationChild
}

/// What the card renders for one state. A flat record on purpose: the owner asked for a
/// matrix, and a matrix is what a test can read back.
struct AuthenticationStatusPresentation: Equatable, Sendable {
    /// Localization key for the bold status line.
    var headerKey: String
    /// Localization key for the caption beneath it.
    var subtitleKey: String
    /// Green check vs. amber exclamation. Never the only signal — the header says it too
    /// (state is never conveyed by color alone).
    var isCloudSynced: Bool
    /// Route into `SignInView`. FALSE for every child state (owner, 2026-08-16): a child
    /// has no account to create and no credentials to sign in with, so the affordance is
    /// pure misdirection. A future parent-gated setting could reintroduce a sign-in path
    /// for a guardian on the child's device — NOT BUILT, recorded here only.
    var showsSignIn: Bool
    /// Sign Out + Delete Account. They travel together — only a registered session has
    /// either — and Delete Account is Guideline 5.1.1(v)'s requirement for exactly that
    /// session.
    var showsRegisteredAccountControls: Bool
    /// The child-copy card that replaces the adult CTA.
    var childGuidance: ChildGuidance?
    /// Non-interactive child notice (`ChildPremiumInlineNotice`) where there is nothing
    /// to do.
    var childNoticeKey: String?

    struct ChildGuidance: Equatable, Sendable {
        var titleKey: String
        var bodyKey: String
        var showsJoinFamilyButton: Bool
    }

    /// Convenience readouts so the matrix test (and the report table) can talk in the
    /// owner's columns.
    var showsDeleteAccount: Bool { showsRegisteredAccountControls }
    var showsJoinFamily: Bool { childGuidance?.showsJoinFamilyButton ?? false }
}

enum AuthenticationStatusPolicy {
    struct Inputs: Equatable, Sendable {
        /// `FirebaseAuthService.isTrulyAuthenticated` — a non-anonymous Firebase session.
        var isRegisteredSession: Bool
        /// `FirebaseAuthService.wasPreviouslySignedIn`.
        var wasPreviouslySignedIn: Bool
        /// `FirebaseAuthService.isAnonymousUser`.
        var isAnonymousSession: Bool
        /// `AppUser.firebaseUID != nil`.
        var hasFirebaseUid: Bool
        /// The one child classification in the app (`ChildRestrictedModeService`).
        var childSessionState: ChildRestrictedModeService.ChildSessionState
        /// `ChildRestrictedModeService.isFamilyApprovalPending`. FR-88: the reconciled value —
        /// `users/{uid}.pendingFamilyRequest` when the server has answered, the device's
        /// optimistic redemption flag only while it has not. The decision below is unchanged;
        /// what changed is that "a live request exists" is now a claim the server backs.
        var isFamilyApprovalPending: Bool
        /// `AgeGateStore.isResolved` for the current identity epoch.
        var isAgeAnswerResolved: Bool
        /// `FirebaseAuthService.isCurrentIdentityDetached` (FR-60(c)).
        var isIdentityDetached: Bool
        /// `AppUser.wasEverInFamily` — separates a revoked child from one who never joined.
        var wasEverInFamily: Bool

        init(
            isRegisteredSession: Bool = false,
            wasPreviouslySignedIn: Bool = false,
            isAnonymousSession: Bool = false,
            hasFirebaseUid: Bool = false,
            childSessionState: ChildRestrictedModeService.ChildSessionState = .notChild,
            isFamilyApprovalPending: Bool = false,
            isAgeAnswerResolved: Bool = true,
            isIdentityDetached: Bool = false,
            wasEverInFamily: Bool = false
        ) {
            self.isRegisteredSession = isRegisteredSession
            self.wasPreviouslySignedIn = wasPreviouslySignedIn
            self.isAnonymousSession = isAnonymousSession
            self.hasFirebaseUid = hasFirebaseUid
            self.childSessionState = childSessionState
            self.isFamilyApprovalPending = isFamilyApprovalPending
            self.isAgeAnswerResolved = isAgeAnswerResolved
            self.isIdentityDetached = isIdentityDetached
            self.wasEverInFamily = wasEverInFamily
        }
    }

    static func state(for inputs: Inputs) -> AuthenticationStatusState {
        // Adult account states first — unchanged from the pre-matrix chain, byte for byte.
        // Neither can hold a child: a child session has no credentials, so it is always
        // anonymous, which makes `wasPreviouslySignedIn` false for it by definition.
        if inputs.isRegisteredSession { return .registeredAdult }
        if inputs.wasPreviouslySignedIn { return .signedOutRegisteredAdult }

        // "Does a cloud identity exist for this session?" — the exact condition the old
        // header used. It is now consulted only AFTER the child branch, which is the whole
        // fix: a child holding a uid can no longer be labelled an anonymous adult.
        let hasCloudIdentity = inputs.isAnonymousSession || inputs.hasFirebaseUid

        switch inputs.childSessionState {
        case .consentedChild:
            return .consentedChild

        case .unconsentedChild:
            // Device pass 2026-08-17 (fix 1). Owner's rule, verbatim: "waiting for approval"
            // must mean a pending request ACTUALLY EXISTS; approved, declined, or none-sent
            // all get the ordinary local-child wording.
            //
            // So the pending flag is the sole entry to (5), and it is consulted FIRST —
            // ahead of the cloud-identity guard, because the flag is itself identity-bound
            // (it stores the uid) and therefore already carries the evidence that guard is
            // looking for. `ChildFamilyPromptPolicy.presentation` resolves pending ahead of
            // its own classification for exactly the same reason; the two policies now
            // agree, which is the anti-hybrid rule applied inside this branch.
            //
            // This does NOT reopen FR-60(c): the service reads the flag through
            // `authService.currentUser?.firebaseUID`, so a detached session — whose uid is
            // nil end to end — reports `isFamilyApprovalPending == false` and still lands on
            // (4), exactly as `theDetachedChildIsIndistinguishableFromAFreshLocalChild`
            // requires. Hoisting is inert in production; it is here so the rule "waiting
            // means a request exists" is structural rather than incidental.
            if inputs.isFamilyApprovalPending { return .transientDeclaredChild }

            // A child with no cloud identity is FR-60's local-first child — including one
            // whose identity was just detached, which is why the detach has to nil the uid
            // end to end rather than leave the session half-provisioned.
            guard hasCloudIdentity else { return .localUnconsentedChild }

            // Removed from a family they were once in ⇒ say so. Everything else — never
            // sent a code, declined, or a request whose outcome this device lost track of —
            // is an ordinary local child.
            //
            // That last case is the reported defect: a reinstall restores the uid from the
            // Keychain while UserDefaults (which holds the pending flag) is wiped, and
            // remove-and-delete leaves the same shape. Both used to land on (5) and told the
            // child their family was still deciding, forever, about a request that no longer
            // existed. There is no evidence of a live request here, so we do not claim one.
            return inputs.wasEverInFamily ? .postRevocationChild : .localUnconsentedChild

        case .notChild:
            guard hasCloudIdentity else {
                return inputs.isIdentityDetached ? .detachedAdultSession : .localAdultGuest
            }
            return inputs.isAgeAnswerResolved ? .anonymousAdult : .unresolvedRestoredSession
        }
    }

    static func presentation(for state: AuthenticationStatusState) -> AuthenticationStatusPresentation {
        switch state {
        case .registeredAdult:
            return AuthenticationStatusPresentation(
                headerKey: "Signed In",
                subtitleKey: "Your account is synced to the cloud",
                isCloudSynced: true,
                showsSignIn: false,
                showsRegisteredAccountControls: true
            )

        case .signedOutRegisteredAdult:
            return AuthenticationStatusPresentation(
                headerKey: "Signed Out",
                subtitleKey: "You are signed out. Sign in to sync your account and access all features",
                isCloudSynced: false,
                showsSignIn: true,
                showsRegisteredAccountControls: false
            )

        case .anonymousAdult, .unresolvedRestoredSession:
            // (3) shares (2)'s presentation deliberately. Until F-30 resolves the epoch we
            // cannot honestly say more than "anonymous", and inventing a third headline for
            // a state that is about to be deleted would be copy we localize twice and throw
            // away.
            return AuthenticationStatusPresentation(
                headerKey: "Anonymous Account",
                subtitleKey: "Sign up to sync your account and access more features",
                isCloudSynced: false,
                showsSignIn: true,
                showsRegisteredAccountControls: false
            )

        case .localAdultGuest, .detachedAdultSession:
            return AuthenticationStatusPresentation(
                headerKey: "Local Account",
                subtitleKey: "Your account is stored locally only. Sign in to sync to the cloud",
                isCloudSynced: false,
                showsSignIn: true,
                showsRegisteredAccountControls: false
            )

        case .localUnconsentedChild:
            // Header stays "Local Account" — it is accurate and already localized. The
            // SUBTITLE changes: the old one told a child to sign in, which is the one thing
            // FR-60(e) says they cannot do.
            return AuthenticationStatusPresentation(
                headerKey: "Local Account",
                subtitleKey: "auth_status.child.local_subtitle",
                isCloudSynced: false,
                showsSignIn: false,
                showsRegisteredAccountControls: false,
                childGuidance: .init(
                    titleKey: "child_gate.screen.join_title",
                    bodyKey: "child_gate.screen.join_body",
                    showsJoinFamilyButton: true
                )
            )

        case .transientDeclaredChild:
            // Same copy as the home banner's waiting variant, on purpose: the child sees one
            // consistent account state wherever they look for it.
            return AuthenticationStatusPresentation(
                headerKey: "child_gate.family_prompt.pending_title",
                subtitleKey: "child_gate.family_prompt.pending_subtitle",
                isCloudSynced: false,
                showsSignIn: false,
                showsRegisteredAccountControls: false,
                childGuidance: .init(
                    titleKey: "auth_status.child.pending_guidance_title",
                    bodyKey: "auth_status.child.pending_guidance_body",
                    showsJoinFamilyButton: true
                )
            )

        case .consentedChild:
            // The reported defect: this said "Anonymous Account — sign up to sync…", which is
            // both wrong (the account IS synced) and an invitation to do the impossible.
            return AuthenticationStatusPresentation(
                headerKey: "auth_status.child.family_header",
                subtitleKey: "auth_status.child.family_subtitle",
                isCloudSynced: true,
                showsSignIn: false,
                showsRegisteredAccountControls: false,
                childNoticeKey: "child_gate.account.consented_notice"
            )

        case .postRevocationChild:
            return AuthenticationStatusPresentation(
                headerKey: "auth_status.child.no_family_header",
                subtitleKey: "auth_status.child.no_family_subtitle",
                isCloudSynced: false,
                showsSignIn: false,
                showsRegisteredAccountControls: false,
                childGuidance: .init(
                    titleKey: "child_gate.screen.join_title",
                    bodyKey: "child_gate.screen.join_body",
                    showsJoinFamilyButton: true
                )
            )
        }
    }

    static func presentation(for inputs: Inputs) -> AuthenticationStatusPresentation {
        presentation(for: state(for: inputs))
    }
}

struct UserProfileView: View {
    @Bindable var user: AppUser
    @ObservedObject var authService: FirebaseAuthService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: MainSettingsCoordinator
    
    // Navigation
    
    // Keep local copies for editing
    @State private var currentUserName: String
    
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isCheckingUsername = false
    @State private var linkingPlatform: LinkedPlatform.PlatformType? = nil
    @State private var showAvatarPickerSheet = false
    @State private var showLicenseWalletSheet = false
    @State private var showDeleteAccountSheet = false

    @StateObject private var lifetimeStatsViewModel: LifetimeStatsProfileViewModel
    @StateObject private var xpProgressViewModel: XpProgressViewModel
    @ObservedObject private var entitlementService = EntitlementService.shared
    @ObservedObject private var userProgressionRepository = UserProgressionRepository.shared
    @ObservedObject private var userProgressionService = UserProgressionService.shared
    @ObservedObject private var licenseCosmeticStore = LicenseCosmeticStore.shared
    /// Observed (not just read) so the card re-renders the moment a share-code redemption
    /// marks the pending-approval flag or the identity settles — see `revision`.
    @ObservedObject private var childRestrictedMode = ChildRestrictedModeService.shared
    @ObservedObject private var ageGateStore = AgeGateStore.shared

    // Helper function to get topmost view controller
    private func topViewController(controller: UIViewController? = nil) -> UIViewController? {
        let controller = controller ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
        
        if let navigationController = controller as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return topViewController(controller: selected)
            }
        }
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }
    
    // Helper function to handle platform linking
    private func handleLinkPlatform(_ platform: LinkedPlatform.PlatformType) {
        // Prevent multiple simultaneous taps
        guard !authService.isLoading, linkingPlatform == nil else {
            print("⚠️ Already linking, ignoring tap for \(platform.rawValue)")
            return
        }
        
        // Set the linking platform immediately
        linkingPlatform = platform
        
        Task {
            do {
                print("🔗 User tapped to link: \(platform.rawValue)")
                
                guard let presentingViewController = topViewController() else {
                    await MainActor.run {
                        errorMessage = "Unable to present sign in".localized
                        showError = true
                        linkingPlatform = nil
                    }
                    return
                }
                
                print("🔗 Calling link method for platform: \(platform.rawValue)")
                
                // Use explicit if-else instead of switch to prevent any fallthrough issues
                if platform == .google {
                    print("🔗 Linking Google account...")
                    try await authService.linkGoogleAccount(presentingViewController: presentingViewController)
                } else if platform == .apple {
                    print("🔗 Linking Apple account...")
                    try await authService.linkAppleAccount()
                } else if platform == .microsoft {
                    print("🔗 Linking Microsoft account...")
                    try await authService.linkMicrosoftAccount(presentingViewController: presentingViewController)
                } else if platform == .yahoo {
                    print("🔗 Linking Yahoo account...")
                    try await authService.linkYahooAccount(presentingViewController: presentingViewController)
                } else {
                    // Not yet implemented
                    print("❌ \(platform.rawValue) linking not implemented")
                    await MainActor.run {
                        errorMessage = "%@ linking is not yet available".localized(platform.rawValue)
                        showError = true
                        linkingPlatform = nil
                    }
                    return
                }
                
                print("✅ Successfully linked \(platform.rawValue)")
                
                // Clear linking platform on success
                await MainActor.run {
                    linkingPlatform = nil
                }
            } catch {
                print("❌ Error linking \(platform.rawValue): \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    linkingPlatform = nil
                }
            }
        }
    }
    
    init(user: AppUser, authService: FirebaseAuthService) {
        self.user = user
        self.authService = authService
        _currentUserName = State(initialValue: user.userName)
        let lifetimeStatsVM = LifetimeStatsProfileViewModel(userId: user.id)
        let xpProgressVM = XpProgressViewModel(userId: user.id)
        _lifetimeStatsViewModel = StateObject(wrappedValue: lifetimeStatsVM)
        _xpProgressViewModel = StateObject(wrappedValue: xpProgressVM)
    }

    private var gameLicense: UserDriversLicense {
        let progression = userProgressionRepository.snapshot
        let effective = userProgressionService.effectiveTotals
        return UserDriversLicenseBuilder.make(from: ProfileLicenseInputs(
            user: user,
            lifetimeStats: lifetimeStatsViewModel.stats,
            totalXp: xpProgressViewModel.displayedTotalXp,
            acceptedRegionFindCount: effective?.acceptedRegionFindCount ?? progression?.acceptedRegionFindCount,
            competitiveFirstPlaceFinishes: effective?.competitiveFirstPlaceFinishes
                ?? progression?.competitiveFirstPlaceFinishes ?? 0,
            isRoyale: entitlementService.entitlementState(for: user).effectiveTier >= .royale
        ))
    }

    /// Drives the whole Authentication Status card (device pass 2026-08-16, bug 2).
    /// `ChildRestrictedModeService` already classifies child sessions for the FR-28 home
    /// banner; feeding that same classification in here keeps one source of truth instead
    /// of a parallel check — and letting the policy decide the header as well as the CTA
    /// is what stops the two halves of the card describing different sessions.
    private var authenticationStatus: AuthenticationStatusPresentation {
        AuthenticationStatusPolicy.presentation(for: AuthenticationStatusPolicy.Inputs(
            isRegisteredSession: authService.isTrulyAuthenticated,
            wasPreviouslySignedIn: authService.wasPreviouslySignedIn,
            isAnonymousSession: authService.isAnonymousUser,
            hasFirebaseUid: user.firebaseUID != nil,
            childSessionState: childRestrictedMode.childSessionState,
            isFamilyApprovalPending: childRestrictedMode.isFamilyApprovalPending,
            isAgeAnswerResolved: ageGateStore.isResolved,
            isIdentityDetached: authService.isCurrentIdentityDetached,
            wasEverInFamily: user.wasEverInFamily
        ))
    }

    var body: some View {
            AppBackgroundView {
                List {
                    // Explorer license hero — avatar and license skin are separate actions
                    Section {
                        ProfileDriversLicenseCardSection(
                            license: gameLicense,
                            user: user,
                            style: licenseCosmeticStore.equippedStyle,
                            showsAvatarEdit: true,
                            showsLicenseCustomize: true,
                            onEditAvatar: {
                                showAvatarPickerSheet = true
                                AnalyticsService.shared.log(.avatarPickerOpened(source: "profile"))
                            },
                            onCustomizeLicense: {
                                showLicenseWalletSheet = true
                            }
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                    
                    Section {
                        VStack(spacing: 12) {
                            // No name rows: real names are never collected (F-6 rework).
                            // Username - Editable
                            SettingEditableTextRow(
                                title: "Username".localized,
                                value: $currentUserName,
                                placeholder: "Enter username".localized,
                                detail: nil,
                                isDisabled: isCheckingUsername,
                                onSave: {
                                    saveUserName()
                                },
                                onCancel: {
                                    cancelEditing()
                                }
                            )
                          
                            // Email - Share Data Toggle
                            SettingShareDataToggleRow3(
                                title: "Email".localized,
                                value: Binding(
                                    get: { user.email },
                                    set: { newValue in
                                        user.email = newValue
                                    }
                                ),
                                detail: nil,
                                isOn: Binding(
                                    get: { user.isEmailPublic },
                                    set: { newValue in
                                        user.isEmailPublic = newValue
                                        user.lastUpdated = .now
                                        try? modelContext.save()
                                        syncProfileToFirestoreIfNeeded()
                                    }
                                ),
                                isEditable: false,
                                onSave: {
                                    try? modelContext.save()
                                },
                                onCancel: {
                                    // Reset to original value if needed
                                }
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Account Information".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))

                    ProfileXpProgressSection(viewModel: xpProgressViewModel) {
                        SettingNavigationRow(
                            title: "profile.progression.achievements.title".localized,
                            description: "profile.progression.achievements.description".localized,
                            icon: "rosette"
                        ) {
                            coordinator.navigateToAchievements()
                        }

                        SettingNavigationRow(
                            title: "profile.progression.ranks.title".localized,
                            description: "profile.progression.ranks.description".localized,
                            icon: "chart.line.uptrend.xyaxis"
                        ) {
                            coordinator.navifateToRankProgression()
                        }
                    }

                    LifetimeStatsProfileStatsSection(viewModel: lifetimeStatsViewModel)

                  // Authentication Status Section
                  Section {
                      let status = authenticationStatus
                      VStack(alignment: .leading, spacing: 16) {
                          // Authentication status. One classification decides the header,
                          // the caption, the icon AND the actions (device pass 2026-08-16,
                          // bug 2) — see `AuthenticationStatusPolicy`.
                          AuthenticationStatusHeaderRow(presentation: status)

                          // Child sessions never get a sign-in affordance (owner,
                          // 2026-08-16): there is no account to create and no credential to
                          // sign in with. They get the established child-gate guidance
                          // instead (see ChildAccountCreationGuidanceView in SignInView.swift
                          // / ChildPremiumInfoView for the house style).
                          if let guidance = status.childGuidance {
                              ChildAccountSectionGuidance(
                                  title: guidance.titleKey.localized,
                                  message: guidance.bodyKey.localized,
                                  showsJoinButton: guidance.showsJoinFamilyButton
                              )
                              .environmentObject(authService)
                          }

                          if let noticeKey = status.childNoticeKey {
                              ChildPremiumInlineNotice(textKey: noticeKey)
                          }

                          if status.showsSignIn {
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
                          }

                          if status.showsRegisteredAccountControls {
                              // Sign out button (only show if truly authenticated)
                              Button {
                                  Task {
                                      do {
                                          try await authService.hardSignOutAndResetToGuest()
                                      } catch {
                                          errorMessage = error.localizedDescription
                                          showError = true
                                      }
                                  }
                              } label: {
                                  HStack {
                                      Text("Sign Out".localized)
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)
                                      
                                      Spacer()
                                      
                                      Image(systemName: "arrow.right")
                                          .font(.system(size: 14, weight: .semibold))
                                  }
                                  .foregroundStyle(Color.red)
                                  .padding(.vertical, 12)
                                  .padding(.horizontal, 16)
                                  .background(
                                      RoundedRectangle(cornerRadius: 12, style: .continuous)
                                          .stroke(Color.red, lineWidth: 2)
                                  )
                              }
                              // Plain style: in a List row, default-style buttons all fire on a
                              // single row tap — sign-out must not trigger from the delete button.
                              .buttonStyle(.plain)

                              // Delete account (Guideline 5.1.1(v); ToS §15, Privacy Policy §11)
                              Button {
                                  showDeleteAccountSheet = true
                              } label: {
                                  HStack {
                                      Text("Delete Account".localized)
                                          .font(.system(.body, design: .rounded))
                                          .fontWeight(.semibold)

                                      Spacer()

                                      Image(systemName: "trash")
                                          .font(.system(size: 14, weight: .semibold))
                                          .accessibilityHidden(true)
                                  }
                                  .foregroundStyle(Color.red)
                                  .padding(.vertical, 12)
                                  .padding(.horizontal, 16)
                                  .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.Theme.cardBackground)
                                )
                              }
                              .buttonStyle(.plain)
                              .accessibilityLabel("Delete Account".localized)
                              .accessibilityHint("Permanently deletes your account and synced data after confirmation".localized)
                          }

                          // Sync status
                          if user.needsSync && !authService.isOnline {
                              HStack(spacing: 8) {
                                  Image(systemName: "arrow.clockwise")
                                      .font(.system(.caption, design: .rounded))
                                  Text("Changes will sync when you're online".localized)
                                      .font(.system(.caption, design: .rounded))
                              }
                              .foregroundStyle(Color.Theme.softBrown)
                              .padding(.top, 8)
                          }
                      }
                      .padding(.vertical, 12)
                      .padding(.horizontal, 16)
                      .background(
                          RoundedRectangle(cornerRadius: 20, style: .continuous)
                              .fill(Color.Theme.cardBackground)
                      )
                  } header: {
                      Text("Authentication Status".localized)
                          .font(.system(.headline, design: .rounded))
                          .foregroundStyle(Color.Theme.primaryBlue)
                  }
                  .textCase(nil)
                  .listRowBackground(Color.clear)
                  .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                  
                    // MVP: Linked Accounts hidden — restore when account linking ships post-MVP
                    /*
                    // Linked Accounts Section
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            if user.linkedPlatforms.isEmpty {
                                Text("No accounts linked".localized)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                            } else {
                                ForEach(user.linkedPlatforms, id: \.platform) { platform in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(platform.platform.rawValue)
                                                    .font(.system(.body, design: .rounded))
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(Color.Theme.primaryBlue)
                                                
                                                Spacer()
                                                
                                                Text("Linked".localized)
                                                    .font(.system(.caption, design: .rounded))
                                                    .foregroundStyle(Color.green)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        Capsule()
                                                            .fill(Color.green.opacity(0.15))
                                                    )
                                            }
                                            
                                            if let email = platform.email {
                                                Text("Email: %@".localized(email))
                                                    .font(.system(.caption, design: .rounded))
                                                    .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                                            }
                                            
                                            if let displayName = platform.displayName {
                                                Text("Name: %@".localized(displayName))
                                                    .font(.system(.caption, design: .rounded))
                                                    .foregroundStyle(Color.Theme.softBrown.opacity(0.8))
                                            }
                                        }
                                        
                                        // Unlink button
                                        Button {
                                            Task {
                                                do {
                                                    try await authService.unlinkPlatform(platform.platform)
                                                } catch {
                                                    errorMessage = error.localizedDescription
                                                    showError = true
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(Color.red)
                                                .font(.system(size: 20))
                                        }
                                        .accessibilityLabel("Unlink %@ account".localized(platform.platform.rawValue))
                                        .accessibilityHint("Removes the linked %@ account".localized(platform.platform.rawValue))
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            
                            // Link new accounts section (only show if truly authenticated)
                            if authService.isTrulyAuthenticated {
                                Divider()
                                    .padding(.vertical, 8)
                                
                                Text("Link Additional Accounts".localized)
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.Theme.primaryBlue)
                                    .padding(.bottom, 4)
                                
                                // Available platforms to link (only show supported ones)
                                let supportedPlatforms: [LinkedPlatform.PlatformType] = [.google, .apple]//, .microsoft, .yahoo]
                                let availablePlatforms = supportedPlatforms.filter { platformType in
                                    !user.linkedPlatforms.contains(where: { $0.platform == platformType })
                                }
                                
                                if availablePlatforms.isEmpty {
                                    Text("All available accounts are linked".localized)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(availablePlatforms, id: \.self) { platform in
                                            Button {
                                                handleLinkPlatform(platform)
                                            } label: {
                                                HStack {
                                                    Text("Link %@".localized(platform.rawValue))
                                                        .font(.system(.body, design: .rounded))
                                                        .fontWeight(.medium)
                                                    
                                                    Spacer()
                                                    
                                                    Image(systemName: "plus.circle.fill")
                                                        .font(.system(size: 18))
                                                        .accessibilityHidden(true)
                                                }
                                                .foregroundStyle(authService.isLoading ? Color.Theme.softBrown.opacity(0.7) : Color.Theme.primaryBlue)
                                                .padding(.vertical, 10)
                                                .padding(.horizontal, 12)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .fill(Color.Theme.primaryBlue.opacity(0.1))
                                                )
                                            }
                                            .disabled(authService.isLoading || linkingPlatform != nil)
                                            .accessibilityLabel("Link %@ account".localized(platform.rawValue))
                                            .accessibilityHint("Links your %@ account to this profile".localized(platform.rawValue))
                                            .accessibilityAddTraits(.isButton)
                                        }
                                    }
                                }
                            } else {
                                Text("Sign in to link additional accounts".localized)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown.opacity(0.7))
                                    .italic()
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.Theme.cardBackground)
                        )
                    } header: {
                        Text("Linked Accounts".localized)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.Theme.primaryBlue)
                    }
                    .textCase(nil)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 20))
                    */
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profile".localized)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Done".localized)
                    .accessibilityHint("Closes the profile view".localized)
                }
            }
            .alert("Error".localized, isPresented: $showError) {
                Button("OK".localized, role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                lifetimeStatsViewModel.onAppear()
                xpProgressViewModel.refresh()
                licenseCosmeticStore.configure(
                    user: user,
                    rankLevel: gameLicense.rankLevel
                )
            }
            .onChange(of: gameLicense.rankLevel) { _, newLevel in
                licenseCosmeticStore.configure(user: user, rankLevel: newLevel)
            }
            .onChange(of: user.userName) { oldValue, newValue in
                currentUserName = newValue
            }
            .sheet(isPresented: $authService.showSignInSheet) {
                SignInView(authService: authService, deferredSetupTouchSource: "profile")
            }
            .sheet(isPresented: $showDeleteAccountSheet) {
                DeleteAccountView(authService: authService)
            }
            .sheet(isPresented: $showAvatarPickerSheet) {
                ProfileAvatarPickerSheet(
                    user: user,
                    onSave: {
                        try? modelContext.save()
                        syncProfileToFirestoreIfNeeded()
                        AnalyticsService.shared.log(.avatarSaved(avatarId: user.avatarId ?? "", source: "profile"))
                        showAvatarPickerSheet = false
                    },
                    onDismiss: { showAvatarPickerSheet = false }
                )
            }
            .sheet(isPresented: $showLicenseWalletSheet) {
                ProfileLicenseWalletSheet(
                    license: gameLicense,
                    user: user,
                    store: licenseCosmeticStore,
                    onSave: {
                        licenseCosmeticStore.applyEquippedIDToBoundUser()
                        try? modelContext.save()
                        syncProfileToFirestoreIfNeeded()
                        AnalyticsService.shared.log(
                            .licenseCosmeticEquipped(
                                cosmeticId: user.equippedLicenseCosmeticId ?? licenseCosmeticStore.equippedID,
                                source: "profile"
                            )
                        )
                        showLicenseWalletSheet = false
                    }
                )
            }
    }
    
    private func profileProgressionRow(title: String, description: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.Theme.primaryBlue)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)

                Text(description)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.Theme.softBrown)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
        .accessibilityElement(children: .combine)
    }

    private func saveUserName() {
        let trimmedName = currentUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            errorMessage = "Username cannot be empty".localized
            showError = true
            currentUserName = user.userName // Reset to original
            return
        }
        
        guard trimmedName != user.userName else {
            return // No change needed
        }
        
        // Check username uniqueness
        isCheckingUsername = true
        Task {
            do {
                // Check if username is taken
                let isTaken = try await authService.isUsernameTaken(trimmedName)
                
                if isTaken {
                    errorMessage = "This username is already taken. Please choose another.".localized
                    showError = true
                    currentUserName = user.userName // Reset to original
                    isCheckingUsername = false
                    return
                }
                
                // Update in auth service (which also checks uniqueness)
                try await authService.updateUserName(trimmedName)
                
                // Save to SwiftData
                try modelContext.save()
                
                isCheckingUsername = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                currentUserName = user.userName // Reset to original
                isCheckingUsername = false
            }
        }
    }
    
    private func cancelEditing() {
        currentUserName = user.userName // Reset to original
    }
    
    /// Persists profile to Firestore; surfaces failures via the existing error alert.
    ///
    /// F-8 device testing (2026-08-15): gating this on `isTrulyAuthenticated` (true only
    /// for a non-anonymous account) silently dropped every edit an anonymous consented
    /// child made here — avatar changes saved locally, then reverted on the next cloud
    /// echo, because the cloud doc never received them in the first place.
    /// `saveUserDataToFirestore` itself has no such restriction (an anonymous Firebase
    /// uid's self-write to its own `users/{uid}` is permitted by the Firestore rules);
    /// the real precondition is a cloud identity to write to, i.e. a `firebaseUID`.
    ///
    /// Device pass 2026-08-16 (bug 1): "a cloud identity" is not the same as "a LIVE cloud
    /// identity". Relaxing the gate to a bare `firebaseUID` made this the one self-doc
    /// trigger on the client that asked nothing about FR-60(c) detachment, and an avatar
    /// edit is the shortest path from a deleted child account to a resurrected
    /// `users/{uid}`. `saveUserDataToFirestore` holds detached uids as well — this is the
    /// second lock, at the trigger, so the surface never even starts a write it knows is
    /// addressed to a retired identity.
    private func syncProfileToFirestoreIfNeeded() {
        guard user.firebaseUID != nil else { return }
        guard !authService.isCurrentIdentityDetached else { return }
        Task {
            do {
                try await authService.saveUserDataToFirestore(user)
            } catch {
                print("❌ Profile sync to Firestore failed: \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Profile Avatar Picker Sheet

private struct ProfileAvatarPickerSheet: View {
    @Bindable var user: AppUser
    let onSave: () -> Void
    let onDismiss: () -> Void

    @State private var selectedId: String?
    @State private var unlockSheetPayload: AvatarUnlockSheetPayload?
    @State private var showPaywallSheet = false
    @State private var paywallUnlockSource: AvatarUnlockSource?
    @StateObject private var paywallViewModel = PaywallViewModel()

    private let catalogService = AvatarCatalogService.shared
    
    private var displayItems: [AvatarDisplayItem] {
        catalogService.displayItems(for: user)
    }
    
    private var selectedAvatarDisplayName: String {
        guard let id = selectedId else { return "None".localized }
        return displayItems.first(where: { $0.id == id })?.displayName ?? "None".localized
    }
    
    var body: some View {
        NavigationStack {
            AppBackgroundView {
                VStack(spacing: 20) {
                    AvatarPickerView(
                        items: displayItems,
                        selectedId: $selectedId,
                        onLockedTap: { item, source in
                            unlockSheetPayload = AvatarUnlockSheetPayload(unlockSource: source, avatarName: item.displayName)
                        },
                        onSelected: nil
                    )
                    .frame(height: 196)
                    .padding()

                    VStack(spacing: 8) {
                        Text("Selected".localized)
                            .font(.caption)
                            .foregroundStyle(Color.Theme.softBrown)
                        Text(selectedAvatarDisplayName)
                            .font(.headline)
                            .foregroundStyle(selectedAvatarDisplayName == "None".localized ? Color.Theme.softBrown : Color.Theme.primaryBlue)
                    }

                    Spacer()
                }
            }
            .navigationTitle("Change avatar".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel".localized) { onDismiss() }
                        .foregroundStyle(Color.Theme.primaryBlue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save".localized) {
                        if let id = selectedId {
                            user.avatarId = id
                            user.lastUpdated = .now
                            onSave()
                        } else {
                            onDismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                }
            }
            .onAppear {
                selectedId = user.avatarId ?? AvatarCatalog.guestAvatarIds.first
                DeferredProfileSetupStore.shared.markTouched(.avatar, source: "profile")
            }
            .overlay {
                if let payload = unlockSheetPayload {
                    AvatarUnlockPopupView(
                        unlockSource: payload.unlockSource,
                        avatarName: payload.avatarName,
                        onDismiss: { unlockSheetPayload = nil },
                        onShowPaywall: { source in
                            paywallUnlockSource = source
                            unlockSheetPayload = nil
                            showPaywallSheet = true
                        }
                    )
                }
            }
            .sheet(isPresented: $showPaywallSheet) {
                PaywallView(viewModel: paywallViewModel, onDismiss: { showPaywallSheet = false })
                    .onAppear {
                        paywallViewModel.setUnlockContext(paywallUnlockSource)
                    }
            }
        }
    }
}

// MARK: - Profile License Wallet Sheet

private struct ProfileLicenseWalletSheet: View {
    let license: UserDriversLicense
    let user: AppUser
    @ObservedObject var store: LicenseCosmeticStore
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            AppBackgroundView {
                DriversLicenseWalletView(
                    license: license,
                    ownedIDs: store.ownedIDs,
                    equippedID: store.equippedIDBinding
                ) {
                    ProfileDriversLicensePortraitView(user: user)
                }
            }
            .navigationTitle("Customize explorers license".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done".localized) {
                        FeedbackService.shared.buttonTap()
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Done".localized)
                }
            }
        }
    }
}

// MARK: - Authentication Status header row (device pass 2026-08-16, bug 2)

/// The status line, its caption and the sync glyph. Extracted so the state matrix can be
/// previewed end to end without a live `AppUser`, `FirebaseAuthService` and Firestore
/// session behind it — the previous inline chain could only ever be seen in one state at a
/// time, on a device, which is how the header and the body drifted apart in the first place.
struct AuthenticationStatusHeaderRow: View {
    let presentation: AuthenticationStatusPresentation

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.headerKey.localized)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)

                Text(presentation.subtitleKey.localized)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Redundant with the header text on purpose — the glyph is a second reading of
            // the same fact, never the only one.
            if presentation.isCloudSynced {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.Theme.accentYellow)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Child account section guidance (COPPA child-gate, F-8 device testing 2026-08-15)

/// What an unconsented child sees on `UserProfileView` instead of Sign In / Create
/// Account: a non-punitive explanation plus the same share-code route
/// `ChildAccountCreationGuidanceView` (SignInView.swift) offers, at card scale for this
/// screen's Authentication Status section rather than a full-screen takeover.
///
/// Deliberately logs NO analytics: an event here would fire only for child sessions on
/// the child's own instance (forbidden by FR-21 / SRS §12), same rule as
/// `ChildFamilyPromptBanner`.
private struct ChildAccountSectionGuidance: View {
    let title: String
    let message: String
    let showsJoinButton: Bool

    @EnvironmentObject private var authService: FirebaseAuthService
    @State private var showJoinFamilySheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "figure.and.child.holdinghands")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            if showsJoinButton {
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
        .sheet(isPresented: $showJoinFamilySheet) {
            JoinFamilySheet()
                .environmentObject(authService)
        }
    }
}

#Preview("Profile — unconsented child guidance") {
    AppBackgroundView {
        List {
            ChildAccountSectionGuidance(
                title: "child_gate.screen.join_title".localized,
                message: "child_gate.screen.join_body".localized,
                showsJoinButton: true
            )
            .listRowBackground(Color.Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
    }
    .environmentObject(FirebaseAuthService())
}

#Preview("Profile — consented child notice") {
    AppBackgroundView {
        List {
            ChildPremiumInlineNotice(textKey: "child_gate.account.consented_notice")
                .listRowBackground(Color.Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
    }
}

/// The whole matrix on one screen — the review surface the inline `if` chain never had.
private struct AuthenticationStatusMatrixPreview: View {
    var body: some View {
        AppBackgroundView {
            List(AuthenticationStatusState.allCases, id: \.self) { state in
                let presentation = AuthenticationStatusPolicy.presentation(for: state)
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.rawValue)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Color.Theme.softBrown)
                    AuthenticationStatusHeaderRow(presentation: presentation)
                    if let guidance = presentation.childGuidance {
                        ChildAccountSectionGuidance(
                            title: guidance.titleKey.localized,
                            message: guidance.bodyKey.localized,
                            showsJoinButton: guidance.showsJoinFamilyButton
                        )
                    }
                    if let noticeKey = presentation.childNoticeKey {
                        ChildPremiumInlineNotice(textKey: noticeKey)
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.Theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
        }
        .environmentObject(FirebaseAuthService())
    }
}

#Preview("Profile — auth status matrix") {
    AuthenticationStatusMatrixPreview()
}

#Preview("Profile — auth status matrix, dark, large text") {
    AuthenticationStatusMatrixPreview()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Profile — unconsented child guidance, dark, large text") {
    AppBackgroundView {
        List {
            ChildAccountSectionGuidance(
                title: "child_gate.screen.join_title".localized,
                message: "child_gate.screen.join_body".localized,
                showsJoinButton: true
            )
            .listRowBackground(Color.Theme.cardBackground)
        }
        .scrollContentBackground(.hidden)
    }
    .environmentObject(FirebaseAuthService())
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility2)
}

