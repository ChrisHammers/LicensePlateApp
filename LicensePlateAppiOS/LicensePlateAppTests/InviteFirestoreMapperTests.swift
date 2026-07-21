//
//  InviteFirestoreMapperTests.swift
//  LicensePlateAppTests
//
//  Family invite — Firestore document → Invite mapping (familyName only).
//

import FirebaseFirestore
import Foundation
import Testing
@testable import LicensePlateApp

struct InviteFirestoreMapperTests {

    private var baseData: [String: Any] {
        [
            "type": "family",
            "fromUserId": "user-from",
            "toUserId": "user-to",
            "familyId": "fam-1",
            "status": "pending",
            "method": "search",
            "expiresAt": Timestamp(date: Date().addingTimeInterval(900)),
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_700_000_000)),
        ]
    }

    @Test func mapsWithoutFamilyName() {
        let invite = Invite(from: baseData, id: "inv-1")
        #expect(invite != nil)
        #expect(invite?.inviteId == "inv-1")
        #expect(invite?.typeEnum == .family)
        #expect(invite?.familyId == "fam-1")
        #expect(invite?.fromUserId == "user-from")
        #expect(invite?.familyName == nil)
    }

    @Test func mapsFamilyName() {
        var data = baseData
        data["familyName"] = "Roadtrippers"
        // Legacy fat fields must be ignored
        data["creatorDisplayName"] = "Ada"
        data["captainsPreviewJSON"] = "[]"

        let invite = Invite(from: data, id: "inv-2")
        #expect(invite?.familyName == "Roadtrippers")
        #expect(invite?.fromUserId == "user-from")
    }

    @Test func toFirestoreDataIncludesFamilyNameWhenPresent() {
        let invite = Invite(
            inviteId: "inv-3",
            type: .family,
            fromUserId: "from",
            toUserId: "to",
            familyId: "fam",
            method: .search,
            expiresAt: Date().addingTimeInterval(900),
            familyName: "Hammers Clan"
        )
        let data = invite.toFirestoreData()
        #expect(data["familyName"] as? String == "Hammers Clan")
        #expect(data["fromUserId"] as? String == "from")
        #expect(data["creatorDisplayName"] == nil)
        #expect(data["captainsPreviewJSON"] == nil)
    }
}
