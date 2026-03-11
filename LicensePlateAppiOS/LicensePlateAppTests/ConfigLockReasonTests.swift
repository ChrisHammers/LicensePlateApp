//
//  ConfigLockReasonTests.swift
//  LicensePlateAppTests
//
//  Step 07.5 — ConfigLockReason enum and serialization for analytics.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ConfigLockReasonTests {

    @Test func allCasesCoverRequiredValues() async throws {
        let cases = ConfigLockReason.allCases
        #expect(cases.contains(.none))
        #expect(cases.contains(.userLocked))
        #expect(cases.contains(.gameStarted))
        #expect(cases.contains(.eventEnforced))
        #expect(cases.contains(.challengeRule))
        #expect(cases.contains(.systemMigration))
    }

    @Test func roundTripEncodingForAnalytics() async throws {
        for reason in ConfigLockReason.allCases {
            let encoded = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(ConfigLockReason.self, from: encoded)
            #expect(decoded == reason)
        }
    }
}
