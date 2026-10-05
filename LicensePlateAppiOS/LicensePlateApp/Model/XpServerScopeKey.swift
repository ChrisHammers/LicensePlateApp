//
//  XpServerScopeKey.swift
//  LicensePlateApp
//
//  The SERVER-side award identities a local XP ledger row mirrors: the component scope key the
//  server writes into `appliedProgressionScopes` / a grant's `idempotencyKey`, and the id the
//  server authors a superseded competitive find under.
//
//  Neutral home (§3.1.1 item 17): both the XP toast (`XpGainToastEligibility`, item 14) and the
//  displayed-total read model (`LedgerPendingXpTotals`) join on these strings, so the derivation
//  lives in Model with exactly ONE implementation rather than being reached for across layers.
//  The one documented exception is total-only: `baseDiscoveryTotalOnlyScope(for:)` (§3.1.1 item 29a).
//

import Foundation

enum XpServerScopeKey {

    /// `srvrej_<clientEventId>` — the activity-event document id the server authors when this
    /// device's competitive `region_found` loses to an earlier find.
    ///
    /// The client's own event is NEVER written remotely on that path
    /// (`functions/src/gameplayEventResolver.ts`, `serverRejectionEventId` :513-514, written at
    /// :767-812), and `progressionCore.previewProgressionComponentsForActivityEvent` grants the
    /// base discovery + both find bonuses off THAT document
    /// (`functions/src/progressionCore.ts` `KIND_DISCOVERY_REJECTED` branch, :523-542). So
    /// `appliedProgressionEvents` records `srvrej_<clientEventId>` and never `<clientEventId>` —
    /// which is why a retirement keyed on the local id alone leaves the rows open forever.
    static func serverRejectionEventId(forClientEventId clientEventId: String) -> String {
        "srvrej_\(clientEventId)"
    }

