//
//  XpFeedProjectionBuilderTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct XpFeedProjectionBuilderTests {

    @Test func buildsPendingAndResolvedLines() {
        let sid = UUID()
        let gid = UUID()
        let uid = "u1"
        let key = XpLedgerKeyBuilder.uniquenessKey(
            userId: uid,
            sessionId: sid,
            gameInstanceId: gid,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        ).storageString
        let events: [XpLedgerEvent] = [
            XpLedgerEvent(
                id: "p1",
                userId: uid,
                sessionId: sid,
                gameInstanceId: gid,
                sourceEventId: "src1",
                sourceEventType: "region_found",
                itemId: "TX",
                grantKind: .provisionalDiscoveryXp,
                status: .provisional,
                xpDelta: 10,
                reasonCode: .discoveryClaimPendingResolution,
                xpUniquenessKey: key,
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            XpLedgerEvent(
                id: "a1",
                userId: uid,
                sessionId: sid,
                gameInstanceId: gid,
                sourceEventId: "res1",
                sourceEventType: "discovery_resolution",
                itemId: "TX",
                grantKind: .reconciliationAdjustment,
                status: .final,
                xpDelta: 5,
                reasonCode: .competitiveLateFinder,
                xpUniquenessKey: key,
                createdAt: Date(timeIntervalSince1970: 200)
            ),
        ]
        let lines = XpFeedProjectionBuilder.lines(from: events) { $0 }
        #expect(lines.count == 2)
        #expect(lines[0].state == .provisional)
        #expect(lines[0].xpDisplayText.contains("10"))
        #expect(lines[1].state == .final)
        #expect(lines[1].title.contains("TX"))
        #expect(lines[1].xpDisplayText.contains("+5"))
    }

    // MARK: - §3.1.1 item 25: completion awards no local row lists come from their grants

    private let sessionId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let gameId = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!

    private func grant(
        _ id: String,
        reason: UserXpGrantReason,
        amount: Int = 25,
        sessionId: String?,
        sourceId: String = "game-end-1",
        idempotencyKey: String? = nil,
        at seconds: TimeInterval = 300
    ) -> UserXpGrant {
        UserXpGrant(
            grantId: id,
            amount: amount,
            reason: reason.rawValue,
            sourceType: "activity_event",
            sourceId: sourceId,
            idempotencyKey: idempotencyKey ?? "scope-\(id)",
            sessionId: sessionId,
            grantedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    /// The local game-ended row this device writes for its own game end.
    private func gameEndedRow(at seconds: TimeInterval = 200) -> XpLedgerEvent {
        XpLedgerEvent(
            id: "ge-row",
            userId: "u1",
            sessionId: sessionId,
            gameInstanceId: gameId,
            sourceEventId: "game-end-1",
            sourceEventType: "game_ended",
            itemId: XpReasonCode.gameEnded.rawValue,
            grantKind: .tripCompletion,
            status: .provisional,
            xpDelta: 50,
            reasonCode: .gameEnded,
            xpUniquenessKey: "ge-key",
            createdAt: Date(timeIntervalSince1970: seconds)
        )
    }

    /// The recap shows placement XP only once the server's grant exists: before it, the game's
    /// line is the only completion line; after it, the placement is one Final line, after the
    /// local row in time order.
    @Test func placementLineAppearsOnlyOnceTheGrantExists() {
        let before = XpFeedProjectionBuilder.lines(
            from: [gameEndedRow()],
            serverGrants: [],
            sessionId: sessionId
        ) { $0 }
        #expect(before.map(\.id) == ["ge-row"])

        let placement = grant("g-first", reason: .competitiveFirstPlaceFinish, sessionId: sessionId.uuidString)
        let after = XpFeedProjectionBuilder.lines(
            from: [gameEndedRow()],
            serverGrants: [placement],
            sessionId: sessionId
        ) { $0 }
        #expect(after.map(\.id) == ["ge-row", "grant|g-first"])
        let line = after[1]
        #expect(line.state == .final)
        #expect(line.title == "xp.toast.group.competitive_place.single".localized)
        #expect(line.xpDisplayText == "xp.row.pill.final".localized(25))
        #expect(line.sourceEventId == "game-end-1")
    }

    /// Every server-decided reason gets its line; the session id matches whatever its casing.
    @Test func everyServerDecidedReasonForThisSessionIsListed() {
        let grants = [
            grant("g1", reason: .competitiveFirstPlaceFinish, sessionId: sessionId.uuidString, at: 301),
            grant("g2", reason: .competitiveSecondPlaceFinish, amount: 10, sessionId: sessionId.uuidString, at: 302),
            grant("g3", reason: .competitiveThirdPlaceFinish, amount: 5, sessionId: sessionId.uuidString, at: 303),
            grant("g4", reason: .tripParticipation, amount: 50, sessionId: sessionId.uuidString.lowercased(), at: 304),
            grant("g5", reason: .tripCompetitiveFirstPlace, sessionId: sessionId.uuidString, at: 305),
        ]
        let lines = XpFeedProjectionBuilder.lines(from: [], serverGrants: grants, sessionId: sessionId) { $0 }
        #expect(lines.map(\.id) == ["grant|g1", "grant|g2", "grant|g3", "grant|g4", "grant|g5"])
        #expect(lines[3].title == "xp.toast.group.trip_participation.single".localized)
        #expect(lines[4].title == "xp.toast.group.trip_competitive_first.single".localized)
    }

    /// Only the completion awards of THIS trip that no row lists: another trip's grant, a grant with
    /// no session, a zero grant, a find grant, and the game-ended grant whose award this device's own
    /// row already lists (joined on the award key) are left out — listing that one would show it twice.
    @Test func otherSessionsAndLocallyListedGrantsAreLeftOut() {
        let grants = [
            grant("other-trip", reason: .competitiveFirstPlaceFinish, sessionId: UUID().uuidString),
            grant("no-session", reason: .tripParticipation, sessionId: nil),
            grant("zero", reason: .competitiveThirdPlaceFinish, amount: 0, sessionId: sessionId.uuidString),
            grant("game-ended", reason: .gameEnded, amount: 50, sessionId: sessionId.uuidString),
            grant("base", reason: .regionFoundBaseDiscovery, amount: 10, sessionId: sessionId.uuidString),
        ]
        let lines = XpFeedProjectionBuilder.lines(
            from: [gameEndedRow()],
            serverGrants: grants,
            sessionId: sessionId
        ) { $0 }
        #expect(lines.map(\.id) == ["ge-row"])

        // With no session to scope them to, no grant is listed at all.
        let unscoped = XpFeedProjectionBuilder.lines(
            from: [],
            serverGrants: [grant("g", reason: .tripParticipation, sessionId: sessionId.uuidString)]
        ) { $0 }
        #expect(unscoped.isEmpty)
    }

    /// The recording device's row also claims a fixed-bonus grant the server paid off ANOTHER event
    /// for the same award (both devices ended the game; the other one's event landed first) — joined
    /// on the server scope the row mirrors, as the XP toast does.
    @Test func aLocalRowClaimsItsAwardsGrantFromAnotherEventByServerScope() {
        let paidElsewhere = grant(
            "game-ended-other-event",
            reason: .gameEnded,
            amount: 50,
            sessionId: sessionId.uuidString,
            sourceId: "game-end-other-device",
            idempotencyKey: "game_ended|v1|u1|\(gameId.uuidString)"
        )
        let lines = XpFeedProjectionBuilder.lines(
            from: [gameEndedRow()],
            serverGrants: [paidElsewhere],
            sessionId: sessionId
        ) { $0 }
        #expect(lines.map(\.id) == ["ge-row"])
    }

    /// A peer's sync import writes no completion row, so on its device the game-ended, full-clear and
    /// trip-ended grants are the recap's only lines for those bonuses — listed next to the
    /// server-decided participation it was paid in the same trip end.
    @Test func aPeerWithNoCompletionRowsListsTheFixedBonusesFromTheirGrants() {
        let grants = [
            grant("game-ended", reason: .gameEnded, amount: 50, sessionId: sessionId.uuidString, at: 301),
            grant("full-clear", reason: .gameFullClear, amount: 200, sessionId: sessionId.uuidString, at: 302),
            grant("trip-ended", reason: .tripEnded, amount: 100, sessionId: sessionId.uuidString, sourceId: "trip-end-1", at: 303),
            grant("participation", reason: .tripParticipation, amount: 50, sessionId: sessionId.uuidString, sourceId: "trip-end-1", at: 304),
        ]
        let lines = XpFeedProjectionBuilder.lines(from: [], serverGrants: grants, sessionId: sessionId) { $0 }
        #expect(lines.map(\.id) == ["grant|game-ended", "grant|full-clear", "grant|trip-ended", "grant|participation"])
        #expect(lines.allSatisfy { $0.state == .final })
        #expect(lines[0].title == "xp.toast.group.game_ended.single".localized)
        #expect(lines[1].title == "xp.toast.group.game_full_clear.single".localized)
        #expect(lines[2].title == "xp.toast.group.trip_ended.single".localized)
        #expect(lines[2].xpDisplayText == "xp.row.pill.final".localized(100))
    }
}
