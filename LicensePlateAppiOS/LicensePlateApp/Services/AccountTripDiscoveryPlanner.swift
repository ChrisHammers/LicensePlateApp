//
//  AccountTripDiscoveryPlanner.swift
//  LicensePlateApp
//
//  §3.1.1 item 19 — account-scoped trip discovery: every trip the account CREATED or
//  JOINED follows it to any device it signs into.
//
//  This file holds the WHOLE policy of that channel as pure, synchronous rules, so the
//  behaviour is unit-testable without Firestore (same shape as `LiveTripListenerEligibility`):
//
//   - `AccountTripDiscoveryGate` — may this device bind the discovery listener at all.
//     It FAILS CLOSED, which is the part that matters: the FR-28 cloud-sync hold resolves
//     to `.notChild` on a device that has never resolved the child posture for this uid, so
//     binding on that signal alone would bulk-import a child's whole trip history through
//     `fetchTripBootstrapForMember` (the one trip callable with no server child gate) in the
//     window before `users/{uid}` is read. A posture that is not yet RESOLVED is treated as
//     "do not bind", not as "not a child".
//   - `AccountTripDiscoveryPlanner` — what to do with each discovered session id.
//     Import is ABSENT-ONLY (OD-16: the client is assumed correct; a background import must
//     never overwrite an unpublished local-first game or an offline status change), cancelled
//     trips are never imported, ended trips get no incremental listeners, and an unresolved
//     status is a RETRY rather than a decision (the member doc is written before the session
//     doc, so a discovery snapshot can legitimately arrive before the trip exists to read).
//

import Foundation

// MARK: - Gate (COPPA / identity; fail-closed)

/// Why discovery did not bind. Carried into the DEBUG trace as `gate.skip reason=…`.
nonisolated enum AccountTripDiscoverySkipReason: String, Equatable, Sendable {
    case noUserId = "no_user_id"
    case authMismatch = "auth_mismatch"
    case identityDetached = "identity_detached"
    case cloudSyncHeld = "cloud_sync_held"
    case childPostureUnresolved = "child_posture_unresolved"
}

nonisolated enum AccountTripDiscoveryGateDecision: Equatable, Sendable {
    case bind(userId: String)
    case skip(reason: AccountTripDiscoverySkipReason)

    var boundUserId: String? {
        if case .bind(let userId) = self { return userId }
        return nil
    }
}

nonisolated enum AccountTripDiscoveryGate {

    /// The five predicates, in reason order.
    ///
    /// The first four are exactly `LiveTripListenerEligibility.cloudChannelUserId` — the same
    /// funnel the live trip listeners use, so discovery can never be bound in a posture where
    /// the rest of the cloud trip channel is held. The fifth is discovery-only and exists
    /// because discovery is the first cloud trip read that does NOT require a local row: it
    /// fires on a brand-new device, which is precisely where the child posture has not been
    /// resolved yet.
    ///
    /// - Parameter isChildPostureResolved: whether this device has any evidence at all about
    ///   whether `userId` is a child account — see `isChildPostureResolved(…)`.
    static func decide(
        userId: String?,
        authenticatedUserId: String?,
        isCloudSyncHeld: Bool,
        isIdentityDetached: Bool,
        isChildPostureResolved: Bool
    ) -> AccountTripDiscoveryGateDecision {
        guard let userId, !userId.isEmpty else { return .skip(reason: .noUserId) }
        guard let authenticatedUserId, authenticatedUserId == userId else {
            return .skip(reason: .authMismatch)
        }
        guard !isIdentityDetached else { return .skip(reason: .identityDetached) }
        guard !isCloudSyncHeld else { return .skip(reason: .cloudSyncHeld) }
        guard isChildPostureResolved else { return .skip(reason: .childPostureUnresolved) }
        return .bind(userId: userId)
    }

    /// Is the child posture for this uid DECIDED on this device?
    ///
    /// Any one of the three signals `ChildRestrictedModeService.childSessionState` consults is
    /// enough, because each of them decides the question: this session's fresh
    /// `users/{uid}.isChildAccount` read (either value), this device's cached last resolution
    /// for the uid, or a device-declared under-13 lineage bound to it. `nil` everywhere means
    /// "we have not looked yet" — never "adult".
    static func isChildPostureResolved(
        freshIsChildAccount: Bool?,
        cachedIsChildAccount: Bool?,
        isDeclaredChildIdentity: Bool
    ) -> Bool {
        freshIsChildAccount != nil || cachedIsChildAccount != nil || isDeclaredChildIdentity
    }
}

// MARK: - One discovery snapshot, in domain terms

/// What the account-scoped membership listener delivered, with the Firestore types already
/// stripped: the trip ids the account is on the roster of, and whether the snapshot came from
/// the local cache (a Firestore listener normally delivers cache THEN server).
///
/// The service binds through an injectable factory producing exactly this, so the bind /
/// re-bind / retire lifecycle is pinnable with no configured `FirebaseApp`.
nonisolated struct AccountTripDiscoverySnapshot: Equatable, Sendable {
    var sessionIds: [UUID]
    var isFromCache: Bool

    init(sessionIds: [UUID], isFromCache: Bool) {
        self.sessionIds = sessionIds
        self.isFromCache = isFromCache
    }
}

