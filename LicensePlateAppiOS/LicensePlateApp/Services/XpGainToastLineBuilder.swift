//
//  XpGainToastLineBuilder.swift
//  LicensePlateApp
//
//  Eligibility rules for XP gain toast ingest (grouping lives in XpGainToastSourceMapper).
//

import Foundation

enum XpGainToastEligibility {

    static func shouldToastLedgerRow(_ row: XpLedgerEvent) -> Bool {
        row.xpDelta > 0
    }

    static func shouldToastRemoteGrant(_ grant: UserXpGrant) -> Bool {
        guard grant.amount > 0 else { return false }
        // Discovery and return-streak toast from local ledger (offline-first); skip remote re-toast.
        if grant.reason == UserXpGrantReason.regionFoundBaseDiscovery.rawValue { return false }
        if grant.reason == UserXpGrantReason.returnStreakDaily.rawValue { return false }
        // §3.1.1 item 12: a migration seal is bookkeeping, not a gain. `reconcileXpGrantLedger`
        // writes ONE row with `sourceType: "migration"` whose amount is `max(0, totalXp - sum(grants))`
        // (functions/src/reconcileXpGrantLedgerCore.ts, legacyUnledgeredGrantWrite /
        // computeLegacyUnledgeredDelta). `legacy_unledgered_balance` matches no group's `grantReasons`
        // in Resources/ProgressionCatalog.v1.json, so XpGainToastSourceMapper.matchGroup falls through
        // to the catch-all "other" group and it renders as exactly ONE line carrying the whole
        // pre-ledger balance — the owner-reported artefact. It is written AFTER the grants listener
        // binds, so the server-snapshot watermark structurally cannot stop it; this exclusion is
        // independently necessary. XP totals are untouched: XpDisplayedTotalResolver still counts the
        // grant in `verifiedTotalXp`; only the notification stops.
        if grant.reason == UserXpGrantReason.legacyUnledgeredBalance.rawValue { return false }
        return true
    }

    /// Identity of a single completion award, shared by the local ledger row and the server grant that
    /// later mirrors it. `XpReasonCode` raw values match `UserXpGrantReason`, and both sides carry the
    /// originating activity event id (`sourceEventId` locally, `sourceId` on the grant).
    ///
    /// Completion awards are matched per award rather than blanket-suppressed by reason (the rule used for
    /// discovery/return-streak) so a multiplayer peer, whose device never wrote the local row, still toasts
    /// when the grant arrives.
    static func localAwardKey(for row: XpLedgerEvent) -> String? {
        guard row.grantKind == .tripCompletion, !row.sourceEventId.isEmpty else { return nil }
        return "\(row.sourceEventId)|\(row.reasonCode.rawValue)"
    }

    static func localAwardKey(for grant: UserXpGrant) -> String {
        "\(grant.sourceId)|\(grant.reason)"
    }

    // MARK: - §3.1.1 item 14 — the server award scope a local row mirrors

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
    /// KNOWN RESIDUAL (owner, 2026-09-18 — filed as a server item, deliberately not handled here):
    /// on the `srvrej_` path the server bills `first_find_of_day` under the UTC day of the rejection,
    /// because the server-authored rejection payload never copies `xpDayKey`. That one scope string
    /// can therefore differ from the local one, and that find's first-of-day bonus still doubles.
    static func mirroredServerScopeKey(for row: XpLedgerEvent) -> String? {
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
