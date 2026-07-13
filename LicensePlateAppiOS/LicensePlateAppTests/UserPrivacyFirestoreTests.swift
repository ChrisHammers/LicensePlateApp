//
//  UserPrivacyFirestoreTests.swift
//  LicensePlateAppTests
//

import Foundation
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
