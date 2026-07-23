//
//  AppUpdateGateServiceTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

private final class InMemorySoftDismissStorage: SoftDismissStorage {
    var fingerprint: String = ""
}

@MainActor
struct AppUpdateGateServiceTests {
    private let client = AppUpdateClientSnapshot(
        marketingVersion: "1.0.0",
        build: "10",
        clientCompat: 1,
        osMajor: 26,
        osMinor: 0,
        osPatch: 0
    )

    @Test func refreshHardSetsDecisionAndDoesNotPresentSoft() {
        let storage = InMemorySoftDismissStorage()
        let spy = AnalyticsLoggingSpy()
        var openedURLs: [URL] = []
        let gate = AppUpdateGateService(
            analytics: spy,
            softDismissStorage: storage,
            clientSnapshotProvider: { client },
            openURL: { openedURLs.append($0) }
        )

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
        gate.refresh(json: json)

        #expect(gate.decision.isHard)
        #expect(gate.shouldPresentSoftPrompt == false)
        #expect(spy.loggedEvents.contains { $0.name == "force_update_gate_shown" })

        gate.openStore()
        #expect(openedURLs.map(\.absoluteString) == ["https://apps.apple.com/app/id123"])
        #expect(spy.loggedEvents.contains { $0.name == "update_store_cta_tapped" })
    }

    @Test func softPromptHiddenAfterDismissForSameFingerprint() {
        let storage = InMemorySoftDismissStorage()
        let spy = AnalyticsLoggingSpy()
        let gate = AppUpdateGateService(
            analytics: spy,
            softDismissStorage: storage,
            clientSnapshotProvider: { client },
            openURL: { _ in }
        )

        let json = """
        {
          "schemaVersion": 1,
          "platforms": {
            "ios": {
              "soft": { "minMarketingVersion": "1.2.0" }
            }
          }
        }
        """
        gate.refresh(json: json)
        #expect(gate.shouldPresentSoftPrompt)
        #expect(spy.loggedEvents.contains { $0.name == "soft_update_prompt_shown" })

        gate.dismissSoft()
        #expect(gate.shouldPresentSoftPrompt == false)
        #expect(storage.fingerprint == "1.2.0#")
        #expect(spy.loggedEvents.contains { $0.name == "soft_update_prompt_dismissed" })

        gate.refresh(json: json)
        #expect(gate.shouldPresentSoftPrompt == false)
    }

    @Test func softRePromptsWhenFingerprintChanges() {
        let storage = InMemorySoftDismissStorage()
        storage.fingerprint = "1.1.0#"
        let spy = AnalyticsLoggingSpy()
        let gate = AppUpdateGateService(
            analytics: spy,
            softDismissStorage: storage,
            clientSnapshotProvider: { client },
            openURL: { _ in }
        )

        let json = """
        {
          "schemaVersion": 1,
          "platforms": {
            "ios": {
              "soft": { "minMarketingVersion": "1.2.0" }
            }
          }
        }
        """
        gate.refresh(json: json)
        #expect(gate.shouldPresentSoftPrompt)
    }

    @Test func emptyPolicyFailsOpen() {
        let gate = AppUpdateGateService(
            analytics: AnalyticsLoggingSpy(),
            softDismissStorage: InMemorySoftDismissStorage(),
            clientSnapshotProvider: { client },
            openURL: { _ in }
        )
        gate.refresh(json: "")
        #expect(gate.decision == .none)
        #expect(gate.shouldPresentSoftPrompt == false)
    }
}
