//
//  AuthProfileSyncPolicyTests.swift
//  LicensePlateAppTests
//
//  Covers auth restore rules A–D (hydrate-before-track, timestamp-only login write,
//  non-destructive contact merge, create-only-when-absent).
//

import Foundation
import Testing
@testable import LicensePlateApp

struct AuthProfileSyncPolicyTests {

    // MARK: - A + D bootstrap actions

    @Test func hydrateBeforeTrackWhenLocalAndCloudFound() {
        let action = AuthProfileSyncPolicy.bootstrapAction(hasLocalUser: true, load: .found)
        #expect(action == .applyCloudThenTrackLogin)
    }

    @Test func insertCloudBeforeTrackWhenNoLocalAndCloudFound() {
        let action = AuthProfileSyncPolicy.bootstrapAction(hasLocalUser: false, load: .found)
        #expect(action == .insertCloudThenTrackLogin)
    }

    @Test func createOnlyWhenCloudConfirmedAbsent() {
        let action = AuthProfileSyncPolicy.bootstrapAction(hasLocalUser: false, load: .notFound)
        #expect(action == .createLocalThenTrackLogin)
    }

    @Test func abortWithoutCreateWhenCloudReadFailsAndNoLocal() {
        let action = AuthProfileSyncPolicy.bootstrapAction(hasLocalUser: false, load: .failed)
        #expect(action == .abortWithoutCreate)
    }

    @Test func keepLocalWhenCloudReadFailsOrMissingWithLocalRow() {
        #expect(
            AuthProfileSyncPolicy.bootstrapAction(hasLocalUser: true, load: .failed)
                == .keepLocalThenTrackLogin
        )
        #expect(
            AuthProfileSyncPolicy.bootstrapAction(hasLocalUser: true, load: .notFound)
                == .keepLocalThenTrackLogin
        )
    }

    // MARK: - B login timestamp allowlist

    @Test func loginTrackingFieldKeysAreTimestampsOnly() {
        #expect(AuthProfileSyncPolicy.loginTimestampFieldKeys == [
            "lastDateLoggedIn",
            "lastUpdated",
        ])
        #expect(!AuthProfileSyncPolicy.loginTimestampFieldKeys.contains("userName"))
        #expect(!AuthProfileSyncPolicy.loginTimestampFieldKeys.contains("userNameLower"))
        #expect(!AuthProfileSyncPolicy.loginTimestampFieldKeys.contains("email"))
        #expect(!AuthProfileSyncPolicy.loginTimestampFieldKeys.contains("phoneNumber"))
        #expect(!AuthProfileSyncPolicy.loginTimestampFieldKeys.contains("firstName"))
    }

    // MARK: - FR-42 login-location removal

    @Test func loginTrackingFieldKeysCarryNoLocation() {
        for key in ["lastLoginLocation", "lastLoginLocations", "lastLoginLocationData", "latitude", "longitude"] {
            #expect(!AuthProfileSyncPolicy.loginTimestampFieldKeys.contains(key))
        }
    }

    @Test func applyCloudProfileNeverHydratesLoginLocation() {
        let local = AppUser(id: "uid-loc", userName: "Local", firebaseUID: "uid-loc")
        let cloud = AppUser(id: "uid-loc", userName: "Cloud", firebaseUID: "uid-loc")
        cloud.lastLoginLocation = [
            LoginLocation(latitude: 41.76, longitude: -72.68, timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        ]

        AuthProfileSyncPolicy.applyCloudProfile(cloud, to: local, isAnonymous: false)

        #expect(local.userName == "Cloud")
        #expect(local.lastLoginLocation.isEmpty)
    }

    // MARK: - A hydrate merge

    @Test func applyCloudProfileOverwritesGuestUsernameAndHydratesContact() {
        let local = AppUser(
            id: "uid-1",
            userName: "UserC99A0A714496",
            firstName: nil,
            lastName: nil,
            email: nil,
            phoneNumber: nil,
            isUsernameManuallyChanged: false,
            firebaseUID: "uid-1",
            needsSync: true
        )
        let cloud = AppUser(
            id: "uid-1",
            userName: "JohnEFeelGood",
            firstName: "John",
            lastName: "Good",
            email: "johnefeelgood@gmail.com",
            phoneNumber: "2035551111",
            isUsernameManuallyChanged: true,
            firebaseUID: "uid-1"
        )
        cloud.avatarId = "cat"
        cloud.equippedLicenseCosmeticId = "gold"
        cloud.isEmailPublic = true
        cloud.isPhonePublic = false

        let syncedAt = Date(timeIntervalSince1970: 1_700_000_000)
        AuthProfileSyncPolicy.applyCloudProfile(cloud, to: local, isAnonymous: false, syncedAt: syncedAt)

        #expect(local.userName == "JohnEFeelGood")
        // F-6 rework: real names are never hydrated, even when a legacy cloud doc carries them.
        #expect(local.firstName == nil)
        #expect(local.lastName == nil)
        #expect(local.email == "johnefeelgood@gmail.com")
        #expect(local.phoneNumber == "2035551111")
        #expect(local.isUsernameManuallyChanged == true)
        #expect(local.avatarId == "cat")
        #expect(local.equippedLicenseCosmeticId == "gold")
        #expect(local.isEmailPublic == true)
        #expect(local.isPhonePublic == false)
        #expect(local.needsSync == false)
        #expect(local.lastSyncedToFirebase == syncedAt)
    }

    @Test func applyCloudProfileCopiesEquippedLicenseCosmeticId() {
        let local = AppUser(id: "uid-2", userName: "Local", equippedLicenseCosmeticId: "standard")
        let cloud = AppUser(id: "uid-2", userName: "Cloud", equippedLicenseCosmeticId: "neon")

        AuthProfileSyncPolicy.applyCloudProfile(cloud, to: local, isAnonymous: false)

        #expect(local.equippedLicenseCosmeticId == "neon")
    }

    @Test func applyCloudProfileSkipsEmailForAnonymous() {
        let local = AppUser(
            id: "uid-anon",
            userName: "GuestLocal",
            email: nil,
            firebaseUID: "uid-anon"
        )
        let cloud = AppUser(
            id: "uid-anon",
            userName: "CloudName",
            email: "should-not-apply@example.com",
            firebaseUID: "uid-anon"
        )

        AuthProfileSyncPolicy.applyCloudProfile(cloud, to: local, isAnonymous: true)

        #expect(local.userName == "CloudName")
        #expect(local.email == nil)
    }
}

