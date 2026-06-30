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

    private init() {}

    func resetForSignOut() {
        attemptedUserIds.removeAll()
    }

    func reconcileIfNeeded(userId: String, isOnline: Bool) async -> XpGrantReconcileOutcome {
        guard isOnline, !userId.isEmpty else { return .skippedOffline }
        guard !attemptedUserIds.contains(userId) else { return .skippedAlreadyAttempted }
        attemptedUserIds.insert(userId)

        do {
            let fn = Functions.functions().httpsCallable("reconcileXpGrantLedger")
            let result = try await fn.call(([:] as [String: Any]).addingClientMetadata())
            guard let payload = result.data as? [String: Any] else {
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
            attemptedUserIds.remove(userId)
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
