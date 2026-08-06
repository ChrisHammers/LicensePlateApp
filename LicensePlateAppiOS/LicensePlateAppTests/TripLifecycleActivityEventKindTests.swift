//
//  TripLifecycleActivityEventKindTests.swift
//  LicensePlateAppTests
//

import Testing
@testable import LicensePlateApp

struct TripLifecycleActivityEventKindTests {

    @Test func participantInvitedRawValueMatchesServer() {
        #expect(TripActivityEventKind.participantInvited.rawValue == "participant_invited")
    }

    @Test func gameCompletedRawValueMatchesServer() {
        #expect(TripActivityEventKind.gameCompleted.rawValue == "game_completed")
        #expect(TripActivityEventPayloadKey.xpDayKey == "xpDayKey")
    }

    @Test func leaveReasonPayloadKeyIsStable() {
        #expect(TripActivityEventPayloadKey.leaveReason == "leaveReason")
        #expect(TripActivityEventPayloadKey.initiatedByUserId == "initiatedByUserId")
    }
}
