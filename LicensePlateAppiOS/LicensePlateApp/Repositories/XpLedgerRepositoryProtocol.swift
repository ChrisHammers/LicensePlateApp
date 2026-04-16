//
//  XpLedgerRepositoryProtocol.swift
//  LicensePlateApp
//

import Foundation
import SwiftData

protocol XpLedgerRepositoryProtocol: AnyObject {
    func setModelContext(_ context: ModelContext)
    /// Append a ledger row (always inserts). Corrections must be new rows.
    func append(_ event: XpLedgerEvent) throws
    /// Idempotent base discovery: inserts only if no existing row for the same `xpUniquenessKey` with `provisionalDiscoveryXp` or `finalDiscoveryAward`.
    @discardableResult
    func appendBaseDiscoveryIfAbsent(_ event: XpLedgerEvent) throws -> Bool
    func ledgerEvents(userId: String, sessionId: UUID, gameInstanceId: UUID, itemId: String?) throws -> [XpLedgerEvent]
    func ledgerEvents(forUniquenessKey: String) throws -> [XpLedgerEvent]
    func ledgerEvents(sourceEventId: String) throws -> [XpLedgerEvent]
    func ledgerEvents(
        userId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        itemId: String?,
        statuses: Set<XpLedgerStatus>?
    ) throws -> [XpLedgerEvent]
    /// Sums `xpDelta` for rows matching scope and whose `status` is in `includingStatuses`.
    func netXpDelta(
        userId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        itemId: String?,
        includingStatuses: Set<XpLedgerStatus>
    ) throws -> Int
    func hasBaseDiscoveryForUniquenessKey(_ key: String) throws -> Bool
}
