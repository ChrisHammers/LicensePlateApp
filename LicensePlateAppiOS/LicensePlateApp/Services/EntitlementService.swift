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
    
    static let shared = EntitlementService()
    
    private var modelContext: ModelContext?
    private let familyRepository: FamilyRepository
    private let userRepository: UserRepository
    
    init(familyRepository: FamilyRepository = .shared, userRepository: UserRepository = .shared) {
        self.familyRepository = familyRepository
        self.userRepository = userRepository
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Entitlement State
    
    /// Build entitlement state for a user (uses cached family and creator when available)
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
        if user.firebaseUID != nil && !(user.email?.isEmpty ?? true) { /* signed up */ }
        // TODO: when backend sends tags (founder, seasonal, etc.), add from user profile
        // if user.hasFounderTag { tags.insert("founder") }
        
        return EntitlementState(
            userTier: tier,
            familyId: familyId,
            wasEverInFamily: wasEverInFamily,
            familyRole: familyRole,
            tags: tags,
            creatorTierForFamily: creatorTierForFamily
        )
    }
    
    /// User tier from auth state: guest (anonymous or no firebaseUID), signedUp (has firebaseUID + persisted), gold/royale from backend (TODO)
    private func userTier(for user: AppUser) -> UserTier {
        if user.firebaseUID == nil { return .guest }
        // TODO: when backend provides tier, read from user or subscription
        // if user.subscriptionTier == "royale" { return .royale }
        // if user.subscriptionTier == "gold" { return .gold }
        return .signedUp
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
        case .seasonal:
            return entitlement.hasTag("seasonal")
        case .specialPromotion:
            return entitlement.hasTag("specialPromotion")
        }
    }
}
