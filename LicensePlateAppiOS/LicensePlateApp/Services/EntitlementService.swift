//
//  EntitlementService.swift
//  LicensePlateApp
//
//  Resolves effective tier, family state, Family Pass (from creator), and avatar unlock state.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class EntitlementService: ObservableObject {
    
    static let shared = EntitlementService(revenueCatBridge: RevenueCatEntitlementBridge.shared)
    
    private var modelContext: ModelContext?
    private var currentAppUserId: String?
    private let familyRepository: FamilyRepository
    private let userRepository: UserRepository
    private weak var revenueCatBridge: RevenueCatEntitlementProviding?
    
    init(familyRepository: FamilyRepository = .shared, userRepository: UserRepository = .shared, revenueCatBridge: RevenueCatEntitlementProviding? = nil) {
        self.familyRepository = familyRepository
        self.userRepository = userRepository
        self.revenueCatBridge = revenueCatBridge
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    /// Set the current app user id (e.g. Firebase UID or local id). Used to merge RevenueCat tier/tags for this user only.
    func setCurrentUserId(_ id: String?) {
        currentAppUserId = id
    }
    
    // MARK: - Entitlement State
    
    /// Build entitlement state for a user (uses cached family and creator when available; merges RevenueCat tier/tags for current user)
    func entitlementState(for user: AppUser) -> EntitlementState {
        let tier = userTier(for: user)
        let familyId = user.activeFamilyId
        let wasEverInFamily = user.wasEverInFamily
        var familyRole: String?
        var creatorTierForFamily: UserTier?
        
        if let fid = familyId,
           let family = familyRepository.families.first(where: { $0.familyId == fid }),
           let members = familyRepository.familyMembers[fid] {
            if let member = members.first(where: { $0.userId == user.id }) {
                familyRole = member.role
            }
            let creatorId = family.creatorId
            if let creator = getCachedUser(creatorId) {
                creatorTierForFamily = userTier(for: creator)
            }
        }
        
        var tags: Set<String> = []
        if isCurrentUser(user) {
            if let bridge = revenueCatBridge {
                tags = bridge.currentTags
            }
        }
        
        return EntitlementState(
            userTier: tier,
            familyId: familyId,
            wasEverInFamily: wasEverInFamily,
            familyRole: familyRole,
            tags: tags,
            creatorTierForFamily: creatorTierForFamily
        )
    }
    
    /// User tier: base from auth (guest/signedUp); for current user, merged with RevenueCat subscription tier (gold/royale).
    private func userTier(for user: AppUser) -> UserTier {
        let base: UserTier = user.firebaseUID == nil ? .guest : .signedUp
        guard isCurrentUser(user), let bridge = revenueCatBridge else { return base }
        return max(base, bridge.currentTier)
    }
    
    private func isCurrentUser(_ user: AppUser) -> Bool {
        guard let currentId = currentAppUserId else { return false }
        return user.id == currentId || user.firebaseUID == currentId
    }
    
    private func getCachedUser(_ userId: String) -> AppUser? {
        guard let modelContext = modelContext else { return nil }
        let descriptor = FetchDescriptor<AppUser>(
            predicate: #Predicate<AppUser> { $0.id == userId }
        )
        return try? modelContext.fetch(descriptor).first
    }
    
    // MARK: - Avatar Unlock
    
    /// Whether the current user can use this avatar (effective tier + family/tags)
    func isUnlocked(avatar: AvatarItem, entitlement: EntitlementState) -> Bool {
        switch avatar.unlockSource {
        case .guest:
            return true
        case .signedUp:
            return entitlement.effectiveTier >= .signedUp
        case .gold:
            return entitlement.effectiveTier >= .gold
        case .royale:
            return entitlement.effectiveTier >= .royale
        case .family:
            return entitlement.familyUnlocked
        case .familyPass:
            return entitlement.familyPassUnlocked
        case .founder:
            return entitlement.hasTag("founder")
        case .lifetime:
            return entitlement.hasTag("lifetime")
        case .achievement:
            return entitlement.hasTag("achievement")
        case .seasonal:
            return entitlement.hasTag("seasonal")
        case .specialPromotion:
            return entitlement.hasTag("specialPromotion")
        }
    }
}
