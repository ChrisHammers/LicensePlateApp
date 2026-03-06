//
//  AvatarCatalogService.swift
//  LicensePlateApp
//
//  Provides catalog, random guest avatar, avatar by id, and unlock state for current user.
//

import Foundation
import SwiftData
import Combine

/// Display item for picker: catalog item + resolved unlock state
struct AvatarDisplayItem: Identifiable, Equatable {
    let id: String
    let displayName: String
    let assetName: String
    let assetSource: AvatarAssetSource
    let unlockSource: AvatarUnlockSource
    let isUnlocked: Bool
    
    init(from item: AvatarItem, isUnlocked: Bool) {
        self.id = item.id
        self.displayName = item.displayName
        self.assetName = item.assetName
        self.assetSource = item.assetSource
        self.unlockSource = item.unlockSource
        self.isUnlocked = isUnlocked
    }
}

@MainActor
final class AvatarCatalogService: ObservableObject {
    
    static let shared = AvatarCatalogService(entitlementService: .shared)
    
    private let entitlementService: EntitlementService
    
    init(entitlementService: EntitlementService) {
        self.entitlementService = entitlementService
    }
    
    /// Full catalog in tier order
    var allAvatars: [AvatarItem] {
        AvatarCatalog.allAvatars
    }
    
    /// Random guest avatar ID (for first-launch assignment)
    func randomGuestAvatarId() -> String {
        AvatarCatalog.randomGuestAvatarId()
    }
    
    /// Avatar by id
    func avatar(byId id: String) -> AvatarItem? {
        AvatarCatalog.avatar(byId: id)
    }
    
    /// Display items for picker with unlock state for given user
    func displayItems(for user: AppUser?) -> [AvatarDisplayItem] {
        let entitlement = user.map { entitlementService.entitlementState(for: $0) } ?? EntitlementState(userTier: .guest, familyId: nil, wasEverInFamily: false, familyRole: nil, tags: [], creatorTierForFamily: nil)
        return AvatarCatalog.allAvatars.map { item in
            let unlocked = entitlementService.isUnlocked(avatar: item, entitlement: entitlement)
            return AvatarDisplayItem(from: item, isUnlocked: unlocked)
        }
    }
    
    /// Resolve asset name for display (avatarId or legacy defaultImageName)
    func assetName(for user: AppUser) -> String? {
        if let aid = user.avatarId, let item = AvatarCatalog.avatar(byId: aid) {
            return item.assetName
        }
        return nil
    }
}
