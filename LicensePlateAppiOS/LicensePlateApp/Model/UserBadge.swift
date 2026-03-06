//
//  UserBadge.swift
//  LicensePlateApp
//
//  MVP: user/character badge definitions (app-local), progress and equipped slot; server validates unlocks.
//  Named UserBadge to avoid conflict with SwiftUI's Badge (numeric tab badge).
//

import Foundation

// MARK: - User Badge Category

enum UserBadgeCategory: String, Codable, CaseIterable {
    case founderStatus = "founder_status"
    case discovery
    case social
    case trip
}

// MARK: - User Badge Definition (app-local catalog)

struct UserBadgeDefinition: Identifiable {
    let id: String
    let name: String
    let category: UserBadgeCategory
    let description: String
    let iconAssetName: String
    let unlockType: String
    let sortOrder: Int
    var isHidden: Bool
}

// MARK: - MVP User Badge Definitions

enum UserBadgeCatalog {
    // Founder / Status
    static let founder = UserBadgeDefinition(id: "founder", name: "Founder", category: .founderStatus, description: "Founding member", iconAssetName: "badge_founder", unlockType: "one_time", sortOrder: 0, isHidden: false)
    static let earlyExplorer = UserBadgeDefinition(id: "early_explorer", name: "Early Explorer", category: .founderStatus, description: "Early member", iconAssetName: "badge_early_explorer", unlockType: "one_time", sortOrder: 1, isHidden: false)
    // Discovery
    static let firstPlateFound = UserBadgeDefinition(id: "first_plate_found", name: "First Plate Found", category: .discovery, description: "Found your first plate", iconAssetName: "badge_first_plate", unlockType: "progress", sortOrder: 10, isHidden: false)
    static let states10 = UserBadgeDefinition(id: "states_10", name: "10 States Found", category: .discovery, description: "Found plates in 10 states", iconAssetName: "badge_states_10", unlockType: "progress", sortOrder: 11, isHidden: false)
    static let states25 = UserBadgeDefinition(id: "states_25", name: "25 States Found", category: .discovery, description: "Found plates in 25 states", iconAssetName: "badge_states_25", unlockType: "progress", sortOrder: 12, isHidden: false)
    static let states50 = UserBadgeDefinition(id: "states_50", name: "50 States Found", category: .discovery, description: "Found plates in 50 states", iconAssetName: "badge_states_50", unlockType: "progress", sortOrder: 13, isHidden: false)
    static let allStatesComplete = UserBadgeDefinition(id: "all_states_complete", name: "All States Complete", category: .discovery, description: "Found all US states", iconAssetName: "badge_all_states", unlockType: "progress", sortOrder: 14, isHidden: false)
    // Social
    static let familyMember = UserBadgeDefinition(id: "family_member", name: "Family Member", category: .social, description: "Joined a family", iconAssetName: "badge_family_member", unlockType: "one_time", sortOrder: 20, isHidden: false)
    static let familyCaptain = UserBadgeDefinition(id: "family_captain", name: "Family Captain", category: .social, description: "Family captain or creator", iconAssetName: "badge_family_captain", unlockType: "one_time", sortOrder: 21, isHidden: false)
    static let firstFriendAdded = UserBadgeDefinition(id: "first_friend_added", name: "First Friend Added", category: .social, description: "Added your first friend", iconAssetName: "badge_first_friend", unlockType: "one_time", sortOrder: 22, isHidden: false)
    // Trip
    static let firstTrip = UserBadgeDefinition(id: "first_trip", name: "First Trip", category: .trip, description: "Completed your first trip", iconAssetName: "badge_first_trip", unlockType: "one_time", sortOrder: 30, isHidden: false)
    static let tripOrganizer = UserBadgeDefinition(id: "trip_organizer", name: "Trip Organizer", category: .trip, description: "Organized a trip", iconAssetName: "badge_trip_organizer", unlockType: "one_time", sortOrder: 31, isHidden: false)
    
    static var all: [UserBadgeDefinition] {
        [founder, earlyExplorer, firstPlateFound, states10, states25, states50, allStatesComplete, familyMember, familyCaptain, firstFriendAdded, firstTrip, tripOrganizer]
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    
    static func definition(byId id: String) -> UserBadgeDefinition? {
        all.first { $0.id == id }
    }
}

// MARK: - User Badge Progress (for local tracking; sync with server)

struct UserBadgeProgress: Identifiable {
    let badgeId: String
    var progress: Int?
    var unlockedAt: Date?
    var isEquipped: Bool
    
    var id: String { badgeId }
}
