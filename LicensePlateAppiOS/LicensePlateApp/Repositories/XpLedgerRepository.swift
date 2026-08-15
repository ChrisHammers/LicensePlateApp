//
//  XpLedgerRepository.swift
//  LicensePlateApp
//
//  Append-only XP ledger. No updates or deletes of existing rows.
//

import Foundation
import SwiftData
import Combine

enum XpLedgerRepositoryError: Error, Equatable {
    case noModelContext
    case appendBaseDiscoveryRequiresProvisionalOrFinalKind
}

@MainActor
final class XpLedgerRepository: ObservableObject, XpLedgerRepositoryProtocol {

    static let shared = XpLedgerRepository()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func append(_ event: XpLedgerEvent) throws {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        ctx.insert(XpLedgerMapper.toEntity(event))
        try ctx.save()
        objectWillChange.send()
    }

    func appendBaseDiscoveryIfAbsent(_ event: XpLedgerEvent) throws -> Bool {
        guard event.grantKind == .provisionalDiscoveryXp || event.grantKind == .finalDiscoveryAward else {
            throw XpLedgerRepositoryError.appendBaseDiscoveryRequiresProvisionalOrFinalKind
        }
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        try repairKeysRetiredByIdentityRebind(matching: event.xpUniquenessKey)
        if try hasBaseDiscoveryForUniquenessKey(event.xpUniquenessKey) {
            return false
        }
        ctx.insert(XpLedgerMapper.toEntity(event))
        try ctx.save()
        objectWillChange.send()
        return true
    }

