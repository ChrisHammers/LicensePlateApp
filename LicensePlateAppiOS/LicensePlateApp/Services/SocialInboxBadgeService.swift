//
//  SocialInboxBadgeService.swift
//  LicensePlateApp
//
//  App-scoped pending friend/family invite + captain approval counts for Settings rows and home avatar.
//

import Foundation
import Combine

@MainActor
final class SocialInboxBadgeService: ObservableObject {
    static let shared = SocialInboxBadgeService()

    @Published private(set) var pendingFriendRequestsCount = 0
    @Published private(set) var pendingFamilyInvitesCount = 0
    @Published private(set) var pendingFamilyApprovalsCount = 0
    @Published private(set) var totalPendingInviteCount = 0

    /// Family Settings row: incoming family invites + join approvals the user must act on.
    var pendingFamilyInboxCount: Int { pendingFamilyInvitesCount + pendingFamilyApprovalsCount }

    private var cancellables = Set<AnyCancellable>()
    private var boundUserId: String?
    private var boundActiveFamilyId: String?

    private init() {}

    /// Bind to the current user / active family and observe invite + family pending publishers.
    /// Call whenever invite listening starts (or user / family identity changes).
    func bind(userId: String?, activeFamilyId: String? = nil) {
        let identityUnchanged = userId == boundUserId && activeFamilyId == boundActiveFamilyId
        if identityUnchanged, !cancellables.isEmpty {
            // Identity same, but family listen may have been torn down elsewhere — keep approvals live.
            if let activeFamilyId {
                FamilyRepository.shared.startListening(familyId: activeFamilyId)
            }
            return
        }

        cancellables.removeAll()
        boundUserId = userId
        boundActiveFamilyId = activeFamilyId

        guard let userId else {
            FamilyRepository.shared.stopListening()
            resetCounts()
            return
        }

        if let activeFamilyId {
            FamilyRepository.shared.startListening(familyId: activeFamilyId)
        } else {
            // No active family → no join-approval inbox; drop any prior family listeners.
            FamilyRepository.shared.stopListening()
        }

        let invitesPublisher = InviteRepository.shared.$invites
        let pendingPublisher = FamilyRepository.shared.$pendingRequests
        let membersPublisher = FamilyRepository.shared.$familyMembers

        Publishers.CombineLatest3(invitesPublisher, pendingPublisher, membersPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] invites, pendingRequests, members in
                self?.apply(
                    invites: invites,
                    pendingRequests: pendingRequests,
                    members: members,
                    userId: userId,
                    activeFamilyId: activeFamilyId
                )
            }
            .store(in: &cancellables)
    }

    func stopObserving() {
        bind(userId: nil, activeFamilyId: nil)
    }

    private func resetCounts() {
        pendingFriendRequestsCount = 0
        pendingFamilyInvitesCount = 0
        pendingFamilyApprovalsCount = 0
        totalPendingInviteCount = 0
    }

    private func apply(
        invites: [Invite],
        pendingRequests: [String: [PendingJoinRequest]],
        members: [String: [FamilyMember]],
        userId: String,
        activeFamilyId: String?
    ) {
        let counts = SocialInboxBadgeCounts.counts(
            from: invites,
            userId: userId,
            pendingRequestsByFamily: pendingRequests,
            membersByFamily: members,
            activeFamilyId: activeFamilyId
        )
        pendingFriendRequestsCount = counts.friend
        pendingFamilyInvitesCount = counts.family
        pendingFamilyApprovalsCount = counts.familyApprovals
        totalPendingInviteCount = counts.total
    }
}
