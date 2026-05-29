//
//  XpLedgerKeyBuilder.swift
//  LicensePlateApp
//
//  Deterministic idempotency key: `xp|v1|<userId>|<sessionUUID>|<gameUUID>|<itemId>|<category>`.
//  UUID segments are lowercased canonical string form.
//

import Foundation

enum XpLedgerKeyBuilder {

    /// Canonical storage string; must match `XpUniquenessKey.storageString`.
    static func canonicalStorageString(from key: XpUniquenessKey) -> String {
        let sid = key.sessionId.uuidString.lowercased()
        let gid = key.gameInstanceId.uuidString.lowercased()
        return "xp|v1|\(key.userId)|\(sid)|\(gid)|\(key.itemId)|\(key.xpCategory.rawValue)"
    }

    /// Build key from parts (same canonicalization as `XpUniquenessKey`).
    static func uniquenessKey(
        userId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        itemId: String,
        xpCategory: XpLedgerCategory
    ) -> XpUniquenessKey {
        XpUniquenessKey(
            userId: userId,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            itemId: itemId,
            xpCategory: xpCategory
        )
    }
}
