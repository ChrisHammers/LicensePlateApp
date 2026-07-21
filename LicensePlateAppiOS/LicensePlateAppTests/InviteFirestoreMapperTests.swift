//
//  InviteFirestoreMapperTests.swift
//  LicensePlateAppTests
//
//  Family invite display snapshot — Firestore document → Invite mapping.
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

    @Test func mapsWithoutDisplaySnapshot() {
        let invite = Invite(from: baseData, id: "inv-1")
        #expect(invite != nil)
        #expect(invite?.inviteId == "inv-1")
        #expect(invite?.typeEnum == .family)
        #expect(invite?.familyId == "fam-1")
        #expect(invite?.familyName == nil)
        #expect(invite?.creatorDisplayName == nil)
        #expect(invite?.fromUserDisplayName == nil)
        #expect(invite?.captainsPreview.isEmpty == true)
    }

    @Test func mapsFullDisplaySnapshot() {
        let captainsJSON = """
        [{"displayName":"Ada Creator","userName":"ada","role":"creator","avatarId":"scout_otter","userId":"u1"},{"displayName":"Bob Captain","userName":"bob","role":"captain","avatarId":null,"userId":"u2"}]
        """
        var data = baseData
        data["familyName"] = "Roadtrippers"
        data["creatorDisplayName"] = "Ada Creator"
        data["creatorUserName"] = "ada"
        data["fromUserDisplayName"] = "Bob Captain"
        data["fromUserUserName"] = "bob"
        data["captainsPreviewJSON"] = captainsJSON

        let invite = Invite(from: data, id: "inv-2")
        #expect(invite != nil)
        #expect(invite?.familyName == "Roadtrippers")
        #expect(invite?.creatorDisplayName == "Ada Creator")
        #expect(invite?.creatorUserName == "ada")
        #expect(invite?.fromUserDisplayName == "Bob Captain")
        #expect(invite?.fromUserUserName == "bob")
        #expect(invite?.captainsPreview.count == 2)
        #expect(invite?.captainsPreview.first?.isCreator == true)
        #expect(invite?.captainsPreview.first?.avatarId == "scout_otter")
        #expect(invite?.captainsPreview.last?.role == "captain")
        #expect(invite?.captainsPreview.last?.userId == "u2")
    }

    @Test func toFirestoreDataIncludesSnapshotWhenPresent() {
        let captains = [
            FamilyInviteCaptainPreview(displayName: "Ada", userName: "ada", role: "creator", avatarId: "scout_otter", userId: "u1")
        ]
        let invite = Invite(
            inviteId: "inv-3",
            type: .family,
            fromUserId: "from",
            toUserId: "to",
            familyId: "fam",
            method: .search,
            expiresAt: Date().addingTimeInterval(900),
            familyName: "Hammers Clan",
            creatorDisplayName: "Ada",
            creatorUserName: "ada",
            fromUserDisplayName: "Ada",
            fromUserUserName: "ada",
            captainsPreviewJSON: Invite.encodeCaptainsPreview(captains)
        )
        let data = invite.toFirestoreData()
        #expect(data["familyName"] as? String == "Hammers Clan")
        #expect(data["creatorDisplayName"] as? String == "Ada")
        #expect(data["fromUserDisplayName"] as? String == "Ada")
        #expect(data["captainsPreviewJSON"] as? String != nil)
    }

    @Test func decodeCaptainsPreviewHelper() {
        let json = #"[{"displayName":"C","userName":"c","role":"creator"}]"#
        let decoded = Invite.decodeCaptainsPreview(from: json)
        #expect(decoded.count == 1)
        #expect(decoded[0].displayName == "C")
        #expect(decoded[0].isCreator)

        #expect(Invite.decodeCaptainsPreview(from: nil).isEmpty)
        #expect(Invite.decodeCaptainsPreview(from: "not-json").isEmpty)
    }
}
