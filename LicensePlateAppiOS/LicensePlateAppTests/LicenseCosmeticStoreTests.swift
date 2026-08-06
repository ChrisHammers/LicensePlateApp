//
//  LicenseCosmeticStoreTests.swift
//  LicensePlateAppTests
//
//  Equipped Explorers license cosmetic persists on AppUser (public profile field).
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct LicenseCosmeticStoreTests {

    @Test func equipWritesEquippedLicenseCosmeticIdOntoAppUser() {
        let userId = "license-cosmetic-equip-\(UUID().uuidString)"
        let user = AppUser(id: userId, userName: "Scout")
        let store = LicenseCosmeticStore.shared
        store.configure(user: user, rankLevel: 1)

        store.equip("gold")

        #expect(store.equippedID == "gold")
        #expect(user.equippedLicenseCosmeticId == "gold")
        #expect(LicenseCosmetic.first(user.equippedLicenseCosmeticId ?? "standard").id == "gold")
    }

    @Test func configureHydratesFromAppUserOverUserDefaults() {
        let userId = "license-cosmetic-hydrate-\(UUID().uuidString)"
        let defaultsKey = "licenseCosmetic.equipped.\(userId)"
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        UserDefaults.standard.set("neon", forKey: defaultsKey)
        let user = AppUser(id: userId, userName: "Scout", equippedLicenseCosmeticId: "platinum")
        let store = LicenseCosmeticStore.shared
        store.configure(user: user, rankLevel: 1)

        #expect(store.equippedID == "platinum")
        #expect(user.equippedLicenseCosmeticId == "platinum")
        #expect(UserDefaults.standard.string(forKey: defaultsKey) == nil)
    }

    @Test func configurePromotesLegacyUserDefaultsOntoAppUser() {
        let userId = "license-cosmetic-promote-\(UUID().uuidString)"
        let defaultsKey = "licenseCosmetic.equipped.\(userId)"
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        UserDefaults.standard.set("emerald", forKey: defaultsKey)
        let user = AppUser(id: userId, userName: "Scout", equippedLicenseCosmeticId: nil)
        let store = LicenseCosmeticStore.shared
        store.configure(user: user, rankLevel: 1)

        #expect(store.equippedID == "emerald")
        #expect(user.equippedLicenseCosmeticId == "emerald")
        #expect(UserDefaults.standard.string(forKey: defaultsKey) == nil)
    }

    @Test func peerStyleResolvesFromEquippedLicenseCosmeticId() {
        let user = AppUser(id: "peer", userName: "Peer", equippedLicenseCosmeticId: "summer")
        let resolved = LicenseCosmetic.first(user.equippedLicenseCosmeticId ?? "standard")
        #expect(resolved.id == "summer")
        #expect(resolved.id != LicenseCosmetic.first("standard").id)
    }

    @Test func licenseCosmeticEquippedAnalyticsEvent() {
        let event = AnalyticsService.Event.licenseCosmeticEquipped(cosmeticId: "gold", source: "profile")
        #expect(event.name == "license_cosmetic_equipped")
        #expect(event.parameters?["cosmetic_id"] as? String == "gold")
        #expect(event.parameters?["source"] as? String == "profile")
    }
}
