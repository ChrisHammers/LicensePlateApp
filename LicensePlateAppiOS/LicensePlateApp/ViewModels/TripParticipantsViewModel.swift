//
//  TripParticipantsViewModel.swift
//  LicensePlateApp
//
//  Step 11.5 — Passenger list projection for a trip.
//

import Combine
import Foundation

struct PassengerDisplayRow: Identifiable, Equatable {
    let userId: String
    let displayName: String
    let roleLabel: String
    let isCreator: Bool

    var id: String { userId }
}

struct PendingTripInviteDisplayRow: Identifiable, Equatable {
    let inviteId: String
    let inviteeDisplayName: String
    let statusLabel: String

    var id: String { inviteId }
}

@MainActor
final class TripParticipantsViewModel: ObservableObject {
    @Published private(set) var passengers: [PassengerDisplayRow] = []
    @Published private(set) var pendingInviteRows: [PendingTripInviteDisplayRow] = []
    @Published private(set) var tripName: String = ""
    @Published var errorMessage: String?

    let sessionId: UUID

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let tripInviteRepository: TripInviteRepositoryProtocol
    private let displayNamesProvider: (Set<String>) async -> [String: String]
    private var cancellables = Set<AnyCancellable>()

    init(
        sessionId: UUID,
        tripSessionRepository: TripSessionRepositoryProtocol = TripSessionRepository.shared,
        tripInviteRepository: TripInviteRepositoryProtocol = TripInviteRepository.shared,
        userRepository: UserRepository = .shared,
        displayNamesProvider: ((Set<String>) async -> [String: String])? = nil
    ) {
        self.sessionId = sessionId
        self.tripSessionRepository = tripSessionRepository
        self.tripInviteRepository = tripInviteRepository
        self.displayNamesProvider = displayNamesProvider ?? { ids in
            await userRepository.displayNames(forUserIds: ids)
        }

        tripInviteRepository.inviteSnapshotSignal
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Task { @MainActor in
                    await self?.reload()
                }
            }
            .store(in: &cancellables)
    }

    func onAppear() {
        AnalyticsService.shared.log(.tripParticipantsViewed(tripSessionId: sessionId.uuidString))
        Task { await reload() }
    }

    func reload() async {
        errorMessage = nil
        do {
            guard let session = try tripSessionRepository.session(byId: sessionId) else {
                passengers = []
                pendingInviteRows = []
                tripName = ""
                return
            }

            tripName = session.name
            let participantIds = Set(session.participants.map(\.userId))
            let displayNames = await displayNamesProvider(participantIds)
            let unknown = "Unknown user".localized
            passengers = session.participants.map { participant in
                PassengerDisplayRow(
                    userId: participant.userId,
                    displayName: displayNames[participant.userId] ?? unknown,
                    roleLabel: participant.role == .owner ? "Creator".localized : "Passenger".localized,
                    isCreator: participant.role == .owner
                )
            }.sorted { lhs, rhs in
                if lhs.isCreator != rhs.isCreator { return lhs.isCreator }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

            let invites = try tripInviteRepository.getInvites(forTripSessionId: sessionId.uuidString)
            let pending = invites.filter { $0.statusEnum == .pending || $0.statusEnum == .sent }
            let pendingIds = Set(pending.compactMap(\.toUserId))
            let pendingNameMap = await displayNamesProvider(pendingIds)
            let unknownUser = "Unknown user".localized
            pendingInviteRows = pending.map { inv in
                PendingTripInviteDisplayRow(
                    inviteId: inv.inviteId,
                    inviteeDisplayName: inv.toUserId.flatMap { pendingNameMap[$0] } ?? unknownUser,
                    statusLabel: inv.statusEnum.rawValue.capitalized
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
