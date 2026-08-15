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
    /// COPPA FR-85 (F-42): server-granted tag that floors `effectiveTier` at `.signedUp`
    /// for an account that holds the capability without holding credentials — today, a
    /// consented child, who FR-60 made an ANONYMOUS Firebase account and whom
    /// `AccountState.isGuestLike` therefore resolves to `.guest`.
    ///
    /// Written ONLY by the Admin SDK, in the consent transaction that grants membership
    /// (`familyMembershipGrantUserUpdate`), into `users/{uid}.entitlementTags` — which
    /// `firestore.rules` protects with the FR-7 diff-guard (`entitlementTags` is in
    /// `userDocPreservesServerControlledFields` / `userDocCreateOmitsServerControlledFields`,
    /// so a client may carry it through a merge but can never add, change or remove it).
    /// It reaches the client only via `UserRepository.parseEntitlementTags` reading that
    /// document back, so no local flag, defaults key, or SwiftData row can conjure it.
    ///
    /// Deliberately not keyed on `isChildAccount && activeFamilyId != nil`: `activeFamilyId`
    /// is the one field of that pair a client CAN write on its own user doc, so a local
    /// derivation would rest on a self-writable value. And deliberately not `isRegistered`,
    /// which FR-85 prohibits — that field drives search indexing (FR-70).
    static let signedUpEquivalentTag = "signedUpEquivalent"

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
    
    /// effectiveTier = max(userTier, creatorTier) when in family, floored at `.signedUp`
    /// when the FR-85 grant tag is held (see `signedUpEquivalentTag`).
    var effectiveTier: UserTier {
        let base = tags.contains(Self.signedUpEquivalentTag) ? max(userTier, .signedUp) : userTier
        guard familyId != nil, let creator = creatorTierForFamily else { return base }
        return max(base, creator)
    }
    
    func hasTag(_ tag: String) -> Bool {
        tags.contains(tag)
    }
}
