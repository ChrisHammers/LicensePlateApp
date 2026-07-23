//
//  AppUpdatePolicyEvaluatorTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct AppUpdatePolicyEvaluatorTests {
    private let baseClient = AppUpdateClientSnapshot(
        marketingVersion: "1.0.0",
        build: "10",
        clientCompat: 1,
        osMajor: 26,
        osMinor: 0,
        osPatch: 0
    )

    @Test func emptyJSONFailsOpen() {
        let decision = AppUpdatePolicyEvaluator.evaluate(json: "", client: baseClient)
        #expect(decision == .none)
    }

    @Test func invalidJSONFailsOpen() {
        let decision = AppUpdatePolicyEvaluator.evaluate(json: "{not-json", client: baseClient)
        #expect(decision == .none)
    }

    @Test func hardBlocksWhenClientCompatTooLow() {
        let json = """
        {
          "schemaVersion": 1,
          "platforms": {
            "ios": {
              "storeUrl": "https://apps.apple.com/app/id123",
              "hard": { "minClientCompat": 2 }
            }
          }
        }
        """
        let decision = AppUpdatePolicyEvaluator.evaluate(json: json, client: baseClient)
        #expect(decision.isHard)
        #expect(decision.storeURL?.absoluteString == "https://apps.apple.com/app/id123")
    }

    @Test func hardBlocksWhenMarketingVersionTooLow() {
        let json = """
        {
          "schemaVersion": 1,
          "platforms": {
            "ios": {
              "hard": { "minMarketingVersion": "1.2.0" }
            }
          }
        }
        """
        let decision = AppUpdatePolicyEvaluator.evaluate(json: json, client: baseClient)
        #expect(decision.isHard)
    }

    @Test func hardBlocksWhenBuildTooLow() {
        let json = """
        {
          "schemaVersion": 1,
          "platforms": {
            "ios": {
              "hard": { "minBuild": 50 }
            }
          }
        }
        """
        let decision = AppUpdatePolicyEvaluator.evaluate(json: json, client: baseClient)
        #expect(decision.isHard)
    }

    @Test func osCapClampsVersionFloorSoOSLockedClientPasses() {
        // Policy asks for 1.2.0, but osCap for OS < 27 caps requirement at 1.0.0.
        let json = """
        {
          "schemaVersion": 1,
          "platforms": {
            "ios": {
              "hard": { "minMarketingVersion": "1.2.0" },
              "osCaps": [
                {
                  "maxOsVersionExclusive": "27.0",
                  "maxRequiredMarketingVersion": "1.0.0",
                  "maxRequiredBuild": 10
                }
              ]
            }
          }
        }
        """
        let decision = AppUpdatePolicyEvaluator.evaluate(json: json, client: baseClient)
        #expect(decision == .none)
    }

    @Test func osCapDoesNotWaiveMinClientCompat() {
        let json = """
        {
          "schemaVersion": 1,
          "platforms": {
            "ios": {
              "hard": { "minClientCompat": 2, "minMarketingVersion": "1.2.0" },
              "osCaps": [
                {
                  "maxOsVersionExclusive": "27.0",
                  "maxRequiredMarketingVersion": "1.0.0"
                }
              ]
            }
          }
        }
        """
        let decision = AppUpdatePolicyEvaluator.evaluate(json: json, client: baseClient)
        #expect(decision.isHard)
    }

    @Test func softWhenBelowSoftFloorsOnly() {
        let json = """
        {
          "schemaVersion": 1,
          "platforms": {
            "ios": {
              "storeUrl": "https://apps.apple.com/app/id123",
              "soft": { "minMarketingVersion": "1.2.0" }
            }
          }
        }
        """
        let decision = AppUpdatePolicyEvaluator.evaluate(json: json, client: baseClient)
        #expect(decision.isSoft)
    }

    @Test func hardTakesPrecedenceOverSoft() {
        let json = """
        {
          "schemaVersion": 1,
          "platforms": {
            "ios": {
              "hard": { "minClientCompat": 2 },
              "soft": { "minMarketingVersion": "1.2.0" }
            }
          }
        }
        """
        let decision = AppUpdatePolicyEvaluator.evaluate(json: json, client: baseClient)
        #expect(decision.isHard)
    }

    @Test func meetsFloorsReturnsNone() {
        let json = """
        {
          "schemaVersion": 1,
          "platforms": {
            "ios": {
              "hard": { "minClientCompat": 1, "minMarketingVersion": "1.0.0", "minBuild": 10 },
              "soft": { "minMarketingVersion": "1.0.0" }
            }
          }
        }
        """
        let decision = AppUpdatePolicyEvaluator.evaluate(json: json, client: baseClient)
        #expect(decision == .none)
    }

    @Test func softFingerprintStable() {
        let floors = AppUpdatePolicy.VersionFloors(
            minClientCompat: nil,
            minMarketingVersion: "1.2.0",
            minBuild: 45
        )
        #expect(VersionCompare.softFingerprint(floors: floors) == "1.2.0#45")
        #expect(VersionCompare.softFingerprint(floors: nil) == "#")
    }

    @Test func semverCompareOrdersComponents() {
        #expect(VersionCompare.compareMarketing("1.0.0", "1.0.1") == .orderedAscending)
        #expect(VersionCompare.compareMarketing("1.2", "1.2.0") == .orderedSame)
        #expect(VersionCompare.compareMarketing("2.0.0", "1.9.9") == .orderedDescending)
    }
}