    func appendIfAbsent(_ event: XpLedgerEvent) throws -> Bool {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        try repairKeysRetiredByIdentityRebind(matching: event.xpUniquenessKey)
        let key = event.xpUniquenessKey
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { entity in
                entity.xpUniquenessKey == key && entity.status != "voided"
            }
        )
        if try ctx.fetchCount(descriptor) > 0 {
            return false
        }
        ctx.insert(XpLedgerMapper.toEntity(event))
        try ctx.save()
        objectWillChange.send()
        return true
    }

    func hasBaseDiscoveryForUniquenessKey(_ key: String) throws -> Bool {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { entity in
                entity.xpUniquenessKey == key
                    && entity.status != "voided"
                    && (entity.grantKind == "provisional_discovery_xp" || entity.grantKind == "final_discovery_award")
            }
        )
        let count = try ctx.fetchCount(descriptor)
        return count > 0
    }

    @discardableResult
    func voidProvisionalRows(forUniquenessKey key: String, resolvedAt: Date) throws -> Int {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        try repairKeysRetiredByIdentityRebind(matching: key)
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { entity in
                entity.xpUniquenessKey == key
                    && entity.status == "provisional"
            }
        )
        let rows = try ctx.fetch(descriptor)
        var voidedSum = 0
        for row in rows {
            voidedSum += row.xpDelta
            row.status = XpLedgerStatus.voided.rawValue
            row.resolvedAt = resolvedAt
        }
        guard !rows.isEmpty else { return 0 }
        try ctx.save()
        objectWillChange.send()
        return voidedSum
    }

    func ledgerEvents(userId: String, sessionId: UUID, gameInstanceId: UUID, itemId: String?) throws -> [XpLedgerEvent] {
        try ledgerEvents(userId: userId, sessionId: sessionId, gameInstanceId: gameInstanceId, itemId: itemId, statuses: nil)
    }

    func ledgerEvents(
        userId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        itemId: String?,
        statuses: Set<XpLedgerStatus>?
    ) throws -> [XpLedgerEvent] {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        let gid = gameInstanceId.uuidString
        let rows: [XpLedgerEventEntity]
        if let itemId {
            let descriptor = FetchDescriptor<XpLedgerEventEntity>(
                predicate: #Predicate<XpLedgerEventEntity> { e in
                    e.userId == userId && e.sessionId == sid && e.gameInstanceId == gid && e.itemId == itemId
                }
            )
            rows = try ctx.fetch(descriptor)
        } else {
            let descriptor = FetchDescriptor<XpLedgerEventEntity>(
                predicate: #Predicate<XpLedgerEventEntity> { e in
                    e.userId == userId && e.sessionId == sid && e.gameInstanceId == gid
                }
            )
            rows = try ctx.fetch(descriptor)
        }
        return try sortedDomainEvents(from: rows, statuses: statuses)
    }

    func ledgerEvents(forUniquenessKey key: String) throws -> [XpLedgerEvent] {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        try repairKeysRetiredByIdentityRebind(matching: key)
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { $0.xpUniquenessKey == key }
        )
        let rows = try ctx.fetch(descriptor)
        return try sortedDomainEvents(from: rows, statuses: nil)
    }

    func ledgerEvents(sourceEventId: String) throws -> [XpLedgerEvent] {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { $0.sourceEventId == sourceEventId }
        )
        let rows = try ctx.fetch(descriptor)
        return try sortedDomainEvents(from: rows, statuses: nil)
    }

    func ledgerEvents(userId: String) throws -> [XpLedgerEvent] {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { e in
                e.userId == userId
            }
        )
        let rows = try ctx.fetch(descriptor)
        return try sortedDomainEvents(from: rows, statuses: nil)
    }

    func ledgerEvents(userId: String, sessionId: UUID) throws -> [XpLedgerEvent] {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        let sid = sessionId.uuidString
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { e in
                e.userId == userId && e.sessionId == sid
            }
        )
        let rows = try ctx.fetch(descriptor)
        return try sortedDomainEvents(from: rows, statuses: nil)
    }

    func netXpDelta(
        userId: String,
        sessionId: UUID,
        gameInstanceId: UUID,
        itemId: String?,
        includingStatuses: Set<XpLedgerStatus>
    ) throws -> Int {
        let events = try ledgerEvents(
            userId: userId,
            sessionId: sessionId,
            gameInstanceId: gameInstanceId,
            itemId: itemId,
            statuses: includingStatuses
        )
        return events.reduce(0) { $0 + $1.xpDelta }
    }

    /// Hard sign-out exception to append-only rule: wipe the local ledger.
    func deleteAllLocal() throws {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        try ctx.delete(model: XpLedgerEventEntity.self)
        try ctx.save()
        objectWillChange.send()
    }

    /// Repoints rows whose `xpUniquenessKey` still names an identity this device has retired.
    ///
    /// COPPA F-18 / FR-60: a local-first child plays for days under a device-minted UUID and only
    /// gets a uid when they enter a share code. `LocalPlayIdentityRepository.rebindLocalPlayIdentity`
    /// then rewrites `XpLedgerEventEntity.userId` — but `xpUniquenessKey` is a *derived* string
    /// (`xp|v1|<userId>|<session>|<game>|<item>|<category>`) and the sweep leaves it embedding the
    /// retired UUID. Every idempotency lookup in this repository is key equality, so after a rebind
    /// they all miss: `appendBaseDiscoveryIfAbsent` mints a second award for a discovery that
    /// already has one, and `voidProvisionalRows` fails to close the original provisional row, so
    /// one find ends up carrying two live rows (FR-28h late replay makes this happen to the child's
    /// whole pre-consent history at once).
    ///
    /// The repair is keyed on what the rebind *does* maintain: the row's `userId` column. Candidates
    /// are narrowed by `itemId` (a region id, a day key, or a reason raw value — cheap and
    /// selective) and then matched on the key's own parsed slot, so the repair does not assume the
    /// row's scope columns mirror its key (user-scoped rows deliberately key under
    /// `XpLedgerGlobalScope`). A row is only touched when it already belongs to the target user and
    /// occupies exactly the same award slot — a stale identity string is then the only thing that
    /// can differ, and rewriting it is an index repair, not a ledger mutation (the same repair
    /// `UserAchievementEntity.recordKey` already gets inside the sweep). Idempotent: after one
    /// pass nothing matches, so re-running is a no-op.
    private func repairKeysRetiredByIdentityRebind(matching key: String) throws {
        guard let ctx = modelContext else { throw XpLedgerRepositoryError.noModelContext }
        guard let target = XpUniquenessKey.parse(storageString: key) else { return }

        let userId = target.userId
        let itemId = target.itemId
        let descriptor = FetchDescriptor<XpLedgerEventEntity>(
            predicate: #Predicate<XpLedgerEventEntity> { entity in
                entity.userId == userId
                    && entity.itemId == itemId
                    && entity.xpUniquenessKey != key
            }
        )

        var didRepair = false
        for row in try ctx.fetch(descriptor) {
            guard let stored = XpUniquenessKey.parse(storageString: row.xpUniquenessKey) else { continue }
            guard stored.slot == target.slot, stored.userId != userId else { continue }
            row.xpUniquenessKey = key
            didRepair = true
        }
        guard didRepair else { return }
        try ctx.save()
        objectWillChange.send()
    }

    private func sortedDomainEvents(from rows: [XpLedgerEventEntity], statuses: Set<XpLedgerStatus>?) throws -> [XpLedgerEvent] {
        var mapped: [XpLedgerEvent] = []
        mapped.reserveCapacity(rows.count)
        for row in rows {
            let domain = try XpLedgerMapper.toDomain(row)
            if let statuses, !statuses.contains(domain.status) { continue }
            mapped.append(domain)
        }
        mapped.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
        return mapped
    }
}
