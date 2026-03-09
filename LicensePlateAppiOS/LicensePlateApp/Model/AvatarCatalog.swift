//
//  AvatarCatalog.swift
//  LicensePlateApp
//
//  MVP Avatar & Badge Identity System — local/bundled assets only; assetSource supports future downloaded assets.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Asset Source (MVP: bundled only; future: downloaded)

enum AvatarAssetSource: String, Codable, CaseIterable {
    case bundled   // Load from app bundle (MVP)
    case downloaded // Future: load from URL or local cache
}

// MARK: - Unlock Source (determines lock icon and upsell copy)

enum AvatarUnlockSource: String, Codable, CaseIterable {
    case guest
    case signedUp
    case gold
    case royale
    case family
    case familyPass
    case founder
    case lifetime
    case achievement
    case seasonal
    case specialPromotion
    
    var lockIconName: String {
        switch self {
        case .guest: return "person.circle"
        case .signedUp: return "person.badge.plus"
        case .gold: return "star.fill"
        case .royale: return "crown.fill"
        case .family: return "person.2"
        case .familyPass: return "person.2.fill"
        case .founder: return "flag.fill"
        case .lifetime: return "infinity"
        case .achievement: return "rosette"
        case .seasonal: return "leaf"
        case .specialPromotion: return "tag"
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .guest: return 0
        case .signedUp: return 1
        case .gold: return 2
        case .royale: return 3
        case .family: return 4
        case .familyPass: return 5
        case .founder: return 6
        case .lifetime: return 7
        case .achievement: return 8
        case .seasonal: return 9
        case .specialPromotion: return 10
        }
    }
}

// MARK: - Avatar Item (catalog entry; not persisted)

struct AvatarItem: Identifiable, Equatable {
    let id: String
    let displayName: String
    let assetName: String
    var assetSource: AvatarAssetSource
    let unlockSource: AvatarUnlockSource
    
    init(
        id: String,
        displayName: String,
        assetName: String? = nil,
        assetSource: AvatarAssetSource = .bundled,
        unlockSource: AvatarUnlockSource
    ) {
        self.id = id
        self.displayName = displayName
        self.assetName = assetName ?? id
        self.assetSource = assetSource
        self.unlockSource = unlockSource
    }
}

// MARK: - Catalog (single source of truth; immutable IDs)

enum AvatarCatalog {
    
    // MARK: Guest (10)
    static let guestAvatars: [AvatarItem] = [
        AvatarItem(id: "navigator_raccoon", displayName: "Navigator Raccoon", unlockSource: .guest),
        AvatarItem(id: "canada_moose", displayName: "Canada Moose", unlockSource: .guest),
        AvatarItem(id: "mexican_axolotl", displayName: "Mexican Axolotl", unlockSource: .guest),
        AvatarItem(id: "usa_bald_eagle", displayName: "USA Bald Eagle", unlockSource: .guest),
        AvatarItem(id: "scout_otter", displayName: "Scout Otter", unlockSource: .guest),
        AvatarItem(id: "jackrabbit", displayName: "Jackrabbit", unlockSource: .guest),
        AvatarItem(id: "turtle", displayName: "Turtle", unlockSource: .guest),
        AvatarItem(id: "dog", displayName: "Dog", unlockSource: .guest),
        AvatarItem(id: "cat", displayName: "Cat", unlockSource: .guest),
        AvatarItem(id: "police_officer_pig", displayName: "Police Officer Pig", unlockSource: .guest)
    ]
    
    // MARK: SignedUp (5)
    static let signedUpAvatars: [AvatarItem] = [
        AvatarItem(id: "construction_beaver", displayName: "Construction Beaver", unlockSource: .signedUp),
        AvatarItem(id: "grizzly_bear_park_ranger", displayName: "Grizzly Bear Park Ranger", unlockSource: .signedUp),
        AvatarItem(id: "dragon", displayName: "Dragon", unlockSource: .signedUp),
        AvatarItem(id: "crossing_sign_deer", displayName: "Crossing Sign Deer", unlockSource: .signedUp),
        AvatarItem(id: "chihuahua", displayName: "Chihuahua", unlockSource: .signedUp)
    ]
    
    // MARK: Gold (5)
    static let goldAvatars: [AvatarItem] = [
        AvatarItem(id: "midnight_traveling_bat", displayName: "Midnight Traveling Bat", unlockSource: .gold),
        AvatarItem(id: "frog", displayName: "Frog", unlockSource: .gold),
        AvatarItem(id: "fish", displayName: "Fish", unlockSource: .gold),
        AvatarItem(id: "cleaning_up_squirrel", displayName: "Cleaning-Up Squirrel", unlockSource: .gold),
        AvatarItem(id: "hitchhiker_polar_bear", displayName: "Hitchhiker Polar Bear", unlockSource: .gold)
    ]
    
    // MARK: Family (2)
    static let familyAvatars: [AvatarItem] = [
        AvatarItem(id: "wolf", displayName: "Wolf", unlockSource: .family),
        AvatarItem(id: "bison", displayName: "Bison", unlockSource: .family)
    ]
    
    // MARK: Family Pass (2)
    static let familyPassAvatars: [AvatarItem] = [
        AvatarItem(id: "sea_captain_octopus", displayName: "Sea Captain Octopus", unlockSource: .familyPass),
        AvatarItem(id: "junior_scout_porcupine", displayName: "Junior Scout Porcupine", unlockSource: .familyPass)
    ]
    
    // MARK: Founder (2)
    static let founderAvatars: [AvatarItem] = [
        AvatarItem(id: "founder_scout_fox", displayName: "Founder Scout Fox", unlockSource: .founder),
        AvatarItem(id: "founder_scout_bobcat", displayName: "Founder Scout Bobcat", unlockSource: .founder)
    ]
    
    /// Flat list in tier/unlock order for picker
    static var allAvatars: [AvatarItem] {
        guestAvatars + signedUpAvatars + goldAvatars + familyAvatars + familyPassAvatars + founderAvatars
    }
    
    /// All guest avatar IDs (for random assignment)
    static var guestAvatarIds: [String] {
        guestAvatars.map(\.id)
    }
    
    /// Random guest avatar ID for first-launch assignment
    static func randomGuestAvatarId() -> String {
        guestAvatarIds.randomElement() ?? guestAvatars[0].id
    }
    
    /// Look up by id
    static func avatar(byId id: String) -> AvatarItem? {
        allAvatars.first { $0.id == id }
    }
    
    #if canImport(UIKit)
    /// Resolve bundled avatar image for map/profile use. Returns nil if id is nil or asset not found.
    static func image(forAvatarId id: String?) -> UIImage? {
        guard let id = id, let item = avatar(byId: id) else { return nil }
        return UIImage(named: item.assetName)
    }
    #endif
}
