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
    /// FR-28e local mirror of the server scope `lifetime_unique_region|v1|<uid>|<regionId>`.
    /// Written under `XpLedgerGlobalScope` so the key is lifetime-wide, not session-wide —
    /// exactly like the server scope it mirrors.
    case lifetimeUniqueRegion = "lifetime_unique_region"
    /// FR-28e local mirror of the server scope `first_find_of_day|v1|<uid>|<dayKey>`.
    /// Also written under `XpLedgerGlobalScope`; `itemId` is the day key.
    case firstFindOfDay = "first_find_of_day"
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

    /// Everything the key identifies apart from *who* earned it.
    ///
    /// This is the rebind-stable half. `LocalPlayIdentityRepository` retires a local-first
    /// child's device UUID for a real uid at share-code redemption (COPPA F-18 / FR-60) and
    /// rewrites `XpLedgerEventEntity.userId`, but a key string written before that still names
    /// the retired identity. Comparing slots is how a stored row is recognised as *this* award
    /// slot regardless of which identity minted it.
    var slot: Slot {
        Slot(sessionId: sessionId, gameInstanceId: gameInstanceId, itemId: itemId, xpCategory: xpCategory)
    }

    struct Slot: Hashable, Equatable, Sendable {
        var sessionId: UUID
        var gameInstanceId: UUID
        var itemId: String
        var xpCategory: XpLedgerCategory
    }

    /// Parses a canonical `xp|v1|<userId>|<sessionUUID>|<gameUUID>|<itemId>|<category>` string.
    ///
    /// Returns nil for anything not in that exact shape, so callers fail safe (no repair, no
    /// match) rather than mangling a key they do not understand. Safe to split on `|` because
    /// no segment can contain one: ids are UUIDs or Firebase uids, `itemId` is a region id or a
    /// reason/day key, and categories are fixed raw values.
    static func parse(storageString: String) -> XpUniquenessKey? {
        let parts = storageString.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 7, parts[0] == "xp", parts[1] == "v1" else { return nil }
        guard !parts[2].isEmpty, !parts[5].isEmpty else { return nil }
        guard let sessionId = UUID(uuidString: parts[3]),
              let gameInstanceId = UUID(uuidString: parts[4]),
              let category = XpLedgerCategory(rawValue: parts[6])
        else { return nil }
        return XpUniquenessKey(
            userId: parts[2],
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            itemId: parts[5],
            xpCategory: category
        )
    }
}
