//
//  TripInviteFirestoreMapperTests.swift
//  LicensePlateAppTests
//
//  Step 08 — Firestore document → TripInvite mapping (no emulator).
//

import FirebaseFirestore
import Foundation
import Testing
@testable import LicensePlateApp

struct TripInviteFirestoreMapperTests {

    @Test func mapsFullDocument() {
        let id = "invite-doc-1"
        let expires = Date().addingTimeInterval(86400)
        let data: [String: Any] = [
            "tripSessionId": "session-uuid",
            "tripName": "Summer Drive",
            "fromUserId": "user-a",
            "toUserId": "user-b",
            "status": "pending",
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000)),
            "expiresAt": Timestamp(date: expires),
        ]
        let invite = TripInviteFirestoreMapper.tripInvite(documentId: id, data: data)
        #expect(invite != nil)
        #expect(invite?.inviteId == id)
        #expect(invite?.tripSessionId == "session-uuid")
        #expect(invite?.tripName == "Summer Drive")
        #expect(invite?.fromUserId == "user-a")
        #expect(invite?.toUserId == "user-b")
        #expect(invite?.statusEnum == .pending)
    }

    @Test func rejectsMissingRequiredFields() {
        let data: [String: Any] = [
            "tripName": "X",
            "fromUserId": "a",
            "toUserId": "b",
        ]
        #expect(TripInviteFirestoreMapper.tripInvite(documentId: "x", data: data) == nil)
    }

    @Test func defaultsStatusAndTimestamps() {
        let data: [String: Any] = [
            "tripSessionId": "s1",
            "tripName": "T",
            "fromUserId": "a",
            "toUserId": "b",
        ]
        let invite = TripInviteFirestoreMapper.tripInvite(documentId: "d1", data: data)
        #expect(invite?.statusEnum == .pending)
        #expect(invite != nil)
    }
}
