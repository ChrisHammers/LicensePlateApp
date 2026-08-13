//
//  XpGrantReconcileService.swift
//  LicensePlateApp
//
//  Backfills missing server XP grant rows and seals legacy orphan balances.
//

import Foundation
import FirebaseFunctions

enum XpGrantReconcileOutcome: Equatable, Sendable {
    case skippedOffline
    case skippedAlreadyAttempted
    /// FR-28: unconsented child. Nothing was called and nothing was marked attempted, so
    /// the reconcile runs for real once consent lifts the restriction.
    case skippedChildRestricted
    case reconciled(
        totalXp: Int,
        verifiedTotalXp: Int,
        totalXpMatchesGrants: Bool,
        backfilledAchievementGrants: Int,
        legacyAmount: Int,
        grantCount: Int
    )
    case failed(String)
}

@MainActor
final class XpGrantReconcileService {

    static let shared = XpGrantReconcileService()

    private var attemptedUserIds = Set<String>()
    /// Performs the `reconcileXpGrantLedger` call. Injectable for tests (no Firebase).
    private let remoteCall: () async throws -> Any?
    /// FR-28: true while this session is a restricted unconsented child. Injectable.
    private var isRestrictedUnconsentedChild: () -> Bool

    init(
        remoteCall: (() async throws -> Any?)? = nil,
        isRestrictedUnconsentedChild: (() -> Bool)? = nil
    ) {
        self.remoteCall = remoteCall ?? {
            let fn = Functions.functions().httpsCallable("reconcileXpGrantLedger")
            return try await fn.call(([:] as [String: Any]).addingClientMetadata()).data
        }
        self.isRestrictedUnconsentedChild = isRestrictedUnconsentedChild
            ?? { ChildRestrictedModeService.shared.isRestrictedUnconsentedChild }
    }

    func configureRestrictionProvider(_ provider: @escaping () -> Bool) {
        isRestrictedUnconsentedChild = provider
    }

    func resetForSignOut() {
        attemptedUserIds.removeAll()
    }

    func reconcileIfNeeded(userId: String, isOnline: Bool) async -> XpGrantReconcileOutcome {
        guard isOnline, !userId.isEmpty else { return .skippedOffline }
        // FR-28 pre-emptive hold. This closes the account-creation race from the client
        // side: RootView fires the reconcile the moment a uid appears, concurrently with
        // `declareChildRegistration`, so the call could reach the server just before the
        // child flag was written and slip past the server guard. Checking the local
        // restriction first means the child's own device never makes the call at all.
        // Nothing is recorded as attempted, so consent re-runs it for real.
        guard !isRestrictedUnconsentedChild() else { return .skippedChildRestricted }
        guard !attemptedUserIds.contains(userId) else { return .skippedAlreadyAttempted }
        attemptedUserIds.insert(userId)

        do {
            guard let payload = try await remoteCall() as? [String: Any] else {
                return .failed("Unexpected reconcile response shape")
            }
            return .reconciled(
                totalXp: intValue(payload["totalXp"]),
                verifiedTotalXp: intValue(payload["verifiedTotalXp"]),
                totalXpMatchesGrants: boolValue(payload["totalXpMatchesGrants"]),
                backfilledAchievementGrants: intValue(payload["backfilledAchievementGrants"]),
                legacyAmount: intValue(payload["legacyAmount"]),
                grantCount: intValue(payload["grantCount"])
            )
        } catch {
            // Clearing the guard is what makes this self-healing: the next launch retries.
            attemptedUserIds.remove(userId)
            // A restriction rejection that raced the pre-emptive check is a hold, not a
            // failure — consent re-runs it (FR-21: nothing logged either way).
            guard !ChildRestrictedModeService.isChildRestrictionRejection(error) else {
                return .skippedChildRestricted
            }
            return .failed(error.localizedDescription)
        }
    }

    private func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return 0
    }

    private func boolValue(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return false
    }
}
