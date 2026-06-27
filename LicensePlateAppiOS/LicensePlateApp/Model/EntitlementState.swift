//
//  EntitlementState.swift
//  LicensePlateApp
//
//  MVP Avatar & Badge Identity — user tier, family state, additive tags; effective tier and Family Pass derived.
//

import Foundation

// MARK: - User Tier (additive: higher includes lower)

enum UserTier: String, Codable, CaseIterable, Comparable {
    case guest
    case signedUp
    case gold
    case royale
    
    private static let order: [UserTier] = [.guest, .signedUp, .gold, .royale]
    
    static func < (lhs: UserTier, rhs: UserTier) -> Bool {
        guard let li = order.firstIndex(of: lhs), let ri = order.firstIndex(of: rhs) else { return false }
        return li < ri
    }
}

// MARK: - Entitlement State (client state from backend/cache)

struct EntitlementState {
    var userTier: UserTier
    var familyId: String?
    var wasEverInFamily: Bool
    var familyRole: String?
    var tags: Set<String> // e.g. "founder" (Firestore), "seasonal", "specialPromotion" (RevenueCat)
    var creatorTierForFamily: UserTier?
    
    /// familyUnlocked = in family now or was ever in family
    var familyUnlocked: Bool {
        familyId != nil || wasEverInFamily
    }
    
    /// Family Pass: user is in family AND creator has Gold or Royale (derived, not stored on Family)
    var familyPassUnlocked: Bool {
        guard familyId != nil else { return false }
        guard let creator = creatorTierForFamily else { return false }
        return creator == .gold || creator == .royale
    }
    
    /// effectiveTier = max(userTier, creatorTier) when in family
    var effectiveTier: UserTier {
        guard familyId != nil, let creator = creatorTierForFamily else { return userTier }
        return max(userTier, creator)
    }
    
    func hasTag(_ tag: String) -> Bool {
        tags.contains(tag)
    }
}
