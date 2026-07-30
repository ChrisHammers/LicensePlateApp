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
    @Published private(set) var isTripCreator: Bool = false
    @Published private(set) var isRemovingPassenger = false
    @Published var errorMessage: String?
    @Published var passengerIdPendingRemoval: String?

    let sessionId: UUID

    private let tripSessionRepository: TripSessionRepositoryProtocol
    private let tripInviteRepository: TripInviteRepositoryProtocol
    private let authService: FirebaseAuthService
    private let remoteSync: TripCanonicalRemoteSyncing
    private let displayNamesProvider: (Set<String>) async -> [String: String]
    private var cancellables = Set<AnyCancellable>()
    private var createdBy: String?

    var canInvitePassengers: Bool { isTripCreator }
    var canRemovePassengers: Bool { isTripCreator }

    init(
        sessionId: UUID,
        tripSessionRepository: TripSessionRepositoryProtocol = TripSessionRepository.shared,
        tripInviteRepository: TripInviteRepositoryProtocol = TripInviteRepository.shared,
        authService: FirebaseAuthService,
        remoteSync: TripCanonicalRemoteSyncing = TripCanonicalRemoteSyncService.shared,
        userRepository: UserRepository = .shared,
        displayNamesProvider: ((Set<String>) async -> [String: String])? = nil
    ) {
        self.sessionId = sessionId
        self.tripSessionRepository = tripSessionRepository
        self.tripInviteRepository = tripInviteRepository
        self.authService = authService
        self.remoteSync = remoteSync
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

    func canRemove(passengerUserId: String) -> Bool {
        guard canRemovePassengers else { return false }
        guard let viewerId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id else {
            return false
        }
        guard passengerUserId != viewerId else { return false }
        guard let row = passengers.first(where: { $0.userId == passengerUserId }) else {
            return false
        }
        return !row.isCreator
    }

    func confirmRemovePassenger(userId: String) {
        guard canRemove(passengerUserId: userId) else { return }
        passengerIdPendingRemoval = userId
    }

    func cancelRemovePassenger() {
        passengerIdPendingRemoval = nil
    }

    func removePendingPassenger() {
        guard let userId = passengerIdPendingRemoval else { return }
        passengerIdPendingRemoval = nil
        Task { await removePassenger(userId: userId) }
    }

    func removePassenger(userId: String) async {
        guard canRemove(passengerUserId: userId) else {
            errorMessage = "Only the Driver can remove passengers.".localized
            return
        }
        guard !isRemovingPassenger else { return }

        isRemovingPassenger = true
        errorMessage = nil
        defer { isRemovingPassenger = false }

        do {
            try await remoteSync.removeParticipantAsOwner(sessionId: sessionId, removedUserId: userId)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        errorMessage = nil
        do {
            guard let session = try tripSessionRepository.session(byId: sessionId) else {
                passengers = []
                pendingInviteRows = []
                tripName = ""
                isTripCreator = false
                createdBy = nil
                return
            }

            tripName = session.name
            createdBy = session.createdBy
            let viewerId = authService.currentUser?.firebaseUID ?? authService.currentUser?.id
            if let viewerId, let createdBy = session.createdBy {
                isTripCreator = createdBy == viewerId
            } else {
                isTripCreator = false
            }

            let participantIds = Set(session.participants.map(\.userId))
            let displayNames = await displayNamesProvider(participantIds)
            let unknown = "Unknown user".localized
            passengers = session.participants.map { participant in
                let isOwner = participant.role == .owner
                    || (session.createdBy != nil && participant.userId == session.createdBy)
                return PassengerDisplayRow(
                    userId: participant.userId,
                    displayName: displayNames[participant.userId] ?? unknown,
                    roleLabel: isOwner ? "Driver".localized : "Passenger".localized,
                    isCreator: isOwner
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
