//
//  InvitePlayersViewModel.swift
//  LicensePlateApp
//
//  Step 11.5 — Select invite targets from friends/family only; optional setup mode.
//

import Foundation
import Combine

struct InviteCandidate: Identifiable, Equatable {
    let userId: String
    let displayName: String
    let sourceLabel: String
    let isAlreadyParticipant: Bool
    let hasPendingInvite: Bool

    var id: String { userId }

    var isSelectable: Bool {
        !isAlreadyParticipant && !hasPendingInvite
    }
}

enum InvitePlayersMode {
    case setupSelection
    case sendInvites
}

@MainActor
final class InvitePlayersViewModel: ObservableObject {
    @Published private(set) var candidates: [InviteCandidate] = []
    @Published var selectedUserIds: Set<String>
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?

    let mode: InvitePlayersMode
    private let tripSessionId: UUID
    private let tripName: String
    private let authService: FirebaseAuthService
    private let tripInviteRepository: TripInviteRepositoryProtocol
    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let friendshipRepository: FriendshipRepository
    private let familyRepository: FamilyRepository
    private let displayNamesProvider: (Set<String>) async -> [String: String]

    init(
        mode: InvitePlayersMode,
        tripSessionId: UUID,
        tripName: String,
        selectedUserIds: Set<String> = [],
        authService: FirebaseAuthService,
        tripInviteRepository: TripInviteRepositoryProtocol = TripInviteRepository.shared,
        tripSessionRepository: TripSessionRepositoryProtocol = TripSessionRepository.shared,
        friendshipRepository: FriendshipRepository = .shared,
        familyRepository: FamilyRepository = .shared,
        userRepository: UserRepository = .shared,
        displayNamesProvider: ((Set<String>) async -> [String: String])? = nil
    ) {
        self.mode = mode
        self.tripSessionId = tripSessionId
        self.tripName = tripName
        self.selectedUserIds = selectedUserIds
        self.authService = authService
        self.tripInviteRepository = tripInviteRepository
        self.tripSessionRepository = tripSessionRepository
        self.friendshipRepository = friendshipRepository
        self.familyRepository = familyRepository
        self.displayNamesProvider = displayNamesProvider ?? { ids in
            await userRepository.displayNames(forUserIds: ids)
        }
    }

    var selectedCount: Int {
        selectedUserIds.count
    }

    func loadCandidates() async {
        guard let currentUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let accepted = friendshipRepository.getAcceptedFriendships(for: currentUserId)
        let friendIds = Set(accepted.map { $0.userA == currentUserId ? $0.userB : $0.userA })

        var familyIds: Set<String> = []
        if let familyId = authService.currentUser?.activeFamilyId {
            let members = familyRepository.getMembers(familyId: familyId)
            familyIds = Set(members.map(\.userId))
        }

        var ids = friendIds.union(familyIds)
        ids.remove(currentUserId)

        let displayNames = await displayNamesProvider(ids)

        let participantIds: Set<String> = {
            guard let session = try? tripSessionRepository.session(byId: tripSessionId) else { return [] }
            return Set(session.participants.map(\.userId))
        }()

        let inviteRows = (try? tripInviteRepository.getInvites(forTripSessionId: tripSessionId.uuidString)) ?? []
        let pendingInviteIds = Set(
            inviteRows
                .filter { $0.statusEnum == .pending || $0.statusEnum == .sent }
                .compactMap(\.toUserId)
        )

        var rows: [InviteCandidate] = []
        rows.reserveCapacity(ids.count)
        for id in ids {
            let source = familyIds.contains(id) ? (friendIds.contains(id) ? "Friend & Family".localized : "Family".localized) : "Friend".localized
            rows.append(
                InviteCandidate(
                    userId: id,
                    displayName: displayNames[id] ?? id,
                    sourceLabel: source,
                    isAlreadyParticipant: participantIds.contains(id),
                    hasPendingInvite: pendingInviteIds.contains(id)
                )
            )
        }
        candidates = rows.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        selectedUserIds = selectedUserIds.intersection(Set(candidates.filter(\.isSelectable).map(\.userId)))
    }

    func toggleSelection(userId: String) {
        guard let candidate = candidates.first(where: { $0.userId == userId }), candidate.isSelectable else { return }
        if selectedUserIds.contains(userId) {
            selectedUserIds.remove(userId)
        } else {
            selectedUserIds.insert(userId)
        }
    }

    func sendSelectedInvites() async -> Bool {
        guard mode == .sendInvites else { return true }
        guard let fromUserId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else { return false }
        guard !selectedUserIds.isEmpty else { return true }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            for userId in selectedUserIds {
                _ = try await tripInviteRepository.sendTripInvite(
                    tripSessionId: tripSessionId.uuidString,
                    tripName: tripName,
                    fromUserId: fromUserId,
                    toUserId: userId,
                    expiresAt: nil
                )
            }
            AnalyticsService.shared.log(.tripInviteSent(
                tripSessionId: tripSessionId.uuidString,
                tripNameLength: tripName.count
            ))
            return true
        } catch {
            errorMessage = error.localizedDescription
            AnalyticsService.shared.log(.tripInviteSendFailed(
                tripSessionId: tripSessionId.uuidString,
                error: error.localizedDescription
            ))
            return false
        }
    }
}
