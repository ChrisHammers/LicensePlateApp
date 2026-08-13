//
//  FamilyMembershipTransitionService.swift
//  LicensePlateApp
//
//  COPPA F-8 fix pass. `users/{uid}.activeFamilyId` is the server's consent proxy: it is
//  set when a manager admits the member and cleared by every exit path. For a CHILD it
//  is therefore the consent switch itself (FR-28), and both edges have work to do:
//
//  - joined  → consent granted: the FR-28 gameplay hold lifts, so the queued backlog has
//              to drain NOW (see `SyncCoordinator.resumeGameplaySyncAfterConsent` — the
//              child-restriction backoff parks rows an hour out), and the invite that got
//              them in is consumed.
//  - left    → consent revoked: the restricted state and its banner come back, exactly
//              as before the join.
//
//  Both edges must fire from a live server read, not only from a screen re-entry — the
//  parent removes the child on their own device, and nothing local changes until the
//  child's `users/{uid}` listener delivers it.
//

import Foundation
import Combine

// MARK: - Pure transition

enum FamilyMembershipTransition: Equatable, Sendable {
    case none
    /// nil → some: admitted (for a child, consent granted).
    case joined(familyId: String)
    /// some → nil: membership ended (for a child, back to restricted).
    case left(previousFamilyId: String)
    /// some → different some: moved between families; treated as a fresh admission.
    case switched(from: String, to: String)

    /// Whether this edge lifts the FR-28 gameplay hold.
    var resumesGameplaySync: Bool {
        switch self {
        case .joined, .switched: return true
        case .none, .left: return false
        }
    }

    var newFamilyId: String? {
        switch self {
        case .joined(let id), .switched(_, let id): return id
        case .none, .left: return nil
        }
    }
}

enum FamilyMembershipTransitionPolicy {
    static func transition(previous: String?, current: String?) -> FamilyMembershipTransition {
        let previous = previous?.isEmpty == true ? nil : previous
        let current = current?.isEmpty == true ? nil : current
        switch (previous, current) {
        case (nil, nil):
            return .none
        case (nil, .some(let now)):
            return .joined(familyId: now)
        case (.some(let before), nil):
            return .left(previousFamilyId: before)
        case (.some(let before), .some(let now)):
            return before == now ? .none : .switched(from: before, to: now)
        }
    }
}

// MARK: - Consumed invites

enum FamilyInviteConsumptionKeys {
    static let consumedInviteIds = "familyInvites.consumedInviteIds"
}

/// Which accepted family invites have already been REDEEMED into a real membership.
///
/// The server flips a matching accepted invite to `declined` when a captain declines,
/// but leaves it `accepted` forever when they approve. That is harmless while the user is
/// a member (the awaiting-approval card only renders with no active family) and becomes a
/// phantom the moment membership ends: a stale `accepted` invite reads as "waiting for
/// approval" for a request that no longer exists. Recording consumption locally is what
/// distinguishes "already used this invite" from "genuinely waiting" — including for
/// someone who left one family and is now awaiting admission to another.
@MainActor
final class FamilyInviteConsumptionStore {
    static let shared = FamilyInviteConsumptionStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var consumedInviteIds: Set<String> {
        Set(defaults.stringArray(forKey: FamilyInviteConsumptionKeys.consumedInviteIds) ?? [])
    }

    func markConsumed(inviteIds: [String]) {
        let incoming = Set(inviteIds.filter { !$0.isEmpty })
        guard !incoming.isEmpty else { return }
        let merged = consumedInviteIds.union(incoming)
        guard merged.count != consumedInviteIds.count else { return }
        defaults.set(Array(merged), forKey: FamilyInviteConsumptionKeys.consumedInviteIds)
    }

    func isConsumed(_ inviteId: String) -> Bool {
        consumedInviteIds.contains(inviteId)
    }

    /// Hard sign-out: the next account starts with a clean slate.
    func clear() {
        defaults.removeObject(forKey: FamilyInviteConsumptionKeys.consumedInviteIds)
    }
}

// MARK: - Coordinator

@MainActor
final class FamilyMembershipTransitionService {
    static let shared = FamilyMembershipTransitionService()

    /// Injectable effects so the edge logic is testable without Firebase or singletons.
    ///
    /// This service stays the SINGLE detector of the consent edge; everything that has to
    /// happen at consent hangs off these dependencies rather than growing a second
    /// detector somewhere else.
    struct Dependencies {
        /// Accepted family invites for `familyId` addressed to the current user.
        var acceptedInviteIds: (String) -> [String]
        var markInvitesConsumed: ([String]) -> Void
        /// Whether this session is a child account at all — the gate for every FR-28
        /// recovery effect. Adults take the pre-existing path and nothing more.
        var isChildAccountSession: () -> Bool
        /// UNIVERSAL, unchanged since FR-28c shipped: clear the child-restriction backoff
        /// and flush. Every admission runs this, child or adult.
        var resumeGameplaySync: () async -> Void
        /// Child-only: restore the in-memory retry budgets the restricted period must not
        /// have spent.
        var resetRetryBudgets: () -> Void
        /// Child-only: budget reset, cancelled-row recovery, canonical publish, drain, and
        /// then the achievement resend (which must follow the drain).
        var runDurableRecovery: () async -> Void
        /// Child-only: retries the held return-streak daily claim immediately.
        var retryReturnStreakDailyClaim: () async -> Void
        /// Child-only: runs the XP ledger reconcile, skipped for the restricted period.
        var reconcileXpGrants: () async -> Void