struct AuthProfileContactMergeTests {
    // MARK: - C non-destructive contact

    @Test func privateContactMergeOmitsNilAndDoesNotWriteNullSentinels() {
        #expect(ContactSearchNormalization.privateContactMergeFields(email: nil, phoneNumber: nil) == nil)

        let emailOnly = ContactSearchNormalization.privateContactMergeFields(
            email: "user@example.com",
            phoneNumber: nil
        )
        #expect(emailOnly?.keys.sorted() == ["email", "emailLower"])
        #expect(emailOnly?["email"] == "user@example.com")

        let both = ContactSearchNormalization.privateContactMergeFields(
            email: "user@example.com",
            phoneNumber: "2035551111"
        )
        #expect(both?["email"] == "user@example.com")
        #expect(both?["phoneNumber"] == "2035551111")
        #expect(both?["phoneE164"] == "+12035551111")
    }
}

@MainActor
struct AuthProfileHydrateAnalyticsTests {
    @Test func authProfileHydrateFailedEventNameAndParams() {
        let keepLocal = AnalyticsService.Event.authProfileHydrateFailed(outcome: "keep_local")
        #expect(keepLocal.name == "auth_profile_hydrate_failed")
        #expect(keepLocal.parameters?["outcome"] as? String == "keep_local")

        let abort = AnalyticsService.Event.authProfileHydrateFailed(outcome: "abort_no_create")
        #expect(abort.name == "auth_profile_hydrate_failed")
        #expect(abort.parameters?["outcome"] as? String == "abort_no_create")
    }
}
