//
//  ParticipantDisplayNameTests.swift
//  LicensePlateAppTests
//

import Testing
@testable import LicensePlateApp

struct ParticipantDisplayNameTests {

    @Test func decoratesWhenUserIdMatchesCurrentUser() {
        let result = ParticipantDisplayName.decorated(
            "Alex Scout",
            userId: "uid-1",
            currentUserId: "uid-1"
        )
        #expect(result == "%@ [You]".localized("Alex Scout"))
    }

    @Test func leavesNameUnchangedWhenUserIdDiffers() {
        let result = ParticipantDisplayName.decorated(
            "Alex Scout",
            userId: "uid-1",
            currentUserId: "uid-2"
        )
        #expect(result == "Alex Scout")
    }

    @Test func leavesNameUnchangedWhenCurrentUserIdIsNil() {
        let result = ParticipantDisplayName.decorated(
            "Alex Scout",
            userId: "uid-1",
            currentUserId: nil
        )
        #expect(result == "Alex Scout")
    }

    @Test func leavesNameUnchangedWhenCurrentUserIdIsEmpty() {
        let result = ParticipantDisplayName.decorated(
            "Alex Scout",
            userId: "uid-1",
            currentUserId: ""
        )
        #expect(result == "Alex Scout")
    }

    @Test func isCurrentUserFlagDecorates() {
        #expect(
            ParticipantDisplayName.decorated("Morgan", isCurrentUser: true)
                == "%@ [You]".localized("Morgan")
        )
        #expect(ParticipantDisplayName.decorated("Morgan", isCurrentUser: false) == "Morgan")
    }
}