        @MainActor
        static func live(currentUserIdProvider: @escaping () -> String?) -> Dependencies {
            Dependencies(
                acceptedInviteIds: { familyId in
                    guard let userId = currentUserIdProvider(), !userId.isEmpty else { return [] }
                    return FamilyAwaitingApprovalFilter
                        .awaitingApprovalInvites(
                            from: InviteRepository.shared.invites,
                            userId: userId,
                            consumedInviteIds: []
                        )
                        .filter { $0.familyId == familyId }
                        .map(\.inviteId)
                },
                markInvitesConsumed: { FamilyInviteConsumptionStore.shared.markConsumed(inviteIds: $0) },
                isChildAccountSession: {
                    ChildRestrictedModeService.shared.isChildAccountSession
                },
                resumeGameplaySync: { await SyncCoordinator.shared.resumeGameplaySyncAfterConsent() },
                resetRetryBudgets: {
                    AchievementUnlockSyncService.shared.resetRetryBudgetAfterConsent()
                    ReturnStreakDailyXpClaimService.shared.resetRetryBudgetAfterConsent()
                },
                runDurableRecovery: {
                    await ChildRestrictedDataRecoveryService.shared.runConsentRecovery()
                },
                retryReturnStreakDailyClaim: {
                    await ConsentRecoverySupport.retryReturnStreakDailyClaim()
                },
                reconcileXpGrants: {
                    await ConsentRecoverySupport.reconcileXpGrants()
                }
            )
        }
    }

    private var deps: Dependencies
    /// Last value this service acted on, so a repeated read of the same membership is a
    /// no-op and the edges stay exactly-once per change.
    private var lastKnownFamilyId: String?
    private var hasSeenFirstValue = false

    init(dependencies: Dependencies? = nil) {
        self.deps = dependencies ?? .live(currentUserIdProvider: { nil })
    }

    func configure(dependencies: Dependencies) {
        self.deps = dependencies
    }

    /// Seeds the baseline without firing an edge — used when an identity is first
    /// resolved, so an existing membership is not mistaken for a fresh admission.
    func seed(familyId: String?) {
        lastKnownFamilyId = (familyId?.isEmpty == true) ? nil : familyId
        hasSeenFirstValue = true
    }

    func reset() {
        lastKnownFamilyId = nil
        hasSeenFirstValue = false
    }

    /// Feed every observed value of `users/{uid}.activeFamilyId`. Returns the edge taken
    /// (`.none` when nothing changed) so callers can chain UI refreshes.
    @discardableResult
    func note(activeFamilyId: String?) -> FamilyMembershipTransition {
        let normalized = (activeFamilyId?.isEmpty == true) ? nil : activeFamilyId
        guard hasSeenFirstValue else {
            seed(familyId: normalized)
            return .none
        }
        let transition = FamilyMembershipTransitionPolicy.transition(
            previous: lastKnownFamilyId,
            current: normalized
        )
        lastKnownFamilyId = normalized
        guard transition != .none else { return .none }

        if let joinedFamilyId = transition.newFamilyId {
            // Consume the invite BEFORE anything can end this membership, so a later
            // removal cannot resurrect it as a phantom "waiting for approval".
            deps.markInvitesConsumed(deps.acceptedInviteIds(joinedFamilyId))
        }
        if transition.resumesGameplaySync {
            Task { [deps] in
                guard deps.isChildAccountSession() else {
                    // Adults keep exactly the behaviour that shipped with FR-28c: clear the
                    // backoff and flush. None of the recovery machinery below applies to an
                    // account that was never restricted, and running it would spend
                    // callables and erase genuine give-up progress for nothing.
                    await deps.resumeGameplaySync()
                    return
                }
                // Budgets first, so nothing that follows starts one failure from being
                // discarded. `runDurableRecovery` then does the ordered gameplay work
                // (reset, recover, publish, drain) and only afterwards re-sends
                // achievements — progression has to settle before that snapshot is taken.
                // The streak and XP kicks come last: they are independent of the queue, and
                // running them here is what stops them waiting for a scenePhase cycle that
                // may not come for hours.
                deps.resetRetryBudgets()
                await deps.runDurableRecovery()
                await deps.retryReturnStreakDailyClaim()
                await deps.reconcileXpGrants()
            }
        }
        return transition
    }
}
