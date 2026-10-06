//
//  XpFeedProjectionBuilder.swift
//  LicensePlateApp
//
//  Feed/snackbar lines from ledger rows, plus the session's completion grants no row lists.
//

import Foundation

enum XpFeedProjectionBuilder {

    /// The outcome-independent completion bonuses. The device that records the `game_completed` /
    /// `game_ended` / `trip_ended` mints a local row for them; a peer's sync import mints none.
    private static let locallyMintedCompletionReasons: Set<XpReasonCode> = [
        .gameEnded, .gameFullClear, .tripEnded,
    ]

    /// Maps ledger rows to feed lines sorted by `createdAt`.
    ///
    /// `serverGrants` adds this session's completion grants that no listed row already claims:
    ///   * the server-decided awards (`XpReasonCode.serverDecidedCompletion`: placement, trip victory,
    ///     participation) — no local row ever carries them, so their grant is their one line, Final
    ///     once it exists and absent before (OD-17: withheld until decided, never shown and then
    ///     removed);
    ///   * the fixed bonuses (game ended, full clear, trip ended) on a device that did not record the
    ///     completion event — a peer, whose sync import writes no row. On the recording device the
    ///     local row lists the award and claims the grant on the same two-way join the XP toast uses
    ///     (`XpGainToastEligibility.localAwardKey`, or the server scope the row mirrors), so it is
    ///     never listed twice.
    /// Every other grant (finds, achievements, streaks) is left out: the recap lists those from ledger
    /// rows only.
    static func lines(
        from ledgerEvents: [XpLedgerEvent],
        serverGrants: [UserXpGrant] = [],
        sessionId: UUID? = nil,
        itemTitle: (String) -> String
    ) -> [XpFeedProjection] {
        var lines = ledgerEvents.compactMap { row in
            line(from: row, itemTitle: itemTitle)
        }
        if let sessionId {
            // Only rows that render claim a grant: a voided row has no line, so its grant stands.
            let listedRows = ledgerEvents.filter { $0.status != .voided }
            let claimedAwardKeys = Set(listedRows.compactMap { XpGainToastEligibility.localAwardKey(for: $0) })
            let claimedScopes = Set(listedRows.compactMap { XpServerScopeKey.mirrored(for: $0) })
            lines += serverGrants.compactMap { grant in
                guard !claimedAwardKeys.contains(XpGainToastEligibility.localAwardKey(for: grant)),
                      !claimedScopes.contains(grant.idempotencyKey)
                else { return nil }
                return line(from: grant, sessionId: sessionId)
            }
        }
        return lines.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }

    /// A completion grant for `sessionId`, or `nil` for any other grant. The grant's `sessionId` is
    /// the `trip_sessions/{id}` document id, compared as a UUID so casing cannot matter.
    private static func line(from grant: UserXpGrant, sessionId: UUID) -> XpFeedProjection? {
        guard grant.amount > 0,
              let reason = XpReasonCode(rawValue: grant.reason),
              XpReasonCode.serverDecidedCompletion.contains(reason)
                || locallyMintedCompletionReasons.contains(reason),
              let grantSessionId = grant.sessionId.flatMap(UUID.init(uuidString:)),
              grantSessionId == sessionId
        else { return nil }
        return XpFeedProjection(
            id: "grant|\(grant.grantId)",
            sourceEventId: grant.sourceId,
            itemId: reason.rawValue,
            title: completionTitle(for: reason),
            subtitle: nil,
            xpDisplayText: "xp.row.pill.final".localized(grant.amount),
            state: .final,
            createdAt: grant.grantedAt ?? .distantFuture
        )
    }

    private static func line(from row: XpLedgerEvent, itemTitle: (String) -> String) -> XpFeedProjection? {
        guard row.status != .voided else { return nil }

        let name = itemTitle(row.itemId)
        let state: XpFeedLineState = row.status == .provisional ? .provisional : .final
        let (title, subtitle, xpText): (String, String?, String)
        switch row.grantKind {
        case .provisionalDiscoveryXp:
            title = "%@ found".localized(name)
            subtitle = "Pending resolution".localized
            xpText = "+%d XP pending".localized(row.xpDelta)
        case .reconciliationAdjustment:
            // Settlement only ever adjusts upward (OD-17: a shown number never goes down).
            title = "%@ resolved".localized(name)
            subtitle = row.reasonCode.rawValue.replacingOccurrences(of: "_", with: " ")
            xpText = "+%d XP".localized(row.xpDelta)
        case .finalDiscoveryAward:
            title = "%@ found".localized(name)
            subtitle = nil
            xpText = "+%d XP".localized(row.xpDelta)
        case .tripCompletion:
            // Completion bonuses are scoped to the trip/game, not a region — title by reason,
            // reusing the XP toast group copy so offline recap lines read the same as online ones.
            title = completionTitle(for: row.reasonCode)
            subtitle = nil
            xpText = row.status == .provisional
                ? "+%d XP pending".localized(row.xpDelta)
                : "+%d XP".localized(row.xpDelta)
        default:
            title = name
            subtitle = row.grantKind.rawValue
            xpText = "%d XP".localized(row.xpDelta)
        }
        return XpFeedProjection(
            id: row.id,
            sourceEventId: row.sourceEventId,
            itemId: row.itemId,
            title: title,
            subtitle: subtitle,
            xpDisplayText: xpText,
            state: state,
            createdAt: row.createdAt
        )
    }

    /// Existing localized XP toast group titles (en / es-419 / fr-CA already shipped). The placement,
    /// trip-victory and participation titles are reached from server grants only (§3.1.1 item 25);
    /// the fixed-bonus titles from local rows, or from a grant no local row claims.
    private static func completionTitle(for reason: XpReasonCode) -> String {
        switch reason {
        case .gameEnded: return "xp.toast.group.game_ended.single".localized
        case .gameFullClear: return "xp.toast.group.game_full_clear.single".localized
        case .tripEnded: return "xp.toast.group.trip_ended.single".localized
        case .tripParticipation: return "xp.toast.group.trip_participation.single".localized
        case .tripCompetitiveFirstPlace: return "xp.toast.group.trip_competitive_first.single".localized
        case .competitiveFirstPlaceFinish, .competitiveSecondPlace, .competitiveThirdPlace:
            return "xp.toast.group.competitive_place.single".localized
        default: return "xp.toast.group.other.single".localized
        }
    }
}
