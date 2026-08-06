//
//  LicenseCosmeticStore.swift
//  LicensePlateApp
//
//  UI cache + ownership for Explorer license skins.
//  Source of truth is AppUser.equippedLicenseCosmeticId (synced to Firestore like avatarId).
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class LicenseCosmeticStore: ObservableObject {
    static let shared = LicenseCosmeticStore()

    @Published private(set) var equippedID: String = LicenseCosmetic.catalog[0].id
    @Published private(set) var ownedIDs: Set<String> = [LicenseCosmetic.catalog[0].id]

    private var userId: String?
    private weak var boundUser: AppUser?
    private let defaults = UserDefaults.standard

    private init() {}

    /// Bind store to the signed-in user, hydrate equipped id from AppUser, and recompute ownership.
    func configure(user: AppUser, rankLevel: Int) {
        let normalizedRank = max(1, rankLevel)
        let userChanged = self.userId != user.id
        self.userId = user.id
        self.boundUser = user
        ownedIDs = Self.computeOwnedIDs(rankLevel: normalizedRank)
        if userChanged {
            equippedID = resolveEquippedID(for: user)
        } else if let current = user.equippedLicenseCosmeticId, ownedIDs.contains(current) {
            equippedID = current
        }
        // Keep equipped valid against current ownership.
        if !ownedIDs.contains(equippedID) {
            equip(LicenseCosmetic.catalog[0].id)
        }
    }

    var equippedStyle: LicenseStyle {
        LicenseCosmetic.first(equippedID).style
    }

    var equippedIDBinding: Binding<String> {
        Binding(
            get: { self.equippedID },
            set: { self.equip($0) }
        )
    }

    func equip(_ id: String) {
        guard ownedIDs.contains(id) else { return }
        guard equippedID != id else {
            // Still mirror onto AppUser if store and model drifted.
            if boundUser?.equippedLicenseCosmeticId != id {
                boundUser?.equippedLicenseCosmeticId = id
                boundUser?.lastUpdated = .now
            }
            return
        }
        equippedID = id
        boundUser?.equippedLicenseCosmeticId = id
        boundUser?.lastUpdated = .now
        FeedbackService.shared.selectionChange()
    }

    /// Ensures the bound user row matches the in-memory equipped id (e.g. before profile sync).
    func applyEquippedIDToBoundUser() {
        guard let boundUser else { return }
        if boundUser.equippedLicenseCosmeticId != equippedID {
            boundUser.equippedLicenseCosmeticId = equippedID
            boundUser.lastUpdated = .now
        }
    }

    // MARK: - Ownership

    /// Tryout ownership: unlock everything except prestige so the wallet is
    /// exercisable. Prestige (`founder`) stays locked until a real grant path exists.
    /// `rankLevel` is reserved for the eventual progression-gated ownership path.
    static func computeOwnedIDs(rankLevel: Int) -> Set<String> {
        _ = rankLevel
        var owned: Set<String> = []
        for cosmetic in LicenseCosmetic.catalog {
            if case .prestige = cosmetic.source { continue }
            owned.insert(cosmetic.id)
        }
        return owned
    }

    // MARK: - Persistence

    /// Prefer AppUser; one-time promote legacy UserDefaults into AppUser, then clear defaults.
    private func resolveEquippedID(for user: AppUser) -> String {
        if let fromUser = user.equippedLicenseCosmeticId, ownedIDs.contains(fromUser) {
            clearLegacyDefaults(for: user.id)
            return fromUser
        }

        let key = Self.equippedKey(userId: user.id)
        if let fromDefaults = defaults.string(forKey: key), ownedIDs.contains(fromDefaults) {
            user.equippedLicenseCosmeticId = fromDefaults
            user.lastUpdated = .now
            defaults.removeObject(forKey: key)
            return fromDefaults
        }

        let fallback = LicenseCosmetic.catalog[0].id
        if user.equippedLicenseCosmeticId == nil {
            user.equippedLicenseCosmeticId = fallback
            user.lastUpdated = .now
        }
        clearLegacyDefaults(for: user.id)
        return user.equippedLicenseCosmeticId.flatMap { ownedIDs.contains($0) ? $0 : nil } ?? fallback
    }

    private func clearLegacyDefaults(for userId: String) {
        defaults.removeObject(forKey: Self.equippedKey(userId: userId))
    }

    private static func equippedKey(userId: String) -> String {
        "licenseCosmetic.equipped.\(userId)"
    }
}
