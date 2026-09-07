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

/// Owner-found 2026-09-07: a deleted co-player's tombstone id ("deleted-user-xyz")
/// reached every other player's roster. A raw participant id must never render.
struct ParticipantUnresolvedLabelTests {
    @Test func tombstoneIdRendersAsFormerPlayer() {
        #expect(
            ParticipantDisplayName.unresolvedLabel(for: "deleted-user-1a2b3c4d")
                == "participant.former_player".localized
        )
    }

    @Test func unknownUidRendersAsNeutralPlayer() {
        #expect(
            ParticipantDisplayName.unresolvedLabel(for: "ndT1CiyxmpgHy1BRPOQjJri0oMO2")
                == "participant.unknown_player".localized
        )
    }

    @Test func resolvedNamePassesThroughAndEmptyFallsBack() {
        #expect(ParticipantDisplayName.resolved("Alex", participantId: "uid-1") == "Alex")
        #expect(
            ParticipantDisplayName.resolved(nil, participantId: "uid-1")
                == "participant.unknown_player".localized
        )
        #expect(
            ParticipantDisplayName.resolved("", participantId: "deleted-user-ff00ff00")
                == "participant.former_player".localized
        )
    }

    @Test func prefixMirrorsServerTombstoneShape() {
        // `deletedUserTombstoneIdFor` mints `deleted-user-<8 hex>`; the prefix must not drift.
        #expect(ParticipantDisplayName.deletedUserTombstonePrefix == "deleted-user")
    }
}
