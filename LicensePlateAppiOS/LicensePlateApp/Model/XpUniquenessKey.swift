//
//  XpUniquenessKey.swift
//  LicensePlateApp
//
//  Idempotency: user + session + game + item + category. Use `storageString` for persistence and lookups.
//

import Foundation

/// Category axis for XP idempotency (same user cannot farm base discovery XP for the same slot).
enum XpLedgerCategory: String, Codable, CaseIterable, Sendable {
    /// Base region/target discovery credit (idempotent per user/session/game/item).
    case baseRegionDiscovery = "base_region_discovery"
    case tripCompletion = "trip_completion"
    case milestoneUnlock = "milestone_unlock"
    case reconciliation = "reconciliation"
    case returnStreakDaily = "return_streak_daily"
}

struct XpUniquenessKey: Hashable, Equatable, Sendable, Codable {
    var userId: String
    var sessionId: UUID
    var gameInstanceId: UUID
    var itemId: String
    var xpCategory: XpLedgerCategory

    /// Deterministic canonical key (must stay aligned with `XpLedgerKeyBuilder.canonicalStorageString`).
    var storageString: String {
        let sid = sessionId.uuidString.lowercased()
        let gid = gameInstanceId.uuidString.lowercased()
        return "xp|v1|\(userId)|\(sid)|\(gid)|\(itemId)|\(xpCategory.rawValue)"
    }
}
