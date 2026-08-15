//
//  FR85ConsentedChildParityTests.swift
//  LicensePlateAppTests
//
//  COPPA FR-85 (F-42) — a consented child is a full member, not a second-class anonymous
//  session.
//
//  FR-60 made consented children ANONYMOUS Firebase accounts. The client resolves the base
//  tier from the auth provider (`AccountState.isGuestLike`), so a consented child fell to
//  `.guest` and silently lost the six `.signedUp` avatars they are entitled to. The grant is
//  a server-written `users/{uid}.entitlementTags` entry committed in the consent transaction
//  (`familyMembershipGrantUserUpdate`), which `EntitlementState.effectiveTier` reads as a
//  `.signedUp` floor.
//
//  The anti-spoof property under test is that the ONLY input is that server-controlled
//  array: `entitlementTags` is covered by the `firestore.rules` FR-7 diff-guard, so no client
//  write can add, change or remove it, and it reaches the app only via
//  `UserRepository.parseEntitlementTags` reading the document back. Nothing local — no
//  UserDefaults answer, no SwiftData row, not even `activeFamilyId` (which a client CAN
//  write on its own user doc) — participates in the decision.
//

import Foundation
import SwiftData
import Testing
@testable import LicensePlateApp

@MainActor
struct FR85ConsentedChildParityTests {

    private let tag = EntitlementState.signedUpEquivalentTag

    private func state(
        userTier: UserTier,
        tags: Set<String>,
        familyId: String? = nil,
        creatorTier: UserTier? = nil
    ) -> EntitlementState {
        EntitlementState(
            userTier: userTier,
            familyId: familyId,
            wasEverInFamily: familyId != nil,
            familyRole: familyId == nil ? nil : "scout",
            tags: tags,
            creatorTierForFamily: creatorTier
        )
    }

    // MARK: - The tier floor

    @Test func theGrantTagFloorsEffectiveTierAtSignedUp() {
        // The consented child as FR-60 leaves them: anonymous ⇒ base tier `.guest`.
        let child = state(userTier: .guest, tags: [tag], familyId: "fam1")
        #expect(child.userTier == .guest)
        #expect(child.effectiveTier == .signedUp)
    }

    @Test func aGuestWithoutTheTagIsUnchanged() {
        #expect(state(userTier: .guest, tags: []).effectiveTier == .guest)
        #expect(state(userTier: .guest, tags: ["founder"]).effectiveTier == .guest)
        #expect(state(userTier: .guest, tags: [], familyId: "fam1").effectiveTier == .guest)
    }

