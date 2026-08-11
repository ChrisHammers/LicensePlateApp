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

@MainActor
final class ChildRestrictedModeService: ObservableObject {
    static let shared = ChildRestrictedModeService()

    private let ageGateStore: AgeGateStore
    private var currentUserIdProvider: () -> String? = { nil }
    private var activeFamilyIdProvider: () -> String? = { nil }

    init(ageGateStore: AgeGateStore = .shared) {
        self.ageGateStore = ageGateStore
    }

    /// Wire identity/family lookups (RootView, after auth bootstrap).
    func configure(
        currentUserIdProvider: @escaping () -> String?,
        activeFamilyIdProvider: @escaping () -> String?
    ) {
        self.currentUserIdProvider = currentUserIdProvider
        self.activeFamilyIdProvider = activeFamilyIdProvider
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
        guard ageGateStore.category == .under13 else { return .notChild }
        guard let uid = currentUserIdProvider(), !uid.isEmpty else {
            // Pre-uid provisional guest (first-launch flow, uid not created yet).
            return ageGateStore.hasPendingChildDeclaration ? .unconsentedChild : .notChild
        }
        let isChildIdentity = ageGateStore.pendingDeclarationUserId == uid
            || ageGateStore.isDeclaredChildUserId(uid)
        guard isChildIdentity else { return .notChild }
        return activeFamilyIdProvider() == nil ? .unconsentedChild : .consentedChild
    }

    /// FR-28: unconsented child — the under-13 signal bound to this session's identity
    /// (declared uid, flow-bound uid awaiting declaration, or the pre-uid provisional
    /// guest) with no active family.
    var isRestrictedUnconsentedChild: Bool {
        childSessionState == .unconsentedChild
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
