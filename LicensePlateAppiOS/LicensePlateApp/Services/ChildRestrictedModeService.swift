//
//  ChildRestrictedModeService.swift
//  LicensePlateApp
//
//  COPPA F-6 (FR-28 client half): restricted state for an unconsented child —
//  local/offline play continues, cloud gameplay sync pauses, and a non-punitive
//  "ask a parent" surface shows until family admission (consent) lifts it.
//
//  The server (`assertNotUnconsentedChild`, F-5a) is the backstop; this client gate
//  keeps queued events holding instead of burning retries against rejections.
//

import Foundation
import Combine
import FirebaseFunctions

/// How the FR-28 "ask a parent" surface is presented on the home screen.
///
/// Owner decision (F-8 review): the prompt is PERSISTENT but COMPACT — it introduces
/// itself full-size once, then lives on as a one-line row that never covers the app
/// title. It is always tappable and always deep-links to the join-family surface,
/// because joining a family IS how consent happens (FR-28).
enum ChildFamilyPromptPresentation: String, Equatable, Sendable {
    case hidden
    case full
    case compact

    var isVisible: Bool { self != .hidden }
}

enum ChildFamilyPromptPolicy {
    /// - Parameter isFamilyApprovalPending: device pass 2026-08-16 (bug 3). A submitted
    ///   share code is the one prompt state that must NOT collapse to the compact row.
    ///   The compact row shows the title only, and with several children waiting at once
    ///   the owner could not tell which device had actually sent a request. The waiting
    ///   variant therefore always renders full-size — its subtitle is the entire message —
    ///   and it stays visible for as long as the flag is set, which is until membership
    ///   arrives, the identity resets (decline / deletion), or the child sends a new code.
    static func presentation(
        isRestrictedUnconsentedChild: Bool,
        hasPresentedFullBanner: Bool,
        isFamilyApprovalPending: Bool = false
    ) -> ChildFamilyPromptPresentation {
        // Pending wins over the restriction classification, not just over the compact
        // collapse: the flag is identity-bound and only a child session can ever set it,
        // so if it is up, the child is owed the status regardless of how the FR-28
        // classification happens to be resolving this instant.
        if isFamilyApprovalPending { return .full }
        guard isRestrictedUnconsentedChild else { return .hidden }
        return hasPresentedFullBanner ? .compact : .full
    }
}

enum ChildRestrictedModeKeys {
    static let hasPresentedFullFamilyPrompt = "childGate.hasPresentedFullFamilyPrompt"
    /// F-8 device testing (2026-08-15): uid a share-code redemption is awaiting the
    /// family captain's approval for. Stores the uid (not a bare Bool) so the read is
    /// identity-bound — see `isFamilyApprovalPending`.
    static let pendingFamilyApprovalUserId = "childGate.pendingFamilyApprovalUserId"
}

@MainActor
final class ChildRestrictedModeService: ObservableObject {
    static let shared = ChildRestrictedModeService()

    /// Bumped on every mutation of this service's own UserDefaults-backed state, so SwiftUI
    /// surfaces re-evaluate (same idiom as `AgeGateStore.revision`).
    ///
    /// Device pass 2026-08-16 (bug 3): the pending-approval flag had no publisher, so the
    /// only way a surface learned about it was by being told to re-read — and `ContentView`
    /// snapshots it into `@State` at a fixed list of moments. Redeeming a code from anywhere
    /// other than the home banner's own sheet (the profile card, onboarding, the child gate)
    /// set the flag with nobody listening, and the child's "waiting" status simply never
    /// appeared. A published revision makes the flag observable from wherever it is read.
    @Published private(set) var revision = 0

    private let ageGateStore: AgeGateStore
    private let defaults: UserDefaults
    private let childSignalCache: ChildSignalCache
    private var currentUserIdProvider: () -> String? = { nil }
    private var activeFamilyIdProvider: () -> String? = { nil }
    /// This session's fresh `users/{uid}.isChildAccount` resolution (tri-state; nil =
    /// not resolved). Wired to `UserRepository.isChildAccount(for:)` in RootView.
    private var resolvedIsChildAccountProvider: (String) -> Bool? = { _ in nil }

