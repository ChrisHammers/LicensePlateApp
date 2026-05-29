//
//  XpLedgerEventTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct XpLedgerEventTests {

    @Test func codableRoundTrip() throws {
        let original = XpLedgerEvent(
            id: "xp-1",
            userId: "u1",
            sessionId: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            gameInstanceId: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!,
            sourceEventId: "evt-1",
            sourceEventType: "region_found",
            itemId: "CA",
            grantKind: .provisionalDiscoveryXp,
            status: .provisional,
            xpDelta: 10,
            reasonCode: .discoveryClaimPendingResolution,
            xpUniquenessKey: "xp|v1|u1|aa|bb|CA|base_region_discovery",
            metadata: ["inputMethod": "list", "gameMode": "competitive"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(XpLedgerEvent.self, from: data)
        #expect(decoded == original)
    }

    @Test func metadataEncodeDecodeViaMapper() {
        let meta = ["k": "v", "x": "y"]
        let data = XpLedgerMapper.encodeMetadata(meta)
        #expect(XpLedgerMapper.decodeMetadata(data) == meta)
        #expect(XpLedgerMapper.decodeMetadata(nil) == nil)
    }
}
