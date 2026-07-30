//
//  FamilyPendingApprovalsViewModel.swift
//  LicensePlateApp
//

import Foundation
import SwiftData
import Combine

@MainActor
final class FamilyPendingApprovalsViewModel: ObservableObject {
    let familyId: String

    @Published var pendingRequests: [PendingJoinRequest] = []
    @Published var errorMessage: String?
    @Published var showError = false
    @Published private(set) var busyRequestId: String?
    @Published private(set) var busyKind: InviteBusyKind?
    @Published private(set) var processedRequestIds: Set<String> = []

    var isProcessing: Bool { busyRequestId != nil }

    private var authService: FirebaseAuthService?
    private var pendingObservation: AnyCancellable?
    private let familyRepository: FamilyRepository

    init(familyId: String, familyRepository: FamilyRepository = .shared) {
        self.familyId = familyId
        self.familyRepository = familyRepository
    }

    func isBusy(requestId: String, kind: InviteBusyKind) -> Bool {
        busyRequestId == requestId && busyKind == kind
    }

    func isRowDisabled(requestId: String) -> Bool {
        processedRequestIds.contains(requestId) || busyRequestId == requestId
    }

    func configure(authService: FirebaseAuthService, modelContext: ModelContext) {
        self.authService = authService
        familyRepository.setModelContext(modelContext)
        UserRepository.shared.setModelContext(modelContext)
    }

    func onAppear() {
        loadPendingRequests()
        startObservingPendingRequests()
    }

    func onDisappear() {
        pendingObservation?.cancel()
        pendingObservation = nil
    }

    func refreshPendingRequests() async {
        do {
            let linked = try await familyRepository.fetchPendingRequests(familyId: familyId)
            pendingRequests = linked.filter { $0.statusEnum == .pending }
        } catch {
            loadPendingRequests()
        }
    }

    func approve(request: PendingJoinRequest) async -> Bool {
        await respond(to: request, approve: true)
    }

    func decline(request: PendingJoinRequest) async -> Bool {
        await respond(to: request, approve: false)
    }

    private func respond(to request: PendingJoinRequest, approve: Bool) async -> Bool {
        guard busyRequestId == nil else { return false }
        guard !processedRequestIds.contains(request.requestId) else { return false }

        guard let authService, authService.isOnline else {
            errorMessage = "Requires network connection".localized
            showError = true
            return false
        }

        busyRequestId = request.requestId
        busyKind = approve ? .approve : .decline
        defer {
            busyRequestId = nil
            busyKind = nil
        }

        do {
            try await familyRepository.respondToPendingRequest(
                familyId: familyId,
                requestId: request.requestId,
                approve: approve
            )
            if approve {
                AnalyticsService.shared.log(.familyJoinRequestApproved)
            } else {
                AnalyticsService.shared.log(.familyJoinRequestDeclined)
            }
            processedRequestIds.insert(request.requestId)
            await refreshPendingRequests()
            return true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return false
        }
    }

    private func loadPendingRequests() {
        pendingRequests = familyRepository.getPendingRequests(familyId: familyId)
            .filter { $0.statusEnum == .pending }
    }

    private func startObservingPendingRequests() {
        pendingObservation?.cancel()
        pendingObservation = familyRepository.$pendingRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pendingByFamily in
                guard let self, pendingByFamily[self.familyId] != nil else { return }
                self.loadPendingRequests()
            }
    }
}
