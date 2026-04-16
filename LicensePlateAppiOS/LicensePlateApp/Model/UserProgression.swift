//
//  UserProgression.swift
//  LicensePlateApp
//
//  Step 16 — Decoded `user_progression/{uid}` (server-maintained; client read-only).
//

import Foundation

/// Local-only progression increments from events not yet listed in `appliedProgressionEvents` (Step 16 addendum).
struct ProgressionPendingDelta: Equatable, Sendable {
    var totalXp: Int
    var acceptedRegionFindCount: Int
    var competitiveFirstPlaceFinishes: Int
    var everCompetitiveFirstPlace: Bool

    static let zero = ProgressionPendingDelta(
        totalXp: 0,
        acceptedRegionFindCount: 0,
        competitiveFirstPlaceFinishes: 0,
        everCompetitiveFirstPlace: false
    )

    static func + (a: ProgressionPendingDelta, b: ProgressionPendingDelta) -> ProgressionPendingDelta {
        ProgressionPendingDelta(
            totalXp: a.totalXp + b.totalXp,
            acceptedRegionFindCount: a.acceptedRegionFindCount + b.acceptedRegionFindCount,
            competitiveFirstPlaceFinishes: a.competitiveFirstPlaceFinishes + b.competitiveFirstPlaceFinishes,
            everCompetitiveFirstPlace: a.everCompetitiveFirstPlace || b.everCompetitiveFirstPlace
        )
    }
}

/// Snapshot of Firestore `user_progression` for the signed-in user.
struct UserProgressionSnapshot: Equatable, Sendable {
    var totalXp: Int
    var acceptedRegionFindCount: Int
    var competitiveFirstPlaceFinishes: Int
    var everCompetitiveFirstPlace: Bool
    var lastUpdatedAt: Date?
    /// Keys of `appliedProgressionEvents` on the server doc (authoritative applied event ids).
    var appliedProgressionEventIds: Set<String>

    static let empty = UserProgressionSnapshot(
        totalXp: 0,
        acceptedRegionFindCount: 0,
        competitiveFirstPlaceFinishes: 0,
        everCompetitiveFirstPlace: false,
        lastUpdatedAt: nil,
        appliedProgressionEventIds: []
    )
}

/// Server totals plus local pending (offline) projection for UI and analytics.
struct UserProgressionEffectiveTotals: Equatable, Sendable {
    var totalXp: Int
    var acceptedRegionFindCount: Int
    var competitiveFirstPlaceFinishes: Int
    var everCompetitiveFirstPlace: Bool
    /// True when at least one local gameplay event contributes to totals but is not yet in `appliedProgressionEvents`.
    var hasPendingLocalProgression: Bool

    static func combined(server: UserProgressionSnapshot, pending: ProgressionPendingDelta) -> UserProgressionEffectiveTotals {
        UserProgressionEffectiveTotals(
            totalXp: server.totalXp + pending.totalXp,
            acceptedRegionFindCount: server.acceptedRegionFindCount + pending.acceptedRegionFindCount,
            competitiveFirstPlaceFinishes: server.competitiveFirstPlaceFinishes + pending.competitiveFirstPlaceFinishes,
            everCompetitiveFirstPlace: server.everCompetitiveFirstPlace || pending.everCompetitiveFirstPlace,
            hasPendingLocalProgression: pending != .zero
        )
    }
}
