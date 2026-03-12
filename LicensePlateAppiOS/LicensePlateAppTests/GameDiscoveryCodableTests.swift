//
//  GameDiscoveryCodableTests.swift
//  LicensePlateAppTests
//
//  Step 11.6 — Codable round-trip for GameDiscovery and riskFlags; source-of-truth and legacy compatibility.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct GameDiscoveryCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func makeDiscovery(
        id: String = UUID().uuidString,
        riskFlags: [RiskFlag]? = nil,
        riskFlag: String? = nil
    ) -> GameDiscovery {
        GameDiscovery(
            id: id,
            gameInstanceId: UUID(),
            participantId: "user1",
            targetId: "us-ca",
            discoveredAt: Date(),
            inputMethod: .list,
            location: nil,
            riskFlag: riskFlag,
            riskFlags: riskFlags
        )
    }

    private func makeRiskFlag(
        type: RiskFlagType = .duplicateDiscovery,
        severity: RiskSeverity = .notice,
        metadata: RiskFlagMetadata = RiskFlagMetadata()
    ) -> RiskFlag {
        RiskFlag(
            type: type,
            severity: severity,
            source: .localHeuristic,
            presentationKey: "risk.test",
            metadata: metadata
        )
    }

    @Test func discoveryWithZeroFlagsPersistsAndReloads() async throws {
        let discovery = makeDiscovery(riskFlags: nil)
        let data = try encoder.encode(discovery)
        let decoded = try decoder.decode(GameDiscovery.self, from: data)
        #expect(decoded.riskFlags == nil || decoded.riskFlags?.isEmpty == true)
        #expect(decoded.highestRiskSeverity == nil)
        #expect(decoded.riskFlagCount == 0)
    }

    @Test func discoveryWithOneFlagPersistsAndReloads() async throws {
        let flag = makeRiskFlag(severity: .notice, metadata: RiskFlagMetadata(burstCount: 5))
        let discovery = makeDiscovery(riskFlags: [flag])
        let data = try encoder.encode(discovery)
        let decoded = try decoder.decode(GameDiscovery.self, from: data)
        #expect(decoded.riskFlags?.count == 1)
        #expect(decoded.riskFlags?[0].type == .duplicateDiscovery)
        #expect(decoded.riskFlags?[0].severity == .notice)
        #expect(decoded.riskFlags?[0].metadata.burstCount == 5)
        #expect(decoded.highestRiskSeverity == .notice)
        #expect(decoded.riskFlagCount == 1)
    }

    @Test func discoveryWithMultipleFlagsPersistsAndReloads() async throws {
        let flags = [
            makeRiskFlag(severity: .notice),
            makeRiskFlag(type: .burstInputPattern, severity: .warning),
            makeRiskFlag(type: .suspiciousToggleLoop, severity: .review)
        ]
        let discovery = makeDiscovery(riskFlags: flags)
        let data = try encoder.encode(discovery)
        let decoded = try decoder.decode(GameDiscovery.self, from: data)
        #expect(decoded.riskFlags?.count == 3)
        #expect(decoded.highestRiskSeverity == .review)
        #expect(decoded.riskFlagCount == 3)
        #expect(decoded.hasReviewLevelRisk == true)
    }

    @Test func riskFlagMetadataSurvivesRoundTrip() async throws {
        let flag = makeRiskFlag(
            type: .burstInputPattern,
            metadata: RiskFlagMetadata(burstCount: 12, toggleLoopCount: 4)
        )
        let discovery = makeDiscovery(riskFlags: [flag])
        let data = try encoder.encode(discovery)
        let decoded = try decoder.decode(GameDiscovery.self, from: data)
        #expect(decoded.riskFlags?.first?.metadata.burstCount == 12)
        #expect(decoded.riskFlags?.first?.metadata.toggleLoopCount == 4)
    }

    @Test func legacyFriendlyDecodeMissingRiskFlagsKey() async throws {
        var discovery = makeDiscovery(riskFlags: nil)
        discovery.riskFlag = "legacy_string"
        let data = try encoder.encode(discovery)
        let decoded = try decoder.decode(GameDiscovery.self, from: data)
        #expect(decoded.riskFlags == nil)
        #expect(decoded.riskFlagCount == 0)
        #expect(decoded.highestRiskSeverity == nil)
    }

    /// Legacy-adapted discoveries may not have discovery-linked risk history; payloads without riskFlags must decode safely.
    @Test func legacyPayloadWithoutRiskFlagsKeyDecodesSafely() async throws {
        let discovery = makeDiscovery(riskFlags: nil)
        var data = try encoder.encode(discovery)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "riskFlags")
        data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(GameDiscovery.self, from: data)
        #expect(decoded.id == discovery.id)
        #expect(decoded.riskFlags == nil)
        #expect(decoded.riskFlagCount == 0)
    }

    @Test func sourceOfTruthRiskFlagsPreferredOverLegacyField() async throws {
        let flag = makeRiskFlag(severity: .warning)
        var discovery = makeDiscovery(riskFlags: [flag], riskFlag: "legacy_override")
        let data = try encoder.encode(discovery)
        let decoded = try decoder.decode(GameDiscovery.self, from: data)
        #expect(decoded.riskFlags?.count == 1)
        #expect(decoded.highestRiskSeverity == .warning)
        #expect(decoded.riskFlagCount == 1)
    }
}
