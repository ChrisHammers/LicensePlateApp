//
//  LocalPlayIdentityRepository.swift
//  LicensePlateApp
//
//  COPPA F-18 (FR-60(b)/(d)) — carrying local play history across the one identity
//  transition the local-first child model creates.
//
//  Before FR-60 this problem did not exist. A guest's local `AppUser.id` was a UUID for
//  milliseconds: `createFreshLocalGuestUser()` made it and `signInAnonymously()` replaced it
//  with the Firebase uid before the user could start a trip. Under FR-60 an under-13 player
//  never provisions, so that UUID is their play identity for as long as they play locally —
//  days or weeks of trips, discoveries and XP — and the uid only arrives when they enter a
//  share code.
//
//  Every local store stamps the play identity as a plain string (`TripSession.createdBy`,
//  `TripParticipant.userId`, `TripActivityEvent.actorId` and its `participantId` payload,
//  `XpLedgerEvent.userId`, achievement and lifetime-stats rows), and the app resolves that
//  identity as `firebaseUID ?? id`. So the moment the uid lands, every one of those rows
//  names an identity the app no longer recognises: the home list and travel log filter the
//  child's own trips out, `UserProgressionService`'s roster check fails and XP reads as
//  zero, and `isTripCreator` says false for trips they created. FR-28h late-replay would
//  then have nothing correct to upload — which is precisely the history D-25 promises
//  survives the consent boundary, unbounded, for exactly this population.
//
//  `AppUser.localIDBeforeFirebase` was declared for this and never written; this repository
//  is what finally does the work, and `FirebaseAuthService` populates that field alongside.
//
//  Layering (CLAUDE.md): the SwiftData sweep lives here, in the repository layer. The
//  rewriting RULES are pure and live in `LocalPlayIdentityRebindPolicy` below so the
//  identity-substitution semantics are unit-testable without a ModelContext.
//

import Foundation
import SwiftData

// MARK: - Pure rewrite rules

/// Substitution semantics for the rebind: **a value is rewritten if and only if it is
/// exactly the previous local identity.**
///
/// That equality test is the whole safety argument. The previous identity is a UUID this
/// device minted for one unprovisioned guest, so no other participant, actor or ledger row
/// can carry it — a multiplayer trip the child later joins is untouched, and a server-stamped
/// value cannot collide because the server has never seen this account. It also makes the
/// pass idempotent: after one run nothing equals the old id, so a second run is a no-op.
enum LocalPlayIdentityRebindPolicy {

    /// Guard for the whole pass. A missing, empty or unchanged previous identity has nothing
    /// to rebind, and rebinding onto an empty id would erase ownership.
    static func shouldRebind(previousUserId: String?, newUserId: String) -> Bool {
        guard let previousUserId, !previousUserId.isEmpty, !newUserId.isEmpty else { return false }
        return previousUserId != newUserId
    }

    /// Scalar field substitution.
    static func rebound(_ value: String?, from previousUserId: String, to newUserId: String) -> String? {
        value == previousUserId ? newUserId : value
    }

    /// `TripSessionEntity.participantsData` — JSON `[TripParticipant]`.
    /// - Returns: the re-encoded blob, or nil when nothing changed (so the caller can skip
    ///   the write and keep the pass a genuine no-op on re-run).
    static func reboundParticipantsData(
        _ data: Data?,
        from previousUserId: String,
        to newUserId: String
    ) -> Data? {
        guard let data,
              var participants = try? JSONDecoder().decode([TripParticipant].self, from: data),
              participants.contains(where: { $0.userId == previousUserId }) else {
            return nil
        }
        for index in participants.indices where participants[index].userId == previousUserId {
            participants[index].userId = newUserId
        }
        return try? JSONEncoder().encode(participants)
    }

    /// `TripActivityEventEntity.payloadData` — JSON `[String: String]`.
    ///
    /// Every key is considered rather than an allowlist of known identity keys
    /// (`participantId`, `initiatedByUserId`, …): the equality test already scopes the
    /// rewrite to this one device-local identity, and an allowlist would silently miss a
    /// payload key added later — leaving a stale identity in exactly the data FR-28h uploads.
    static func reboundPayloadData(
        _ data: Data?,
        from previousUserId: String,
        to newUserId: String
    ) -> Data? {
        guard let data,
              var payload = try? JSONDecoder().decode([String: String].self, from: data),
              payload.values.contains(previousUserId) else {
            return nil
        }
        for (key, value) in payload where value == previousUserId {
            payload[key] = newUserId
        }
        return try? JSONEncoder().encode(payload)
    }
}

// MARK: - Summary

/// Per-store counts, for the DEBUG log and for the tests that pin the sweep's coverage.
struct LocalPlayIdentityRebindSummary: Equatable {
    var tripSessions = 0
    var activityEvents = 0
    var discoveryResolutions = 0
    var xpLedgerEvents = 0
    var achievements = 0
    var lifetimeStats = 0

    var totalRowsRewritten: Int {
        tripSessions + activityEvents + discoveryResolutions + xpLedgerEvents
            + achievements + lifetimeStats
    }

