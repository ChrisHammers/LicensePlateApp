//
//  SocialIdentityHydrationTests.swift
//  LicensePlateAppTests
//
//  Identity displayName + family member/pending user linking for social rows.
//

import Foundation
import FirebaseFirestore
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct SocialIdentityHydrationTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
    }

    // F-6 rework: real names are never collected — displayName is always the username,
    // even when a legacy row still carries stored name values (frozen schema).
    @Test func cachedIdentityMapUsesUsernameAsDisplayName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let user = AppUser(
            id: "uid-1",
            userName: "scoutotter",
            firstName: "Alex",
            lastName: "Scout",
            firebaseUID: "uid-1"
        )
        user.avatarId = "scout_otter"
        context.insert(user)
        try context.save()

        let repository = UserRepository.shared
        repository.setModelContext(context)

        let map = repository.cachedIdentityMap(forUserIds: ["uid-1"])
        #expect(map["uid-1"]?.displayName == "scoutotter")
        #expect(map["uid-1"]?.avatarId == "scout_otter")
        #expect(map["uid-1"]?.displayName != "Alex Scout")
    }

    @Test func getMembersAndPendingExposeLinkedUsers() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let familyId = "family-hydration-1"
        let memberUserId = "member-1"
        let pendingUserId = "pending-1"

        let memberUser = AppUser(
            id: memberUserId,
            userName: "captain_jane",
            firstName: "Jane",
            lastName: "Captain",
            firebaseUID: memberUserId
        )
        memberUser.avatarId = "navigator_raccoon"
        context.insert(memberUser)

        let pendingUser = AppUser(
            id: pendingUserId,
            userName: "pending_pat",
            firstName: "Pat",
            lastName: "Pending",
            firebaseUID: pendingUserId
        )
        pendingUser.avatarId = "scout_otter"
        context.insert(pendingUser)

        let member = FamilyMember(familyId: familyId, userId: memberUserId, role: .captain)
        member.user = memberUser
        context.insert(member)

        let pending = PendingJoinRequest(
            requestId: "req-1",
            familyId: familyId,
            userId: pendingUserId,
            requestedBy: pendingUserId,
            method: .code,
            status: .pending,
            user: pendingUser
        )
        context.insert(pending)
        try context.save()

        let familyRepository = FamilyRepository.shared
        familyRepository.setModelContext(context)

        let members = familyRepository.getMembers(familyId: familyId)
        #expect(members.count == 1)
        #expect(members.first?.user?.displayName == "captain_jane")
        #expect(members.first?.user?.avatarId == "navigator_raccoon")

        let pendingRequests = familyRepository.getPendingRequests(familyId: familyId)
        #expect(pendingRequests.count == 1)
        #expect(pendingRequests.first?.user?.displayName == "pending_pat")
        #expect(pendingRequests.first?.user?.avatarId == "scout_otter")
    }

    @Test func linkUserToMembersAttachesCachedUserToPendingRequest() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let familyId = "family-link-pending"
        let pendingUserId = "pending-link-1"

        let cachedUser = AppUser(
            id: pendingUserId,
            userName: "link_pat",
            firstName: "Link",
            lastName: "Pat",
            firebaseUID: pendingUserId
        )
        cachedUser.avatarId = "scout_otter"
        context.insert(cachedUser)

        let pending = PendingJoinRequest(
            requestId: "req-link-1",
            familyId: familyId,
            userId: pendingUserId,
            requestedBy: "captain-1",
            method: .search,
            status: .pending,
            user: nil
        )
        context.insert(pending)
        try context.save()

        let familyRepository = FamilyRepository.shared
        familyRepository.setModelContext(context)
        UserRepository.shared.setModelContext(context)

        #expect(familyRepository.getPendingRequests(familyId: familyId).first?.user == nil)

        // Simulate post-getUser link (cache hit path used by fetchAndCacheUsers).
        let fetched = try await UserRepository.shared.getUser(userId: pendingUserId)
        #expect(fetched?.displayName == "link_pat")
        familyRepository.linkUserToMembers(userId: pendingUserId, familyId: familyId)

        let linked = familyRepository.getPendingRequests(familyId: familyId)
        #expect(linked.count == 1)
        #expect(linked.first?.user?.displayName == "link_pat")
        #expect(linked.first?.user?.avatarId == "scout_otter")
    }

    // MARK: - FR-86 identity stamp (device pass 2026-08-17)
    //
    // The reported defect, precisely: the captain reinstalled with a request still pending.
    // Cold store, so `request.user` is nil and stays nil (FR-12 denies a peer read of a
    // non-member child's user doc), and the FR-86 stamp was the only identity left — but it
    // lived on the model as a `@Transient`, and the rows the list renders do not come from
    // the decode. They come from `getPendingRequests`, a fresh `FetchDescriptor` fetch, where
    // a transient is nil by definition. So the captain saw "Pending User" + a placeholder.
    //
    // The stamp is now a projection the repository parses at decode and publishes beside the
    // rows, keyed by requestId — the arrangement `childMemberFlags` already uses for the same
    // frozen-schema reason.

    private func pendingDocumentData(
        userId: String,
        userName: Any? = nil,
        avatarId: Any? = nil
    ) -> [String: Any] {
        var data: [String: Any] = [
            "userId": userId,
            "requestedBy": userId,
            "method": "code",
            "status": "pending",
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_760_000_000))
        ]
        if let userName { data["userName"] = userName }
        if let avatarId { data["avatarId"] = avatarId }
        return data
    }

    /// Cold store + fresh decode ⇒ the stamp reaches the render path. This walks the exact
    /// sequence `FamilyRepository.fetchPendingRequests` performs on a reinstall: decode the
    /// Firestore doc, parse the stamp, insert into an EMPTY store, save, then read the rows
    /// back the way the UI does.
    @Test func aStampSurvivesTheColdStoreDecodeThatAReinstallProduces() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let familyId = "family-stamp-reinstall"
        let requestId = "req-stamp-1"
        let childUserId = "child-stamp-1"

        let data = pendingDocumentData(
            userId: childUserId,
            userName: "pending_pat",
            avatarId: "scout_otter"
        )

        // 1. Decode, exactly as the repository does.
        let decoded = try #require(
            PendingJoinRequest(from: data, id: requestId, familyId: familyId)
        )
        let stamps = FamilyRepository.parsePendingIdentityStamps(
            documents: [(requestId: requestId, data: data)]
        )

        // 2. Cold store: nothing cached, so this is the insert branch.
        context.insert(decoded)
        try context.save()

        let familyRepository = FamilyRepository.shared
        familyRepository.setModelContext(context)
        familyRepository.applyPendingIdentityStamps(stamps, familyId: familyId)

        // 3. Read back the way the list does — a store fetch, not the decoded array.
        let rows = familyRepository.getPendingRequests(familyId: familyId)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        // No cached AppUser to resolve: this is precisely when the stamp has to carry the row.
        #expect(row.user == nil)

        let stamp = try #require(
            familyRepository.pendingIdentityStamp(familyId: familyId, requestId: row.requestId)
        )
        #expect(stamp.userName == "pending_pat")
        #expect(stamp.avatarId == "scout_otter")
    }

    /// The graceful fallback the owner asked to keep: an unstamped row resolves to `nil`, so
    /// the views' "Pending User" + placeholder path is still what renders.
    @Test func anUnstampedRowStillFallsBackToThePlaceholder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let familyId = "family-stamp-absent"
        let requestId = "req-stamp-2"

        let data = pendingDocumentData(userId: "child-stamp-2")
        let decoded = try #require(
            PendingJoinRequest(from: data, id: requestId, familyId: familyId)
        )
        context.insert(decoded)
        try context.save()

        let familyRepository = FamilyRepository.shared
        familyRepository.setModelContext(context)
        familyRepository.applyPendingIdentityStamps(
            FamilyRepository.parsePendingIdentityStamps(
                documents: [(requestId: requestId, data: data)]
            ),
            familyId: familyId
        )

        #expect(familyRepository.getPendingRequests(familyId: familyId).count == 1)
        #expect(
            familyRepository.pendingIdentityStamp(familyId: familyId, requestId: requestId) == nil
        )
    }

    /// Blank and non-string stamps are absent, not empty labels — a row must never render a
    /// nameless name. Partial stamps are kept: a name with no avatar is still worth showing.
    @Test func blankAndMalformedStampsAreTreatedAsAbsent() {
        #expect(PendingIdentityStamp(firestoreData: ["userName": "   ", "avatarId": ""]) == nil)
        #expect(PendingIdentityStamp(firestoreData: ["userName": 42, "avatarId": true]) == nil)
        #expect(PendingIdentityStamp(firestoreData: [:]) == nil)

        let nameOnly = PendingIdentityStamp(firestoreData: ["userName": "  pending_pat  "])
        #expect(nameOnly?.userName == "pending_pat")
        #expect(nameOnly?.avatarId == nil)
    }

    /// Two pending children are distinguishable, which is the whole point of FR-86 — the
    /// projection is keyed per request, so one unstamped row cannot blank out another.
    @Test func stampsAreKeyedPerRequestSoPendingChildrenStayDistinguishable() {
        let stamps = FamilyRepository.parsePendingIdentityStamps(documents: [
            (
                requestId: "req-a",
                data: ["userName": "pending_pat", "avatarId": "scout_otter"]
            ),
            (
                requestId: "req-b",
                data: ["userName": "pending_sam", "avatarId": "navigator_raccoon"]
            ),
            (requestId: "req-c", data: [:])
        ])

        #expect(stamps["req-a"]?.userName == "pending_pat")
        #expect(stamps["req-b"]?.userName == "pending_sam")
        #expect(stamps["req-b"]?.avatarId == "navigator_raccoon")
        #expect(stamps["req-c"] == nil)
        #expect(stamps.count == 2)
    }

    // MARK: - FR-86 extended to OUTGOING invites (device pass 2026-08-26)
    //
    // The captain's "Waiting for response" row renders the INVITEE, whose users/{uid} the
    // captain is forbidden (FR-12) from reading — so the identity travels on the invite doc,
    // server-stamped, and projects through InviteRepository exactly as the pending-row
    // stamps project through FamilyRepository. These tests are the owner's ghost-row repro
    // (child entered a code, never tapped Accept → captain saw "Pending User" + blank
    // avatar forever) encoded, per the 2026-08-26 instruction that repro steps land in tests.

    private func rawInviteDocument(
        familyId: String,
        toUserId: String,
        userName: String? = nil,
        avatarId: String? = nil
    ) -> [String: Any] {
        var data: [String: Any] = [
            "type": "family",
            "fromUserId": "captain-1",
            "toUserId": toUserId,
            "familyId": familyId,
            "status": "pending",
            "method": "code",
            "expiresAt": Timestamp(date: Date().addingTimeInterval(900)),
            "createdAt": Timestamp(date: Date()),
        ]
        if let userName { data["userName"] = userName }
        if let avatarId { data["avatarId"] = avatarId }
        return data
    }

    /// THE GHOST-ROW REGRESSION TEST. A stamped invite read back off a COLD store — the
    /// reinstall/fresh-launch shape, where no cached AppUser exists and the user-doc read is
    /// denied — still projects the invitee's name and avatar.
    @Test func aStampedOutgoingInviteProjectsTheInviteeAcrossAColdStoreFetch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let familyId = "family-invite-stamp-1"
        let inviteId = "invite-stamp-1"

        let data = rawInviteDocument(
            familyId: familyId,
            toUserId: "child-invitee-1",
            userName: "pending_pat",
            avatarId: "scout_otter"
        )

        context.insert(
            Invite(
                inviteId: inviteId,
                type: .family,
                fromUserId: "captain-1",
                toUserId: "child-invitee-1",
                familyId: familyId,
                method: .code,
                expiresAt: Date().addingTimeInterval(900)
            )
        )
        try context.save()

        let inviteRepository = InviteRepository.shared
        inviteRepository.setModelContext(context)
        inviteRepository.applyInviteIdentityStamps(
            InviteRepository.parseInviteIdentityStamps(
                documents: [(inviteId: inviteId, data: data)]
            ),
            familyId: familyId
        )

        // Read back the way the dashboard does — a store fetch, not the decoded array.
        let rows = inviteRepository.getPendingFamilyInvites(familyId: familyId)
        #expect(rows.count == 1)

        let stamp = try #require(
            inviteRepository.inviteIdentityStamp(familyId: familyId, inviteId: inviteId)
        )
        #expect(stamp.userName == "pending_pat")
        #expect(stamp.avatarId == "scout_otter")
    }

    /// An unstamped invite (pre-stamp rows, or a child whose best-effort profile publish
    /// failed) resolves to `nil`, so the row's "Pending User" + placeholder fallback stays
    /// the rendered state — degraded, never wrong.
    @Test func anUnstampedOutgoingInviteFallsBackToThePlaceholder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let familyId = "family-invite-stamp-2"
        let inviteId = "invite-stamp-2"

        context.insert(
            Invite(
                inviteId: inviteId,
                type: .family,
                fromUserId: "captain-1",
                toUserId: "child-invitee-2",
                familyId: familyId,
                method: .code,
                expiresAt: Date().addingTimeInterval(900)
            )
        )
        try context.save()

        let inviteRepository = InviteRepository.shared
        inviteRepository.setModelContext(context)
        inviteRepository.applyInviteIdentityStamps(
            InviteRepository.parseInviteIdentityStamps(
                documents: [(
                    inviteId: inviteId,
                    data: rawInviteDocument(familyId: familyId, toUserId: "child-invitee-2")
                )]
            ),
            familyId: familyId
        )

        #expect(inviteRepository.getPendingFamilyInvites(familyId: familyId).count == 1)
        #expect(inviteRepository.inviteIdentityStamp(familyId: familyId, inviteId: inviteId) == nil)
    }

    /// Stamps are keyed per invite, so two invitees stay distinguishable and one unstamped
    /// invite cannot blank out another — the same guarantee the pending-row projection makes.
    @Test func inviteStampsAreKeyedPerInviteSoInviteesStayDistinguishable() {
        let stamps = InviteRepository.parseInviteIdentityStamps(documents: [
            (
                inviteId: "inv-a",
                data: ["userName": "pending_pat", "avatarId": "scout_otter"]
            ),
            (
                inviteId: "inv-b",
                data: ["userName": "pending_sam", "avatarId": "navigator_raccoon"]
            ),
            (inviteId: "inv-c", data: [:])
        ])

        #expect(stamps["inv-a"]?.userName == "pending_pat")
        #expect(stamps["inv-b"]?.userName == "pending_sam")
        #expect(stamps["inv-b"]?.avatarId == "navigator_raccoon")
        #expect(stamps["inv-c"] == nil)
        #expect(stamps.count == 2)
    }
}
