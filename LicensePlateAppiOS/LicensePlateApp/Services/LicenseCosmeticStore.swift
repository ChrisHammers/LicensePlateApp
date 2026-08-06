//
//  LicenseCosmeticStore.swift
//  LicensePlateApp
//
//  Local equip + ownership for Explorer license skins.
//  Persistence is UserDefaults (no SwiftData schema change) so the wallet can be tried
//  without cloud sync. Replace with entitlement/progression grants when shipping.
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
    private let defaults = UserDefaults.standard

    private init() {}

    /// Bind store to the signed-in user and recompute ownership from rank.
    func configure(userId: String, rankLevel: Int) {
        let normalizedRank = max(1, rankLevel)
        let userChanged = self.userId != userId
        self.userId = userId
        ownedIDs = Self.computeOwnedIDs(rankLevel: normalizedRank)
        if userChanged {
            equippedID = loadEquippedID(for: userId)
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
        guard equippedID != id else { return }
        equippedID = id
        if let userId {
            defaults.set(id, forKey: Self.equippedKey(userId: userId))
        }
        FeedbackService.shared.selectionChange()
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

    private func loadEquippedID(for userId: String) -> String {
        let stored = defaults.string(forKey: Self.equippedKey(userId: userId))
        if let stored, ownedIDs.contains(stored) {
            return stored
        }
        return LicenseCosmetic.catalog[0].id
    }

    private static func equippedKey(userId: String) -> String {
        "licenseCosmetic.equipped.\(userId)"
    }
}