    @Test func theTagIsAFloorAndNeverACeiling() {
        // It can only raise a `.guest` to `.signedUp`; a paid tier is never pulled down,
        // and the family-creator elevation still wins when it is higher.
        #expect(state(userTier: .gold, tags: [tag]).effectiveTier == .gold)
        #expect(state(userTier: .royale, tags: [tag]).effectiveTier == .royale)
        #expect(
            state(userTier: .guest, tags: [tag], familyId: "fam1", creatorTier: .royale)
                .effectiveTier == .royale
        )
    }

    @Test func theTagDoesNotDependOnFamilyStateBeingPresentLocally() {
        // Sticky by design, exactly like `wasEverInFamily`: the roster cache may be empty
        // (offline, cold launch) without the child's avatars flickering back to locked.
        #expect(state(userTier: .guest, tags: [tag], familyId: nil).effectiveTier == .signedUp)
    }

    // MARK: - Avatar unlock (the visible symptom FR-85 names)

    @Test func everySignedUpAvatarUnlocksForAConsentedChild() {
        let service = EntitlementService(
            revenueCatBridge: MockRevenueCatBridge(tier: .guest),
            accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
        )
        let child = state(userTier: .guest, tags: [tag], familyId: "fam1")
        let guest = state(userTier: .guest, tags: [], familyId: "fam1")

        let signedUpAvatars = AvatarCatalog.allAvatars.filter { $0.unlockSource == .signedUp }
        #expect(signedUpAvatars.count == 6)

        for avatar in signedUpAvatars {
            #expect(service.isUnlocked(avatar: avatar, entitlement: child))
            #expect(!service.isUnlocked(avatar: avatar, entitlement: guest))
        }
    }

    @Test func theGrantUnlocksExactlyTheSignedUpTierAndNothingElse() {
        let service = EntitlementService(
            revenueCatBridge: MockRevenueCatBridge(tier: .guest),
            accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
        )
        // No familyId, so the sticky family unlock cannot mask the comparison.
        let child = state(userTier: .guest, tags: [tag])

        for source in AvatarUnlockSource.allCases {
            let probe = AvatarItem(id: "probe_\(source.rawValue)", displayName: "Probe", unlockSource: source)
            let expected = source == .guest || source == .signedUp
            #expect(
                service.isUnlocked(avatar: probe, entitlement: child) == expected,
                "\(source.rawValue) unlock state changed"
            )
        }
    }

    // MARK: - Provenance: the tag is server data, not a local flag

    @Test func theTagIsOnlyEverReadOutOfTheFirestoreUserDocument() {
        // `parseEntitlementTags` is the single ingress. A user doc that does not carry the
        // tag cannot produce it, whatever else the document (or the device) says.
        let consented: [String: Any] = [
            "userName": "Kid",
            "isChildAccount": true,
            "activeFamilyId": "fam1",
            "isRegistered": false,
            "entitlementTags": ["signedUpEquivalent"],
        ]
        #expect(UserRepository.parseEntitlementTags(from: consented).contains(tag))

        // The shape a modified client could produce locally — child flag plus a
        // self-written `activeFamilyId`, the one field of the pair rules let a client
        // write on its own doc — yields nothing.
        let forged: [String: Any] = [
            "userName": "Kid",
            "isChildAccount": true,
            "activeFamilyId": "fam1",
            "isRegistered": false,
        ]
        #expect(UserRepository.parseEntitlementTags(from: forged).isEmpty)
    }

    @Test func aConsentedChildResolvesSignedUpEndToEndFromTheIngestedDocument() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let child = AppUser(id: "kid", userName: "Kid", firebaseUID: "kid")
        context.insert(child)
        try context.save()

        let userRepo = UserRepository()
        userRepo.setModelContext(context)
        userRepo.ingestEntitlementTags(
            userId: "kid",
            tags: UserRepository.parseEntitlementTags(from: ["entitlementTags": ["signedUpEquivalent"]])
        )

        let service = EntitlementService(
            userRepository: userRepo,
            revenueCatBridge: MockRevenueCatBridge(tier: .guest),
            accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
        )
        service.setModelContext(context)
        service.setCurrentUserId("kid")

        let resolved = service.entitlementState(for: child)
        // Base tier still tells the truth — this account really is anonymous.
        #expect(resolved.userTier == .guest)
        #expect(resolved.effectiveTier == .signedUp)

        let catalog = AvatarCatalogService(entitlementService: service)
        let items = catalog.displayItems(for: child)
        let signedUp = items.filter { $0.unlockSource == .signedUp }
        #expect(!signedUp.isEmpty)
        #expect(signedUp.allSatisfy { $0.isUnlocked })
        // Paid tiers stay locked.
        #expect(items.filter { $0.unlockSource == .founder }.allSatisfy { !$0.isUnlocked })
    }

    @Test func anAnonymousAccountWithoutTheGrantStaysGuest() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let stranger = AppUser(id: "anon", userName: "Anon", firebaseUID: "anon")
        context.insert(stranger)
        try context.save()

        let userRepo = UserRepository()
        userRepo.setModelContext(context)

        let service = EntitlementService(
            userRepository: userRepo,
            revenueCatBridge: MockRevenueCatBridge(tier: .guest),
            accountStateProvider: StaticAccountStateProvider(.firebaseAnonymous)
        )
        service.setModelContext(context)
        service.setCurrentUserId("anon")

        let resolved = service.entitlementState(for: stranger)
        #expect(resolved.effectiveTier == .guest)
        let catalog = AvatarCatalogService(entitlementService: service)
        #expect(
            catalog.displayItems(for: stranger)
                .filter { $0.unlockSource == .signedUp }
                .allSatisfy { !$0.isUnlocked }
        )
    }

    @Test func theGrantIsClearedWithTheRestOfTheSessionOnPurge() {
        let userRepo = UserRepository()
        userRepo.ingestEntitlementTags(userId: "kid", tags: [tag])
        #expect(userRepo.entitlementTags(for: "kid").contains(tag))
        userRepo.clearEntitlementTags()
        #expect(userRepo.entitlementTags(for: "kid").isEmpty)
    }

    // MARK: - Blast radius: what the tier floor must NOT change

    @Test func theGrantDoesNotChangeAdEligibilityOrTripLimits() {
        let child = state(userTier: .guest, tags: [tag], familyId: "fam1")
        // Ads: eligibility is `< .gold`, so guest and signedUp are identical. Child
        // sessions are separately held by `ChildSessionPosture` (FR-17/FR-46) regardless.
        #expect(child.effectiveTier < .gold)
        // Active trips: the limit is 1 for both `.guest` and `.signedUp`.
        let gate = TripEntitlementGate(
            tripSessionRepository: MockTripSessionRepository(),
            entitlementService: EntitlementService(),
            analytics: AnalyticsLoggingSpy()
        )
        #expect(gate.activeTripLimit(for: child) == 1)
        #expect(gate.activeTripLimit(for: state(userTier: .guest, tags: [])) == 1)
    }
}
