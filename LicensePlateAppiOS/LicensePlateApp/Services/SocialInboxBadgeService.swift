//
//  SocialInboxBadgeService.swift
//  LicensePlateApp
//
//  App-scoped pending friend/family invite counts for Settings rows and home avatar.
//

import Foundation
import Combine

@MainActor
final class SocialInboxBadgeService: ObservableObject {
    static let shared = SocialInboxBadgeService()

    @Published private(set) var pendingFriendRequestsCount = 0
    @Published private(set) var pendingFamilyInvitesCount = 0
    @Published private(set) var totalPendingInviteCount = 0

    private var inviteCancellable: AnyCancellable?
    private var boundUserId: String?

    private init() {}

    /// Bind to the current user and observe `InviteRepository.$invites`.
    /// Call whenever invite listening starts (or user identity changes).
    func bind(userId: String?) {
        if userId == boundUserId, inviteCancellable != nil { return }

        inviteCancellable?.cancel()
        inviteCancellable = nil
        boundUserId = userId

        guard let userId else {
            pendingFriendRequestsCount = 0
            pendingFamilyInvitesCount = 0
            totalPendingInviteCount = 0
            return
        }

        inviteCancellable = InviteRepository.shared.$invites
            .receive(on: DispatchQueue.main)
            .sink { [weak self] invites in
                self?.apply(invites: invites, userId: userId)
            }
    }

    func stopObserving() {
        bind(userId: nil)
    }

    private func apply(invites: [Invite], userId: String) {
        let counts = SocialInboxBadgeCounts.counts(from: invites, userId: userId)
        pendingFriendRequestsCount = counts.friend
        pendingFamilyInvitesCount = counts.family
        totalPendingInviteCount = counts.total
    }
}