    init(
        ageGateStore: AgeGateStore = .shared,
        defaults: UserDefaults = .standard,
        childSignalCache: ChildSignalCache? = nil
    ) {
        self.ageGateStore = ageGateStore
        self.defaults = defaults
        // The cache is UserDefaults-backed state, so an instance over the same defaults
        // sees the same data as `.shared` — and tests get isolation for free.
        self.childSignalCache = childSignalCache ?? ChildSignalCache(defaults: defaults)
    }

    /// Wire identity/family lookups (RootView, after auth bootstrap).
    func configure(
        currentUserIdProvider: @escaping () -> String?,
        activeFamilyIdProvider: @escaping () -> String?,
        resolvedIsChildAccountProvider: @escaping (String) -> Bool? = { _ in nil }
    ) {
        self.currentUserIdProvider = currentUserIdProvider
        self.activeFamilyIdProvider = activeFamilyIdProvider
        self.resolvedIsChildAccountProvider = resolvedIsChildAccountProvider
    }

    /// Client-side child session classification (advisory; server gates are the
    /// authority). Identity-bound: a stale answer never classifies a different
    /// signed-in account as a child (incident-1 regression).
    enum ChildSessionState: Equatable {
        case notChild
        /// Flag bound to this identity, no active family — restricted (FR-28).
        case unconsentedChild
        /// Flag bound to this identity, active family present.
        case consentedChild
    }

    var childSessionState: ChildSessionState {
        guard let uid = currentUserIdProvider(), !uid.isEmpty else {
            // Pre-uid provisional guest (first-launch flow, uid not created yet).
            guard ageGateStore.category == .under13 else { return .notChild }
            return ageGateStore.hasPendingChildDeclaration ? .unconsentedChild : .notChild
        }
        // Two independent, both identity-bound, sources of the child signal:
        //
        // 1. Device-declared lineage (F-6): this device's under-13 answer, epoch-bound,
        //    with the declared/pending uid matching the signed-in identity.
        // 2. Server-resolved truth for THIS uid — the fresh projection this session,
        //    or the cached last resolution (FR-19 asymmetric trust: only TRUE counts;
        //    both are written exclusively from server-resolved snapshots).
        //
        // (2) exists because (1) alone cannot survive its own erasure: a manager
        // CORRECTION wipes the device markers, and if the manager then re-flags the
        // account (correct → re-grant → remove), or a child account signs in on a
        // device that never ran the age gate for it, the server flag is the only
        // signal left. Without (2) those sessions classified `.notChild` and rendered
        // adult surfaces (create-family, no "ask a parent") while every server gate
        // still rejected them.
        let deviceDeclaredIdentity = ageGateStore.category == .under13
            && (ageGateStore.isPendingDeclaration(userId: uid)
                || ageGateStore.isDeclaredChildUserId(uid))
        let serverResolvedChild = resolvedIsChildAccountProvider(uid) == true
            || childSignalCache.cachedIsChildAccount(for: uid) == true
        guard deviceDeclaredIdentity || serverResolvedChild else { return .notChild }
        return activeFamilyIdProvider() == nil ? .unconsentedChild : .consentedChild
    }

    /// FR-28: unconsented child — the under-13 signal bound to this session's identity
    /// (declared uid, flow-bound uid awaiting declaration, or the pre-uid provisional
    /// guest) with no active family.
    var isRestrictedUnconsentedChild: Bool {
        childSessionState == .unconsentedChild
    }

    /// True when this session belongs to a child account AT ALL — restricted or consented.
    ///
    /// This is the scope for FR-28 consent-recovery work, and the distinction from
    /// `isRestrictedUnconsentedChild` is the point: after consent the account is no longer
    /// restricted, but it is still the account whose data the restriction stranded. The
    /// signal is effectively sticky (`isChildAccount` only clears through a parent
    /// correction), so it survives the restart that loses in-memory retry state — which is
    /// exactly when recovery needs to run.
    ///
    /// Adults are `.notChild` and skip every recovery path, so they never pay for machinery
    /// that exists to undo a restriction they were never under.
    var isChildAccountSession: Bool {
        childSessionState != .notChild
    }

