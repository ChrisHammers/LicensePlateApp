//
//  GameplayXpSyncSupportTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct GameplayXpSyncSupportTests {

    /// §3.1.1 item 24 (OD-17). Every rejection the callable returns for this device's own find —
    /// invalid participant included — settles as `.acceptedLate`: the find keeps the base award it
    /// already showed, and no settlement of it is worth 0 XP.
    @Test func everyServerRejectionOfThisDevicesFindSettlesAsAcceptedLate() {
        for reason in [
            DiscoveryRejectionReason.serverRejectedLateCompetitive,
            .serverRejectedSupersededByEarlierTimestamp,
            .rejectedInvalidParticipant,
        ] {
            #expect(
                GameplayXpSyncSupport.discoveryOutcome(forServerRejectionReason: reason.rawValue) == .acceptedLate,
                "\(reason.rawValue)"
            )
        }
    }

    /// A reason the server never returns for this device's own `region_found` settles nothing.
    @Test func otherReasonsSettleNothing() {
        #expect(
            GameplayXpSyncSupport.discoveryOutcome(
                forServerRejectionReason: DiscoveryRejectionReason.rejectedDuplicate.rawValue
            ) == nil
        )
        #expect(GameplayXpSyncSupport.discoveryOutcome(forServerRejectionReason: "") == nil)
    }
}
