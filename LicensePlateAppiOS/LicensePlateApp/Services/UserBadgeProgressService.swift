//
//  UserBadgeProgressService.swift
//  LicensePlateApp
//
//  MVP: local progress, one equipped slot; server validates unlocks (TODO sync).
//  Named to avoid conflict with SwiftUI's Badge.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class UserBadgeProgressService: ObservableObject {
    
    static let shared = UserBadgeProgressService()
    
    private var modelContext: ModelContext?
    
    private init() {}
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Definitions
    
    var allBadges: [UserBadgeDefinition] {
        UserBadgeCatalog.all
    }
    
    func definition(byId id: String) -> UserBadgeDefinition? {
        UserBadgeCatalog.definition(byId: id)
    }
    
    // MARK: - Progress (MVP: in-memory / User; later SwiftData or sync)
    
    /// Progress for a user badge (e.g. states found count for discovery). Server is source of truth; client tracks locally until sync.
    func progress(for badgeId: String, userId: String) -> Int {
        // TODO: load from local store or server
        return 0
    }
    
    /// Whether user badge is unlocked for user (server-validated; client can show optimistically)
    func isUnlocked(badgeId: String, userId: String) -> Bool {
        // TODO: check server or local cache
        guard let def = UserBadgeCatalog.definition(byId: badgeId) else { return false }
        if def.unlockType == "one_time" {
            return progress(for: badgeId, userId: userId) > 0
        }
        return false
    }
    
    /// Equipped user badge comes from AppUser.equippedBadgeId
    func equippedBadge(for user: AppUser) -> UserBadgeDefinition? {
        guard let id = user.equippedBadgeId else { return nil }
        return UserBadgeCatalog.definition(byId: id)
    }
}
