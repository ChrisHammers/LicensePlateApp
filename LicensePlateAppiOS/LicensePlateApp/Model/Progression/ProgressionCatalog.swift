//
//  ProgressionCatalog.swift
//  LicensePlateApp
//
//  Bundled achievement + rank ladder catalog (Phase 1).
//  Authoritative gameplay XP remains in ProgressionRewardsConfig.
//

import Foundation

// MARK: - Root catalog

struct ProgressionCatalog: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var achievements: [ProgressionCatalogAchievement]
    var rankLadder: ProgressionCatalogRankLadder
    var presentation: ProgressionCatalogPresentation
    var xpToast: ProgressionCatalogXpToast

    static let supportedSchemaVersions: Set<Int> = [1]

    var sortedXpToastGroups: [ProgressionCatalogXpToastGroup] {
        xpToast.groups.sorted {
            if $0.displayOrder != $1.displayOrder { return $0.displayOrder < $1.displayOrder }
            return $0.id < $1.id
        }
    }

    func xpToastGroup(id: String) -> ProgressionCatalogXpToastGroup? {
        xpToast.groups.first { $0.id == id }
    }

    /// Achievements shown in list UI (excludes `hidden`).
    var visibleAchievements: [ProgressionCatalogAchievement] {
        achievements.filter { !$0.hidden }
    }
}

// MARK: - Achievements

enum ProgressionCatalogAchievementCategory: String, Codable, CaseIterable, Sendable {
    case exploration
    case collection
    case competition
    case milestones
    case social
}

enum ProgressionCatalogAchievementRarity: String, Codable, CaseIterable, Sendable {
    case common
    case rare
    case epic
    case legendary
    case mythic
}

enum ProgressionCatalogAchievementEvaluator: String, Codable, CaseIterable, Sendable {
    case everCompetitiveFirstPlace = "ever_competitive_first_place"
    case acceptedRegionCount = "accepted_region_count"
    case totalDiscoveries = "total_discoveries"
    case winStreak = "win_streak"
    case completedTrips = "completed_trips"
    case familyMember = "family_member"
    case competitiveWins = "competitive_wins"
    case royaleMember = "royale_member"
    case flawless = "flawless"
    case founder = "founder"

    /// Evaluators that require `hidden: true` until data sources ship.
    static let deferredEvaluators: Set<ProgressionCatalogAchievementEvaluator> = [
        .winStreak,
        .flawless,
    ]
}

struct ProgressionCatalogAchievement: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var titleKey: String
    var detailKey: String
    var icon: String
    var rarity: ProgressionCatalogAchievementRarity
    var category: ProgressionCatalogAchievementCategory
    var goal: Int
    var xpReward: Int
    var hidden: Bool
    var evaluator: ProgressionCatalogAchievementEvaluator
}

// MARK: - Rank ladder

enum ProgressionCatalogRankUnlockKind: String, Codable, Sendable {
    case cosmetic
    case feature
    case badge
    case title
}

struct ProgressionCatalogRankUnlock: Codable, Equatable, Sendable, Identifiable {
    var titleKey: String
    var icon: String
    var kind: ProgressionCatalogRankUnlockKind

    var id: String { "\(kind.rawValue)-\(titleKey)" }
}

struct ProgressionCatalogRank: Codable, Equatable, Sendable, Identifiable {
    var level: Int
    var titleKey: String
    var xpRequired: Int
    var unlocks: [ProgressionCatalogRankUnlock]

    var id: Int { level }
}

struct ProgressionCatalogRankLadder: Codable, Equatable, Sendable {
    var ranks: [ProgressionCatalogRank]
}

// MARK: - Presentation (client-only; Remote Config override in Phase 2)

struct ProgressionCatalogPresentation: Codable, Equatable, Sendable {
    var achievementsEnabled: Bool
    var rankProgressionEnabled: Bool
}

// MARK: - XP toast grouping (Remote Config override supported)

struct ProgressionCatalogXpToast: Codable, Equatable, Sendable {
    var burstDurationSeconds: Int
    var groups: [ProgressionCatalogXpToastGroup]
}

