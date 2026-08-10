//
//  UserPrivacyFirestoreTests.swift
//  LicensePlateAppTests
//

import Foundation
import FirebaseFirestore
import Testing
@testable import LicensePlateApp

struct UserPrivacyFirestoreTests {
    @Test func encodeWritesSearchableKeys() {
        let encoded = UserPrivacyFirestore.encode(isEmailPublic: true, isPhonePublic: false)
        #expect(encoded["emailSearchable"] == true)
        #expect(encoded["phoneSearchable"] == false)
    }

    @Test func decodePrefersPrivacyMap() {
        let data: [String: Any] = [
            "privacy": [
                "emailSearchable": true,
                "phoneSearchable": true
            ],
            "isEmailPublic": false,
            "isPhonePublic": false
        ]
        let decoded = UserPrivacyFirestore.decode(from: data)
        #expect(decoded.isEmailPublic == true)
        #expect(decoded.isPhonePublic == true)
    }

    @Test func decodeFallsBackToLegacyTopLevel() {
        let data: [String: Any] = [
            "isEmailPublic": true,
            "isPhonePublic": false
        ]
        let decoded = UserPrivacyFirestore.decode(from: data)
        #expect(decoded.isEmailPublic == true)
        #expect(decoded.isPhonePublic == false)
    }

    @Test func decodeDefaultsToFalseWhenMissing() {
        let decoded = UserPrivacyFirestore.decode(from: [:])
        #expect(decoded.isEmailPublic == false)
        #expect(decoded.isPhonePublic == false)
    }
}

/// FR-43 / audit E1: contact identifiers must never reach the peer-readable users/{uid} doc.
struct LinkedPlatformFirestoreTests {
    private let google = LinkedPlatform(
        platform: .google,
        platformUserId: "google-uid-1",
        linkedAt: Date(timeIntervalSince1970: 1_700_000_000),
        email: "kid@example.com",
        phoneNumber: "+15551234567",
        displayName: "Kid Example"
    )

    private let apple = LinkedPlatform(
        platform: .apple,
        platformUserId: "apple-uid-1",
        linkedAt: Date(timeIntervalSince1970: 1_700_000_100),
        email: nil,
        phoneNumber: nil,
        displayName: nil
    )

    @Test func publicEntriesKeepIdentityOnly() {
        let entries = LinkedPlatformFirestore.publicEntries(from: [google, apple])

        #expect(entries.count == 2)
        for entry in entries {
            #expect(Set(entry.keys) == LinkedPlatformFirestore.publicEntryKeys)
            #expect(Set(entry.keys).isDisjoint(with: LinkedPlatformFirestore.contactEntryKeys))
        }
        #expect(entries[0]["platform"] as? String == "Google")
        #expect(entries[0]["platformUserId"] as? String == "google-uid-1")
        #expect(entries[0]["linkedAt"] is Timestamp)
    }

    @Test func publicEntriesLeakNoContactValues() {
        let entries = LinkedPlatformFirestore.publicEntries(from: [google])
        let flattened = entries.flatMap { $0.values.map { String(describing: $0) } }.joined(separator: "|")

        #expect(!flattened.contains("kid@example.com"))
        #expect(!flattened.contains("+15551234567"))
        #expect(!flattened.contains("Kid Example"))
    }

    @Test func privateContactEntriesCarryContactPlusIdentityKey() throws {
        let entries = try #require(LinkedPlatformFirestore.privateContactEntries(from: [google, apple]))

        // Only the platform that actually has contact data produces a row.
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry["platform"] as? String == "Google")
        #expect(entry["platformUserId"] as? String == "google-uid-1")
        #expect(entry["email"] as? String == "kid@example.com")
        #expect(entry["phoneNumber"] as? String == "+15551234567")
        #expect(entry["displayName"] as? String == "Kid Example")
    }

    @Test func privateContactEntriesAreNilWhenNothingToWrite() {
        #expect(LinkedPlatformFirestore.privateContactEntries(from: []) == nil)
        #expect(LinkedPlatformFirestore.privateContactEntries(from: [apple]) == nil)

        let blank = LinkedPlatform(
            platform: .google,
            platformUserId: "google-uid-1",
            linkedAt: .now,
            email: "",
            phoneNumber: "",
            displayName: ""
        )
        #expect(LinkedPlatformFirestore.privateContactEntries(from: [blank]) == nil)
    }

    @Test func mergingRehydratesOwnerContactFromPrivateDoc() throws {
        let publicOnly = LinkedPlatform(
            platform: .google,
            platformUserId: "google-uid-1",
            linkedAt: google.linkedAt,
            email: nil,
            phoneNumber: nil,
            displayName: nil
        )
        let privateEntries = try #require(LinkedPlatformFirestore.privateContactEntries(from: [google]))

        let merged = LinkedPlatformFirestore.merging([publicOnly, apple], privateEntries: privateEntries)

        #expect(merged.count == 2)
        #expect(merged[0].email == "kid@example.com")
        #expect(merged[0].phoneNumber == "+15551234567")
        #expect(merged[0].displayName == "Kid Example")
        // Untouched platform stays contact-free.
        #expect(merged[1].email == nil)
        #expect(merged[1].displayName == nil)
    }

    @Test func mergingIsANoOpWithoutPrivateEntries() {
        #expect(LinkedPlatformFirestore.merging([google], privateEntries: nil).count == 1)
        #expect(LinkedPlatformFirestore.merging([google], privateEntries: []).first?.email == "kid@example.com")
    }

    @Test func mergingNeverDowngradesLocalContact() {
        let staleEntries: [[String: Any]] = [[
            "platform": "Google",
            "platformUserId": "google-uid-1",
            "email": "stale@example.com"
        ]]

        let merged = LinkedPlatformFirestore.merging([google], privateEntries: staleEntries)
        #expect(merged[0].email == "kid@example.com")
    }
}

struct UserSearchInviteMethodTests {
    @Test func inviteMethodMapsMatchFieldForCloudFunctionGates() {
        #expect(UserRepository.UserSearchResult.MatchField.username.inviteMethod == "search")
        #expect(UserRepository.UserSearchResult.MatchField.email.inviteMethod == "search")
        #expect(UserRepository.UserSearchResult.MatchField.phone.inviteMethod == "search")
    }
}