// MARK: - Per-id status this device resolved from `trip_sessions/{id}`

/// What the discovering device learned about a discovered trip.
///
/// `unresolved` covers every "we do not know yet" case — the session doc is missing (the
/// publish race: `members/{uid}` is written before the parent doc), unreadable, or carries a
/// status this build does not know. It is deliberately NOT folded into "import without
/// listeners": a genuinely active trip imported during a transient read failure would sit on
/// Home with no listeners and no self-heal.
nonisolated enum DiscoveredTripStatus: Equatable, Sendable {
    /// `created` or `active` — import AND attach the incremental listeners.
    case live
    /// `ended` — import, no listeners. `endedAt` orders a bulk restore newest-first.
    case ended(endedAt: Date?)
    /// `cancelled` — never imported.
    case cancelled
    /// Not knowable this pass; retry.
    case unresolved
}

// MARK: - Plan

nonisolated enum AccountTripDiscoveryAction: Equatable, Sendable {
    case importLive
    case importEnded
    case skipLocal
    case skipInFlight
    case skipCancelled
    case retry
}

nonisolated struct AccountTripDiscoveryPlan: Equatable, Sendable {
    /// Import and attach incremental listeners, in discovery order.
    var importLive: [UUID] = []
    /// Import with NO listeners, newest-ended first.
    var importEnded: [UUID] = []
    var skippedLocal: [UUID] = []
    var skippedInFlight: [UUID] = []
    var skippedCancelled: [UUID] = []
    var retry: [UUID] = []

    /// Live trips first, then ended newest-first — the order a bulk restore runs serially in.
    var importOrder: [UUID] { importLive + importEnded }

    var isEmpty: Bool {
        importLive.isEmpty && importEnded.isEmpty && skippedLocal.isEmpty
            && skippedInFlight.isEmpty && skippedCancelled.isEmpty && retry.isEmpty
    }
}

nonisolated enum AccountTripDiscoveryPlanner {

    /// The one rule, per id. Order is load-bearing: a session this device already holds is
    /// skipped BEFORE its status is consulted (OD-16 — discovery never touches local truth),
    /// and an import already running for the id is skipped before that, so the cache-then-server
    /// pair of snapshots a Firestore listener normally delivers cannot double-import.
    static func action(
        sessionId: UUID,
        localSessionIds: Set<UUID>,
        inFlightSessionIds: Set<UUID>,
        status: DiscoveredTripStatus?
    ) -> AccountTripDiscoveryAction {
        if localSessionIds.contains(sessionId) { return .skipLocal }
        if inFlightSessionIds.contains(sessionId) { return .skipInFlight }
        switch status {
        case .some(.live): return .importLive
        case .some(.ended): return .importEnded
        case .some(.cancelled): return .skipCancelled
        case .some(.unresolved), .none: return .retry
        }
    }

    /// The ids a pass must read `trip_sessions/{id}` for. Anything already held locally or
    /// already importing needs no read at all.
    static func idsNeedingStatus(
        discoveredSessionIds: [UUID],
        localSessionIds: Set<UUID>,
        inFlightSessionIds: Set<UUID>
    ) -> [UUID] {
        discoveredSessionIds.filter {
            !localSessionIds.contains($0) && !inFlightSessionIds.contains($0)
        }
    }

    static func plan(
        discoveredSessionIds: [UUID],
        localSessionIds: Set<UUID>,
        inFlightSessionIds: Set<UUID>,
        statusById: [UUID: DiscoveredTripStatus]
    ) -> AccountTripDiscoveryPlan {
        var plan = AccountTripDiscoveryPlan()
        var endedWithTimestamp: [(id: UUID, endedAt: Date?)] = []
        for sessionId in discoveredSessionIds {
            let status = statusById[sessionId]
            switch action(
                sessionId: sessionId,
                localSessionIds: localSessionIds,
                inFlightSessionIds: inFlightSessionIds,
                status: status
            ) {
            case .importLive:
                plan.importLive.append(sessionId)
            case .importEnded:
                if case .some(.ended(let endedAt)) = status {
                    endedWithTimestamp.append((sessionId, endedAt))
                } else {
                    endedWithTimestamp.append((sessionId, nil))
                }
            case .skipLocal:
                plan.skippedLocal.append(sessionId)
            case .skipInFlight:
                plan.skippedInFlight.append(sessionId)
            case .skipCancelled:
                plan.skippedCancelled.append(sessionId)
            case .retry:
                plan.retry.append(sessionId)
            }
        }
        // Newest-ended first, with unknown timestamps last; ties keep discovery order.
        plan.importEnded = endedWithTimestamp
            .enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.endedAt ?? .distantPast
                let r = rhs.element.endedAt ?? .distantPast
                if l != r { return l > r }
                return lhs.offset < rhs.offset
            }
            .map(\.element.id)
        return plan
    }
}