    /// The SERVER award scope string this local ledger row mirrors, or `nil` when the row has no
    /// server counterpart to join against.
    ///
    /// This is the join the XP toast dedups on, in BOTH directions: a remote grant carries its
    /// component scope as `idempotencyKey` (`functions/src/progressionOnActivityEvent.ts:148-156`,
    /// decoded at `Repositories/XpGrantRemoteRepository.swift`), so "this device already announced
    /// this award" and "the server already granted this award" are comparable without either side's
    /// event id. That id-independence is the whole point: it closes the late-competitive variant,
    /// where the server authors its grant off `srvrej_<clientEventId>` while the local row carries
    /// the client id (`functions/src/gameplayEventResolver.ts`), and the variant where two devices
    /// author the same completion event and only one event id ever reaches a grant.
    ///
    /// §3.1.1 item 17 added the second consumer: the same string is what the server stamps into
    /// `user_progression.appliedProgressionScopes` in the transaction that increments `totalXp`
    /// (`progressionOnActivityEvent.ts:118-178`), so "the scope is applied" means "that award is
    /// already inside the server total" and `LedgerPendingXpTotals` retires the mirroring local row
    /// on it.
    ///
    /// Byte-for-byte mirrors of `functions/src/progressionCore.ts`:
    ///   * `lifetimeUniqueRegionScopeKey`   (:281-283) `lifetime_unique_region|v1|<uid>|<regionId>`
    ///   * `firstFindOfDayScopeKey`         (:285-287) `first_find_of_day|v1|<uid>|<dayKey>`
    ///   * `gameEndedScopeKey`              (:289-291) `game_ended|v1|<uid>|<gameInstanceId>`
    ///   * `gameFullClearScopeKey`          (:293-295) `game_full_clear|v1|<uid>|<gameInstanceId>`
    ///   * `competitivePlaceScopeKey`       (:297-304) `competitive_place|<n>|v1|<uid>|<gameInstanceId>`
    ///   * `tripEndedScopeKey`              (:306-308) `trip_ended|v1|<uid>|<sessionId>`
    ///   * `tripParticipationScopeKey`      (:310-312) `trip_participation|v1|<uid>|<sessionId>`
    ///   * `tripCompetitiveFirstScopeKey`   (:314-316) `trip_competitive_first|v1|<uid>|<sessionId>`
    ///
    /// These are SERVER scope strings, NOT `XpUniquenessKey.storageString`: the local storage key
    /// lowercases its UUID segments on purpose (`Model/XpUniquenessKey.swift:36-37`,
    /// `Services/XpLedgerKeyBuilder.swift:15-16`) and the server scope does not.
    ///
    /// CASING: the server reads `gameInstanceId` out of the activity-event payload, which this
    /// client stamps as `UUID.uuidString` — UPPERCASE (`Services/GameInstanceLifecycleService.swift:114`,
    /// `:153`, `:189`; `Services/TripSessionFactory.swift:106`) — and it reads `sessionId` from the
    /// `trip_sessions/{sessionId}` document id, which this client also writes as `UUID.uuidString`
    /// (`Services/TripCanonicalRemoteSyncService.swift:363`,
    /// `Services/FairnessAckWatermarkRemoteService.swift:25`,
    /// `Services/TripParticipantPrefsStore.swift:79`). So `uuidString` here matches what the server
    /// wrote, with no case folding on either side. `regionId` and the `yyyy-MM-dd` day key travel
    /// verbatim and carry no case question.
    ///
    /// Switched exhaustively with no `default:` so a new `XpReasonCode` cannot be added without a
    /// decision about whether it mirrors a server award.
    ///
    /// SERVER DEPENDENCY (§3.1.1 item 18, deliberately not handled here): on the `srvrej_` path the
    /// `first_find_of_day` scope matches only because the server-authored rejection payload carries
    /// the client's `xpDayKey` (`gameplayEventResolver.ts`). A server without item 18 bills under the
    /// UTC day of the rejection, that one scope string differs from the local one, and that find's
    /// first-of-day bonus doubles in the TOAST. The displayed TOTAL is unaffected either way:
    /// `LedgerPendingXpTotals` also retires on `serverRejectionEventId(forClientEventId:)`, which
    /// carries no day at all.
    static func mirrored(for row: XpLedgerEvent) -> String? {
        switch row.reasonCode {
        // ---- Local-first find bonuses. Account-scoped: the row's `sessionId`/`gameInstanceId` are
        //      the global sentinels and `itemId` carries the discriminator the server uses.
        case .lifetimeUniqueRegion:
            guard !row.itemId.isEmpty else { return nil }
            return "lifetime_unique_region|v1|\(row.userId)|\(row.itemId)"
        case .firstFindOfDay:
            guard !row.itemId.isEmpty else { return nil }
            return "first_find_of_day|v1|\(row.userId)|\(row.itemId)"

        // ---- Completion awards, written as `.tripCompletion` rows by
        //      `XpReconciliationService.handleCompletionEventThrowing`. Game-scoped components carry
        //      the real `gameInstanceId`; trip-scoped ones carry the real `sessionId`.
        case .gameEnded:
            return gameScopedCompletionScopeKey(prefix: "game_ended", row: row)
        case .gameFullClear:
            return gameScopedCompletionScopeKey(prefix: "game_full_clear", row: row)
        case .competitiveFirstPlaceFinish:
            return gameScopedCompletionScopeKey(prefix: "competitive_place|1", row: row)
        case .competitiveSecondPlace:
            return gameScopedCompletionScopeKey(prefix: "competitive_place|2", row: row)
        case .competitiveThirdPlace:
            return gameScopedCompletionScopeKey(prefix: "competitive_place|3", row: row)
        case .tripEnded:
            return sessionScopedCompletionScopeKey(prefix: "trip_ended", row: row)
        case .tripParticipation:
            return sessionScopedCompletionScopeKey(prefix: "trip_participation", row: row)
        case .tripCompetitiveFirstPlace:
            return sessionScopedCompletionScopeKey(prefix: "trip_competitive_first", row: row)

        // ---- Base discovery, in all four of its local labels. The server mirror is
        //      `region_found_base_discovery`, which `shouldToastRemoteGrant` already excludes by
        //      reason; giving these rows a scope would add a second rule for an award that has one.
        //      (The displayed TOTAL joins them on `baseDiscoveryTotalOnlyScope(for:)` instead.)
        case .soloNewDiscovery, .collaborativeSharedFinder, .competitiveLateFinder,
             .discoveryClaimPendingResolution:
            return nil

        // ---- `competitive_first_finder` is a LABEL on the settled base award locally (amount =
        //      base discovery XP, `Services/XpAwardRuleEngine.swift`), while on the server it is a
        //      SEPARATE +5 component with its own `xp_scope|…|competitive_first_finder` key
        //      (progressionCore.ts:377-390). Different money — joining them would suppress an award
        //      this device never announced.
        case .competitiveFirstFinder:
            return nil

        // ---- Return streak keeps its reason-level exclusion in `shouldToastRemoteGrant`.
        case .returnStreakDaily:
            return nil

        // ---- No-XP markers: never positive, so they never reach a toast or a scope ack.
        //      `spam_toggle_no_xp` additionally has no writer anywhere in the app.
        case .duplicateNoXp, .personalRefindNoXp, .spamToggleNoXp, .riskRejectedNoXp:
            return nil

        // ---- Dead cases. `trip_completion` is legacy and unused as a reason code; `milestone_unlock`
        //      as a REASON has no writer (ReturnStreakService writes the `.milestoneUnlock` grant KIND
        //      under `.returnStreakDaily`), and achievement XP is server-only.
        case .tripCompletion, .milestoneUnlock:
            return nil
        }
    }