    static let none = LocalPlayIdentityRebindSummary()
}

// MARK: - Repository

enum LocalPlayIdentityRepositoryError: Error {
    case noModelContext
}

@MainActor
final class LocalPlayIdentityRepository {
    static let shared = LocalPlayIdentityRepository()

    private var modelContext: ModelContext?

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    /// Rewrites every local gameplay/progression row that names `previousUserId` to name
    /// `newUserId`, in one saved transaction.
    ///
    /// Deliberately NOT swept: `PublicLifetimeStatsCacheEntity` and `PendingTripLeaveEntity`.
    /// Both are caches/queues of SERVER state keyed by uid, and an account that has just been
    /// provisioned has no server state to have cached — there is nothing under the old
    /// identity to carry, and rewriting a cache key would fabricate a mirror row for a
    /// document that does not exist. `TripRoutePointEntity` carries no identity at all (it is
    /// keyed on the trip), so it needs nothing.
    @discardableResult
    func rebindLocalPlayIdentity(
        from previousUserId: String?,
        to newUserId: String
    ) throws -> LocalPlayIdentityRebindSummary {
        guard LocalPlayIdentityRebindPolicy.shouldRebind(
            previousUserId: previousUserId,
            newUserId: newUserId
        ), let previousUserId else {
            return .none
        }
        guard let context = modelContext else {
            throw LocalPlayIdentityRepositoryError.noModelContext
        }

        var summary = LocalPlayIdentityRebindSummary()

        // ---- Trips: ownership, the end stamp, and the participant roster.
        let sessions = try context.fetch(FetchDescriptor<TripSessionEntity>())
        for session in sessions {
            var changed = false
            if session.createdBy == previousUserId {
                session.createdBy = newUserId
                changed = true
            }
            if session.endedBy == previousUserId {
                session.endedBy = newUserId
                changed = true
            }
            if let rebound = LocalPlayIdentityRebindPolicy.reboundParticipantsData(
                session.participantsData, from: previousUserId, to: newUserId
            ) {
                session.participantsData = rebound
                changed = true
            }
            if changed { summary.tripSessions += 1 }
        }

        // ---- Activity events: the append-only log FR-28h replays to the server.
        let events = try context.fetch(FetchDescriptor<TripActivityEventEntity>())
        for event in events {
            var changed = false
            if event.actorId == previousUserId {
                event.actorId = newUserId
                changed = true
            }
            if let rebound = LocalPlayIdentityRebindPolicy.reboundPayloadData(
                event.payloadData, from: previousUserId, to: newUserId
            ) {
                event.payloadData = rebound
                changed = true
            }
            if changed { summary.activityEvents += 1 }
        }

        // ---- Discovery resolutions (local projections of who found what).
        let resolutions = try context.fetch(FetchDescriptor<DiscoveryResolutionEntity>())
        for resolution in resolutions where resolution.actorUserId == previousUserId {
            resolution.actorUserId = newUserId
            summary.discoveryResolutions += 1
        }

        // ---- XP ledger: without this the child's whole XP total reads as zero.
        //      `xpUniquenessKey` is DERIVED from the uid (like `recordKey` below) and every
        //      idempotency check in `XpLedgerRepository` is key-string equality — leaving the
        //      stale key made late-replay reconciliation miss and double-award (device-pass
        //      Bug A, 2026-08-15). The repository also self-repairs stale keys at its call
        //      sites; this is the belt half of that belt-and-braces.
        let ledgerRows = try context.fetch(FetchDescriptor<XpLedgerEventEntity>())
        for row in ledgerRows where row.userId == previousUserId {
            row.userId = newUserId
            if let parsed = XpUniquenessKey.parse(storageString: row.xpUniquenessKey),
               parsed.userId == previousUserId {
                row.xpUniquenessKey = XpUniquenessKey(
                    userId: newUserId,
                    sessionId: parsed.sessionId,
                    gameInstanceId: parsed.gameInstanceId,
                    itemId: parsed.itemId,
                    xpCategory: parsed.xpCategory
                ).storageString
            }
            summary.xpLedgerEvents += 1
        }

        // ---- Achievements. `recordKey` is `@Attribute(.unique)` and derived from the uid,
        //      so it has to be recomputed in step with `userId` or the row would keep a key
        //      that no lookup for the new identity can ever match.
        let achievements = try context.fetch(FetchDescriptor<UserAchievementEntity>())
        for achievement in achievements where achievement.userId == previousUserId {
            achievement.userId = newUserId
            achievement.recordKey = UserAchievementEntity.makeRecordKey(
                userId: newUserId,
                achievementId: achievement.achievementId
            )
            summary.achievements += 1
        }

        // ---- Lifetime stats. `userId` is the unique key; a freshly minted uid cannot
        //      already have a row, so there is no collision to resolve.
        let lifetimeStats = try context.fetch(FetchDescriptor<UserLifetimeStatsEntity>())
        for stats in lifetimeStats where stats.userId == previousUserId {
            stats.userId = newUserId
            summary.lifetimeStats += 1
        }

        try context.save()
        return summary
    }
}
