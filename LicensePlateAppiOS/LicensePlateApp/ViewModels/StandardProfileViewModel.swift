//
//  StandardProfileViewModel.swift
//  LicensePlateApp
//
//  Read-only profile adapter for self or looked-up users (public lifetime stats + local progression when self).
//

import Combine
import Foundation

@MainActor
final class StandardProfileViewModel: ObservableObject {
    @Published private(set) var lifetimeStats: UserLifetimeStats?
    @Published private(set) var isRecomputing = false
    @Published private(set) var isPendingServerSync = false
    @Published private(set) var lastError: String?

    let user: AppUser
    let isSelfProfile: Bool

    private let userId: String
    private let lifetimeStatsViewModel: LifetimeStatsProfileViewModel?
    private let xpProgressViewModel: XpProgressViewModel?
    private let publicLifetimeStatsRepository: PublicLifetimeStatsRepository
    private var cancellables = Set<AnyCancellable>()

    init(
        user: AppUser,
        isSelfProfile: Bool,
        lifetimeStatsViewModel: LifetimeStatsProfileViewModel? = nil,
        xpProgressViewModel: XpProgressViewModel? = nil,
        publicLifetimeStatsRepository: PublicLifetimeStatsRepository = .shared
    ) {
        self.user = user
        self.isSelfProfile = isSelfProfile
        self.userId = user.firebaseUID ?? user.id
        self.lifetimeStatsViewModel = isSelfProfile ? lifetimeStatsViewModel : nil
        self.xpProgressViewModel = isSelfProfile ? xpProgressViewModel : nil
        self.publicLifetimeStatsRepository = publicLifetimeStatsRepository

        if isSelfProfile, let lifetimeStatsViewModel {
            lifetimeStatsViewModel.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.syncFromLifetimeStatsViewModel() }
                .store(in: &cancellables)
            syncFromLifetimeStatsViewModel()
        } else {
            publicLifetimeStatsRepository.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.syncPublicStats() }
                .store(in: &cancellables)
            syncPublicStats()
        }

        if isSelfProfile, let xpProgressViewModel {
            xpProgressViewModel.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    func onAppear() {
        if isSelfProfile {
            lifetimeStatsViewModel?.onAppear()
            xpProgressViewModel?.refresh()
        } else {
            publicLifetimeStatsRepository.ensureObservingFriend(userId: userId)
            syncPublicStats()
        }
    }

    func retryRefresh() {
        lifetimeStatsViewModel?.retryRefresh()
    }

    func makeLicense(isRoyale: Bool) -> UserDriversLicense {
        let progression = UserProgressionRepository.shared.snapshot
        let effective = UserProgressionService.shared.effectiveTotals
        let xp = isSelfProfile
            ? (xpProgressViewModel?.displayedTotalXp ?? effective?.totalXp ?? progression?.totalXp ?? 0)
            : 0
        let regions = isSelfProfile
            ? (effective?.acceptedRegionFindCount ?? progression?.acceptedRegionFindCount)
            : nil
        let wins = isSelfProfile
            ? (effective?.competitiveFirstPlaceFinishes ?? progression?.competitiveFirstPlaceFinishes ?? 0)
            : 0

        return UserDriversLicenseBuilder.make(from: ProfileLicenseInputs(
            user: user,
            lifetimeStats: lifetimeStats,
            totalXp: xp,
            acceptedRegionFindCount: regions,
            competitiveFirstPlaceFinishes: wins,
            isRoyale: isRoyale
        ))
    }

    private func syncFromLifetimeStatsViewModel() {
        guard let vm = lifetimeStatsViewModel else { return }
        lifetimeStats = vm.stats
        isRecomputing = vm.isRecomputing
        isPendingServerSync = vm.isPendingServerSync
        lastError = vm.lastError
    }

    private func syncPublicStats() {
        lifetimeStats = publicLifetimeStatsRepository.snapshot(forUserId: userId)
            ?? (try? publicLifetimeStatsRepository.cachedStatsFromDisk(forUserId: userId))
        isRecomputing = false
        isPendingServerSync = lifetimeStats == nil
        lastError = nil
    }
}
