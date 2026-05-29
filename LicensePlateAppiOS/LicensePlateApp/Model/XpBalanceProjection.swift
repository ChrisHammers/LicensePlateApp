//
//  XpBalanceProjection.swift
//  LicensePlateApp
//
//  Ledger-derived balance for one user in one game instance.
//  Option B: not wired to global HUD / progression totals until cutover.
//

import Foundation

struct XpBalanceProjection: Sendable, Equatable {
    var userId: String
    var sessionId: UUID
    var gameInstanceId: UUID

    /// Net XP across all ledger rows for this scope (append-only; includes provisional + final adjustments).
    /// Note: name is historical; this is **not** “final-only” XP — use `displayXp` / row `status` filters in UI when splitting pending vs settled.
    var totalXpFinal: Int
    /// Sum of ledger `xpDelta` for rows with `status == .provisional`.
    var totalXpProvisional: Int
    /// Same as `totalXpFinal` for MVP (full net in this scope).
    var displayXp: Int
    var pendingAdjustmentCount: Int
    var lastRecomputedAt: Date
}