    /// F-7 consumption surface (option B): true while this device's identity epoch has
    /// no age answer — e.g. a post-sign-out reborn guest, which is never prompted and
    /// simply lives behind the standard guest gates. F-7 treats age-unresolved as
    /// child-equivalent for postures (fail-closed: no ads, etc.), combined with its own
    /// fresh `users/{uid}` read for signed-in accounts (FR-19 asymmetric trust).
    /// Postures themselves are NOT implemented here.
    var isAgeUnresolved: Bool {
        !ageGateStore.isResolved
    }

    // MARK: - Home-screen family prompt (FR-28 surface, F-8 banner polish)

    /// Whether the full-size introduction has already been shown on this device. Once
    /// set the prompt stays visible, just compact — it is never dismissible, because the
    /// restriction it explains is not dismissible either.
    var hasPresentedFullFamilyPrompt: Bool {
        defaults.bool(forKey: ChildRestrictedModeKeys.hasPresentedFullFamilyPrompt)
    }

    func markFullFamilyPromptPresented() {
        guard !hasPresentedFullFamilyPrompt else { return }
        defaults.set(true, forKey: ChildRestrictedModeKeys.hasPresentedFullFamilyPrompt)
        revision += 1
    }

    var familyPromptPresentation: ChildFamilyPromptPresentation {
        ChildFamilyPromptPolicy.presentation(
            isRestrictedUnconsentedChild: isRestrictedUnconsentedChild,
            hasPresentedFullBanner: hasPresentedFullFamilyPrompt,
            isFamilyApprovalPending: isFamilyApprovalPending
        )
    }

    // MARK: - Pending family approval (F-8 device testing, 2026-08-15)
    //
    // A share-code redemption gives an unconsented child nothing to look at until a
    // captain approves it — the FR-28 banner kept showing the generic "ask a parent"
    // prompt as if nothing had happened. This is a purely device-local flag (no cloud
    // reads): `FamilyRepository.redeemShareCode` marks it right after a successful
    // FAMILY-type redemption; it clears once membership arrives (an
    // `.userProfilesMerged` delivery that lifts the restriction — ContentView already
    // observes that notification for FR-28) or the identity changes. Identity-bound by
    // storing the uid itself, so a later different identity on this device — or a
    // decline path that signs the child out, which the identity agent owns — never
    // inherits a stale "waiting" state (same pattern as the incident-1 regression
    // guarded elsewhere in this file).

    /// True while a share-code redemption THIS identity made is awaiting captain
    /// approval (no active family yet). False once membership arrives, the flag is
    /// explicitly cleared, or the current identity never set it.
    var isFamilyApprovalPending: Bool {
        guard let uid = currentUserIdProvider(), !uid.isEmpty else { return false }
        return defaults.string(forKey: ChildRestrictedModeKeys.pendingFamilyApprovalUserId) == uid
    }

    /// Called after `FamilyRepository.redeemShareCode` succeeds for a `.family` code
    /// while the caller is a restricted unconsented child.
    func markFamilyApprovalPending() {
        guard let uid = currentUserIdProvider(), !uid.isEmpty else { return }
        guard defaults.string(forKey: ChildRestrictedModeKeys.pendingFamilyApprovalUserId) != uid else { return }
        defaults.set(uid, forKey: ChildRestrictedModeKeys.pendingFamilyApprovalUserId)
        revision += 1
    }

    /// Membership arrived (active family now present) or the identity reset. Safe to
    /// call unconditionally — a no-op when nothing is pending.
    func clearFamilyApprovalPending() {
        guard defaults.string(forKey: ChildRestrictedModeKeys.pendingFamilyApprovalUserId) != nil else { return }
        defaults.removeObject(forKey: ChildRestrictedModeKeys.pendingFamilyApprovalUserId)
        revision += 1
    }

    /// Gameplay cloud uploads hold while restricted; queued events simply wait.
    /// Own-profile sync is NOT held (FR-27 allows the declared account to be synced).
    var isGameplayCloudSyncPaused: Bool {
        isRestrictedUnconsentedChild
    }

    /// True when a callable rejection is the server's unconsented-child / child-account
    /// guard (`failed-precondition` with `details.reason`). These map to the friendly
    /// "ask a parent" copy and are held — never treated as permanent failures.
    nonisolated static func isChildRestrictionRejection(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: ns.code),
              code == .failedPrecondition else {
            return false
        }
        guard let details = ns.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
              let reason = details["reason"] as? String else {
            return false
        }
        return reason == "unconsented_child" || reason == "child_account"
    }
}
