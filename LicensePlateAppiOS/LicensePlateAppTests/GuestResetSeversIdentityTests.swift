//
//  GuestResetSeversIdentityTests.swift
//  LicensePlateAppTests
//
//  SRS §3.1.1 item 8 (owner-found repeatedly; root-caused 2026-09-07): choosing "Continue as
//  Guest" over a restored account reset the local row IN PLACE, leaving it addressable by the
//  old account's uid (`id == firebaseUID` for cloud rows). `UserRepository.cacheUsers` upserts
//  by id, so the next peer-profile refresh that included that account rewrote the "fresh
//  guest" back into it. A reset guest must be unreachable by the old uid.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct GuestResetSeversIdentityTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        return ModelContext(container)
    }

    @Test func resetGuestIsNoLongerAddressableByTheOldAccount() throws {
        let ctx = try makeContext()
        let auth = FirebaseAuthService()
        auth.setModelContext(ctx)

        let restored = AppUser(
            id: "old-uid-chrishamm",
            userName: "ChrisHamm",
            email: "chris@example.com",
            deviceIdentifier: "device",
            isUsernameManuallyChanged: true,
            firebaseUID: "old-uid-chrishamm"
        )
        restored.avatarId = "avatar_chris"
        ctx.insert(restored)
        try ctx.save()
        auth.currentUser = restored

        try auth.resetLocalUserToGuest()

        // Identity fields are gone, and the generated name is not the old one.
        #expect(restored.firebaseUID == nil)
        #expect(restored.email == nil)
        #expect(restored.userName != "ChrisHamm")
        #expect(restored.isUsernameManuallyChanged == false)
        #expect(restored.avatarId != nil)

        // The row can no longer be found by the old account's uid — so a peer-profile
        // merge for that uid cannot land on the guest.
        let oldId = "old-uid-chrishamm"
        let byId = try ctx.fetch(FetchDescriptor<AppUser>(predicate: #Predicate { $0.id == oldId }))
        let byUid = try ctx.fetch(FetchDescriptor<AppUser>(predicate: #Predicate { $0.firebaseUID == oldId }))
        #expect(byId.isEmpty)
        #expect(byUid.isEmpty)
        #expect(auth.currentUser?.id != oldId)
    }
}