struct ProgressionCatalogXpToastGroup: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var displayOrder: Int
    var titleKeySingle: String
    var titleKeyMulti: String
    var detailKey: String?
    var matchers: ProgressionCatalogXpToastMatchers
    var xpReward: Int?
}

struct ProgressionCatalogXpToastMatchers: Codable, Equatable, Sendable {
    var ledgerGrantKinds: [String]?
    var ledgerReasonCodes: [String]?
    var grantReasons: [String]?
    var clientEventKinds: [String]?
}

// MARK: - Defaults

extension ProgressionCatalog {

    /// Hardcoded mirror of `ProgressionCatalog.v1.json`; used when bundle load or validation fails.
    static let bundledDefault = ProgressionCatalog(
        schemaVersion: 1,
        achievements: [
            ProgressionCatalogAchievement(
                id: "first_win",
                titleKey: "achievement.first_win.title",
                detailKey: "achievement.first_win.detail",
                icon: "checkmark.seal.fill",
                rarity: .common,
                category: .competition,
                goal: 1,
                xpReward: 100,
                hidden: false,
                evaluator: .everCompetitiveFirstPlace
            ),
            ProgressionCatalogAchievement(
                id: "explorer_10",
                titleKey: "achievement.explorer_10.title",
                detailKey: "achievement.explorer_10.detail",
                icon: "signpost.right.fill",
                rarity: .common,
                category: .exploration,
                goal: 10,
                xpReward: 200,
                hidden: false,
                evaluator: .acceptedRegionCount
            ),
            ProgressionCatalogAchievement(
                id: "plates_100",
                titleKey: "achievement.plates_100.title",
                detailKey: "achievement.plates_100.detail",
                icon: "rectangle.on.rectangle",
                rarity: .common,
                category: .collection,
                goal: 100,
                xpReward: 250,
                hidden: false,
                evaluator: .totalDiscoveries
            ),
            ProgressionCatalogAchievement(
                id: "streak_5",
                titleKey: "achievement.streak_5.title",
                detailKey: "achievement.streak_5.detail",
                icon: "flame.fill",
                rarity: .rare,
                category: .competition,
                goal: 5,
                xpReward: 500,
                hidden: true,
                evaluator: .winStreak
            ),
            ProgressionCatalogAchievement(
                id: "trips_10",
                titleKey: "achievement.trips_10.title",
                detailKey: "achievement.trips_10.detail",
                icon: "road.lanes",
                rarity: .rare,
                category: .milestones,
                goal: 10,
                xpReward: 400,
                hidden: false,
                evaluator: .completedTrips
            ),
            ProgressionCatalogAchievement(
                id: "family",
                titleKey: "achievement.family.title",
                detailKey: "achievement.family.detail",
                icon: "person.3.fill",
                rarity: .rare,
                category: .social,
                goal: 1,
                xpReward: 300,
                hidden: false,
                evaluator: .familyMember
            ),
            ProgressionCatalogAchievement(
                id: "plates_1000",
                titleKey: "achievement.plates_1000.title",
                detailKey: "achievement.plates_1000.detail",
                icon: "square.stack.3d.up.fill",
                rarity: .epic,
                category: .collection,
                goal: 1_000,
                xpReward: 2_000,
                hidden: false,
                evaluator: .totalDiscoveries
            ),
            ProgressionCatalogAchievement(
                id: "wins_100",
                titleKey: "achievement.wins_100.title",
                detailKey: "achievement.wins_100.detail",
                icon: "trophy.fill",
                rarity: .epic,
                category: .competition,
                goal: 100,
                xpReward: 2_500,
                hidden: false,
                evaluator: .competitiveWins
            ),
            ProgressionCatalogAchievement(
                id: "trips_50",
                titleKey: "achievement.trips_50.title",
                detailKey: "achievement.trips_50.detail",
                icon: "car.2.fill",
                rarity: .epic,
                category: .milestones,
                goal: 50,
                xpReward: 1_500,
                hidden: false,
                evaluator: .completedTrips
            ),
            ProgressionCatalogAchievement(
                id: "royale",
                titleKey: "achievement.royale.title",
                detailKey: "achievement.royale.detail",
                icon: "crown.fill",
                rarity: .epic,
                category: .social,
                goal: 1,
                xpReward: 0,
                hidden: false,
                evaluator: .royaleMember
            ),
            ProgressionCatalogAchievement(
                id: "coast_to_coast",
                titleKey: "achievement.coast_to_coast.title",
                detailKey: "achievement.coast_to_coast.detail",
                icon: "map.fill",
                rarity: .legendary,
                category: .exploration,
                goal: 63,
                xpReward: 5_000,
                hidden: false,
                evaluator: .acceptedRegionCount
            ),
            ProgressionCatalogAchievement(
                id: "flawless",
                titleKey: "achievement.flawless.title",
                detailKey: "achievement.flawless.detail",
                icon: "sparkles",
                rarity: .legendary,
                category: .competition,
                goal: 1,
                xpReward: 1_500,
                hidden: true,
                evaluator: .flawless
            ),
            ProgressionCatalogAchievement(
                id: "founder",
                titleKey: "achievement.founder.title",
                detailKey: "achievement.founder.detail",
                icon: "star.circle.fill",
                rarity: .mythic,
                category: .milestones,
                goal: 1,
                xpReward: 0,
                hidden: false,
                evaluator: .founder
            ),
        ],
        rankLadder: ProgressionCatalogRankLadder(ranks: [
            ProgressionCatalogRank(
                level: 1,
                titleKey: "rank.rookie_rider.title",
                xpRequired: 0,
                unlocks: [
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.standard_license",
                        icon: "creditcard.fill",
                        kind: .cosmetic
                    ),
                ]
            ),
            ProgressionCatalogRank(
                level: 2,
                titleKey: "rank.road_tripper.title",
                xpRequired: 1_000,
                unlocks: [
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.custom_plate_name",
                        icon: "textformat",
                        kind: .feature
                    ),
                ]
            ),
            ProgressionCatalogRank(
                level: 3,
                titleKey: "rank.navigator.title",
                xpRequired: 3_000,
                unlocks: [
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.navigator_badge",
                        icon: "location.north.circle.fill",
                        kind: .badge
                    ),
                ]
            ),
            ProgressionCatalogRank(
                level: 4,
                titleKey: "rank.trailblazer.title",
                xpRequired: 7_000,
                unlocks: [
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.carbon_edition",
                        icon: "square.grid.3x3.fill",
                        kind: .cosmetic
                    ),
                ]
            ),
            ProgressionCatalogRank(
                level: 5,
                titleKey: "rank.pathfinder.title",
                xpRequired: 15_000,
                unlocks: [
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.family_invites",
                        icon: "person.3.fill",
                        kind: .feature
                    ),
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.pathfinder_badge",
                        icon: "rosette",
                        kind: .badge
                    ),
                ]
            ),
            ProgressionCatalogRank(
                level: 6,
                titleKey: "rank.road_warrior.title",
                xpRequired: 30_000,
                unlocks: [
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.gold_foil",
                        icon: "sparkles",
                        kind: .cosmetic
                    ),
                ]
            ),
            ProgressionCatalogRank(
                level: 7,
                titleKey: "rank.highway_legend.title",
                xpRequired: 55_000,
                unlocks: [
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.legend_title",
                        icon: "text.badge.star",
                        kind: .title
                    ),
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.legend_badge",
                        icon: "medal.fill",
                        kind: .badge
                    ),
                ]
            ),
            ProgressionCatalogRank(
                level: 8,
                titleKey: "rank.route_master.title",
                xpRequired: 90_000,
                unlocks: [
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.platinum_foil",
                        icon: "diamond.fill",
                        kind: .cosmetic
                    ),
                ]
            ),
            ProgressionCatalogRank(
                level: 9,
                titleKey: "rank.asphalt_royalty.title",
                xpRequired: 140_000,
                unlocks: [
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.midnight_drive",
                        icon: "moon.stars.fill",
                        kind: .cosmetic
                    ),
                ]
            ),
            ProgressionCatalogRank(
                level: 10,
                titleKey: "rank.grand_voyager.title",
                xpRequired: 220_000,
                unlocks: [
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.prestige_mode",
                        icon: "infinity",
                        kind: .feature
                    ),
                    ProgressionCatalogRankUnlock(
                        titleKey: "rank.unlock.founder_frame",
                        icon: "crown.fill",
                        kind: .cosmetic
                    ),
                ]
            ),
        ]),
        presentation: ProgressionCatalogPresentation(
            achievementsEnabled: true,
            rankProgressionEnabled: true
        ),
        xpToast: ProgressionCatalog.bundledDefaultXpToast
    )

    static let bundledDefaultXpToast = ProgressionCatalogXpToast(
        burstDurationSeconds: 4,
        groups: [
            ProgressionCatalogXpToastGroup(
                id: "discovery",
                displayOrder: 10,
                titleKeySingle: "xp.toast.group.discovery.single",
                titleKeyMulti: "xp.toast.group.discovery.multi",
                detailKey: "xp.toast.group.discovery.detail",
                matchers: ProgressionCatalogXpToastMatchers(
                    ledgerGrantKinds: [
                        XpGrantKind.provisionalDiscoveryXp.rawValue,
                        XpGrantKind.finalDiscoveryAward.rawValue,
                        XpGrantKind.reconciliationAdjustment.rawValue,
                    ],
                    ledgerReasonCodes: [
                        XpReasonCode.soloNewDiscovery.rawValue,
                        XpReasonCode.competitiveFirstFinder.rawValue,
                        XpReasonCode.competitiveLateFinder.rawValue,
                        XpReasonCode.collaborativeSharedFinder.rawValue,
                        XpReasonCode.discoveryClaimPendingResolution.rawValue,
                    ],
                    grantReasons: nil,
                    clientEventKinds: nil
                ),
                xpReward: nil
            ),
            ProgressionCatalogXpToastGroup(
                id: "achievement",
                displayOrder: 20,
                titleKeySingle: "xp.toast.group.achievement.single",
                titleKeyMulti: "xp.toast.group.achievement.multi",
                detailKey: nil,
                matchers: ProgressionCatalogXpToastMatchers(
                    ledgerGrantKinds: [XpGrantKind.milestoneUnlock.rawValue],
                    ledgerReasonCodes: [XpReasonCode.milestoneUnlock.rawValue],
                    grantReasons: [UserXpGrantReason.achievementUnlock.rawValue],
                    clientEventKinds: nil
                ),
                xpReward: nil
            ),
            ProgressionCatalogXpToastGroup(
                id: "return_streak",
                displayOrder: 30,
                titleKeySingle: "xp.toast.group.return_streak.single",
                titleKeyMulti: "xp.toast.group.return_streak.multi",
                detailKey: nil,
                matchers: ProgressionCatalogXpToastMatchers(
                    ledgerGrantKinds: [XpGrantKind.milestoneUnlock.rawValue],
                    ledgerReasonCodes: [XpReasonCode.returnStreakDaily.rawValue],
                    grantReasons: nil,
                    clientEventKinds: ["return_streak"]
                ),
                xpReward: 5
            ),
            ProgressionCatalogXpToastGroup(
                id: "competitive_win",
                displayOrder: 40,
                titleKeySingle: "xp.toast.group.competitive_win.single",
                titleKeyMulti: "xp.toast.group.competitive_win.multi",
                detailKey: nil,
                matchers: ProgressionCatalogXpToastMatchers(
                    ledgerGrantKinds: nil,
                    ledgerReasonCodes: nil,
                    grantReasons: [UserXpGrantReason.competitiveFirstPlaceFinish.rawValue],
                    clientEventKinds: nil
                ),
                xpReward: nil
            ),
            ProgressionCatalogXpToastGroup(
                id: "other",
                displayOrder: 999,
                titleKeySingle: "xp.toast.group.other.single",
                titleKeyMulti: "xp.toast.group.other.multi",
                detailKey: nil,
                matchers: ProgressionCatalogXpToastMatchers(
                    ledgerGrantKinds: nil,
                    ledgerReasonCodes: nil,
                    grantReasons: nil,
                    clientEventKinds: nil
                ),
                xpReward: nil
            ),
        ]
    )

    /// Deterministic fixture for unit tests (matches bundled default).
    static let fixtureDefault = bundledDefault
}