    /// `xp_scope|v1|<uid>|<sessionId>|<gameInstanceId>|<regionId>|base_region_discovery` — the
    /// SERVER scope of the base find award this row mirrors, or `nil` when the row is not a base
    /// discovery award. Byte-for-byte `baseRegionDiscoveryScopeKey` (`functions/src/progressionCore.ts`
    /// :259-269): `uid` is the payload's `participantId` (the row's `userId`), `sessionId` is the
    /// `trip_sessions/{id}` document id and `gameInstanceId` / `regionId` are the payload strings —
    /// all `UUID.uuidString` (UPPERCASE) on this client, per the CASING note on `mirrored(for:)`.
    ///
    /// TOTAL-ONLY (§3.1.1 item 29a). `LedgerPendingXpTotals` retires a base row on this scope; the XP
    /// toast must NOT, which is why it is deliberately not a case of `mirrored(for:)`. The toast
    /// joins `mirrored(for:)` against every grant's `idempotencyKey`, and the server's base grant
    /// carries this scope — so the finding device would stop announcing its own find whenever the
    /// account's other device got there first, a toast rule this item does not change. The total
    /// needs it because the same account can find the same plate in the same game on two devices:
    /// the server pays the base award once, under THIS scope, off whichever event lands first, and
    /// stamps the second event with no increment (`functions/src/progressionOnActivityEvent.ts`
    /// :130-133). The second device's row matches neither its own event id (until that stamp) nor
    /// the paying event's id, so without this join it counts the award a second time on top of a
    /// server total that already holds it — and then drops by it when its own event is stamped
    /// (OD-17: a shown number never goes down).
    ///
    /// The reasons are every label a base award carries locally: the provisional competitive claim
    /// (`XpReconciliationService.handleCommittedActivityEventThrowing`) plus the four settled labels
    /// `XpAwardRuleEngine.xpNetAndReason` gives a positive base amount. `competitive_first_finder` is
    /// the BASE award locally (its +5 server component has a scope of its own), so it belongs here.
    static func baseDiscoveryTotalOnlyScope(for row: XpLedgerEvent) -> String? {
        guard row.grantKind == .provisionalDiscoveryXp || row.grantKind == .finalDiscoveryAward else {
            return nil
        }
        switch row.reasonCode {
        case .discoveryClaimPendingResolution, .soloNewDiscovery, .collaborativeSharedFinder,
             .competitiveFirstFinder, .competitiveLateFinder:
            break
        default:
            return nil
        }
        guard !row.itemId.isEmpty,
              row.sessionId != XpLedgerGlobalScope.sessionId,
              row.gameInstanceId != XpLedgerGlobalScope.gameInstanceId else { return nil }
        return "xp_scope|v1|\(row.userId)|\(row.sessionId.uuidString)|\(row.gameInstanceId.uuidString)"
            + "|\(row.itemId)|base_region_discovery"
    }

    /// `<prefix>|v1|<uid>|<gameInstanceId>` for a completion row scoped to one game instance.
    private static func gameScopedCompletionScopeKey(prefix: String, row: XpLedgerEvent) -> String? {
        guard row.grantKind == .tripCompletion else { return nil }
        guard row.gameInstanceId != XpLedgerGlobalScope.gameInstanceId else { return nil }
        return "\(prefix)|v1|\(row.userId)|\(row.gameInstanceId.uuidString)"
    }

    /// `<prefix>|v1|<uid>|<sessionId>` for a completion row scoped to the trip session.
    private static func sessionScopedCompletionScopeKey(prefix: String, row: XpLedgerEvent) -> String? {
        guard row.grantKind == .tripCompletion else { return nil }
        guard row.sessionId != XpLedgerGlobalScope.sessionId else { return nil }
        return "\(prefix)|v1|\(row.userId)|\(row.sessionId.uuidString)"
    }
}
