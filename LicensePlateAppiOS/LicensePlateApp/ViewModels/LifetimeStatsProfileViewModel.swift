//
//  LifetimeStatsProfileViewModel.swift
//  LicensePlateApp
//
//  Profile-facing adapter over `LifetimeStatsCoordinator` (UI state + refresh entry points).
//

import Foundation
import Combine

@MainActor
final class LifetimeStatsProfileViewModel: ObservableObject {
    @Published private(set) var stats: UserLifetimeStats?
    @Published private(set) var isRecomputing = false
    @Published private(set) var isPendingServerSync = false
    @Published private(set) var lastError: String?

    private let userId: String
    private let coordinator: LifetimeStatsCoordinator
    private var cancellables = Set<AnyCancellable>()

    init(userId: String, coordinator: LifetimeStatsCoordinator = .shared) {
        self.userId = userId
        self.coordinator = coordinator
        coordinator.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                stats = coordinator.stats
                isRecomputing = coordinator.isRecomputing
                isPendingServerSync = coordinator.isPendingServerSync
                lastError = coordinator.lastError
            }
            .store(in: &cancellables)
        syncFromCoordinator()
    }

    private func syncFromCoordinator() {
        stats = coordinator.stats
        isRecomputing = coordinator.isRecomputing
        isPendingServerSync = coordinator.isPendingServerSync
        lastError = coordinator.lastError
    }

    func onAppear() {
        coordinator.onProfileAppear(userId: userId)
    }

    func clearError() {
        coordinator.clearError()
    }

    func retryRefresh() {
        coordinator.clearError()
        coordinator.requestFallbackRecompute(userId: userId)
        AnalyticsService.shared.log(.lifetimeStatsProfileRetryTapped)
    }
}
