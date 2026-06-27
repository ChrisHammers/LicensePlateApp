//
//  AchievementProgressViewModel.swift
//  LicensePlateApp
//
//  Profile progression: catalog projections + live achievement status.
//

import Combine
import Foundation

@MainActor
final class AchievementProgressViewModel: ObservableObject {
    @Published private(set) var achievements: [Achievement] = []
    @Published private(set) var statuses: [String: AchievementStatus] = [:]
    @Published private(set) var rankLadder: RankLadder = RankLadder(ranks: [])
    @Published private(set) var totalXp: Int = 0
    @Published private(set) var achievementsEnabled: Bool = true
    @Published private(set) var rankProgressionEnabled: Bool = true

    private let user: AppUser
    private let catalogProvider: ProgressionCatalogProviding
    private let userProgressionService: UserProgressionService
    private let entitlementService: EntitlementService
    private let lifetimeStatsViewModel: LifetimeStatsProfileViewModel
    private let xpProgressViewModel: XpProgressViewModel
    private var cancellables = Set<AnyCancellable>()

    init(
        user: AppUser,
        lifetimeStatsViewModel: LifetimeStatsProfileViewModel,
        xpProgressViewModel: XpProgressViewModel,
        catalogProvider: ProgressionCatalogProviding = ProgressionCatalogProvider.shared,
        userProgressionService: UserProgressionService = .shared,
        entitlementService: EntitlementService = .shared
    ) {
        self.user = user
        self.lifetimeStatsViewModel = lifetimeStatsViewModel
        self.xpProgressViewModel = xpProgressViewModel
        self.catalogProvider = catalogProvider
        self.userProgressionService = userProgressionService
        self.entitlementService = entitlementService

        lifetimeStatsViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        xpProgressViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        userProgressionService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        entitlementService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        refresh()
    }

    func refresh() {
        let catalog = catalogProvider.current
        achievementsEnabled = catalog.presentation.achievementsEnabled
        rankProgressionEnabled = catalog.presentation.rankProgressionEnabled
        achievements = ProgressionCatalogProjection.achievements(from: catalog)
        rankLadder = ProgressionCatalogProjection.rankLadder(from: catalog)
        totalXp = max(0, xpProgressViewModel.displayedTotalXp)

        let entitlement = entitlementService.entitlementState(for: user)
        let inputs = AchievementProgressInputs(
            progression: userProgressionService.effectiveTotals,
            lifetimeStats: lifetimeStatsViewModel.stats,
            isFamilyMember: user.activeFamilyId != nil || user.wasEverInFamily,
            isRoyale: entitlement.effectiveTier >= .royale,
            isFounder: entitlement.hasTag("founder")
        )
        statuses = AchievementProgressResolver.statuses(
            for: catalog.visibleAchievements,
            inputs: inputs
        )
    }
}
