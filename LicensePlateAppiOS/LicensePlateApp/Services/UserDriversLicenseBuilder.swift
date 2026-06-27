//
//  UserDriversLicenseBuilder.swift
//  LicensePlateApp
//
//  Maps profile / progression / lifetime stats into a `UserDriversLicense` for `UserDriversLicenseCard`.
//

import Foundation
import SwiftUI

struct ProfileLicenseInputs {
    let user: AppUser
    var lifetimeStats: UserLifetimeStats?
    var totalXp: Int = 0
    var acceptedRegionFindCount: Int?
    var competitiveFirstPlaceFinishes: Int = 0
    var isRoyale: Bool = false
}

enum UserDriversLicenseBuilder {

    static func make(
        from inputs: ProfileLicenseInputs,
        catalogProvider: ProgressionCatalogProviding = ProgressionCatalogProvider.shared
    ) -> UserDriversLicense {
        let stats = inputs.lifetimeStats
        let xp = max(0, inputs.totalXp)
        let ladder = ProgressionCatalogProjection.rankLadder(from: catalogProvider.current)
        let rank = ladder.currentRank(xp: xp)
        let discoveries = stats?.totalDiscoveries ?? 0
        let regions = inputs.acceptedRegionFindCount ?? min(discoveries, 63)
        let isFamily = inputs.user.activeFamilyId != nil || inputs.user.wasEverInFamily

        return UserDriversLicense(
            holderName: inputs.user.displayName,
            issueDate: inputs.user.createdAt,
            rankLevel: rank.level,
            rankTitle: rank.title,
            statesProvincesFound: max(0, regions),
            platesFound: max(0, discoveries),
            tripsTaken: max(0, stats?.totalCompletedTrips ?? 0),
            gamesPlayed: max(0, stats?.totalGamesPlayed ?? 0),
            gamesWon: max(0, inputs.competitiveFirstPlaceFinishes),
            xp: xp,
            score: Int((stats?.totalWeightedScore ?? 0).rounded()),
            isRoyale: inputs.isRoyale,
            isFamilyMember: isFamily,
            badges: licenseBadges(for: inputs.user)
        )
    }

    static func licenseBadges(for user: AppUser) -> [LicenseBadge] {
        guard let badgeId = user.equippedBadgeId,
              let definition = UserBadgeCatalog.definition(byId: badgeId) else {
            return []
        }
        return [LicenseBadge(
            symbol: badgeIconSymbol(for: definition),
            label: definition.name,
            color: badgeAccentColor(for: definition.category)
        )]
    }

    private static func badgeIconSymbol(for definition: UserBadgeDefinition) -> String {
        switch definition.category {
        case .founderStatus: return "star.fill"
        case .discovery: return "map.fill"
        case .social: return "person.2.fill"
        case .trip: return "car.fill"
        }
    }

    private static func badgeAccentColor(for category: UserBadgeCategory) -> Color {
        switch category {
        case .founderStatus: return Color(red: 0.96, green: 0.77, blue: 0.26)
        case .discovery: return .green
        case .social: return .blue
        case .trip: return .orange
        }
    }
}
