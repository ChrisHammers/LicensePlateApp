//
//  XpUniquenessKeyTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct XpUniquenessKeyTests {

    @Test func storageStringDeterministic() {
        let sid = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let gid = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let k1 = XpUniquenessKey(
            userId: "alice",
            sessionId: sid,
            gameInstanceId: gid,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        )
        let k2 = XpUniquenessKey(
            userId: "alice",
            sessionId: sid,
            gameInstanceId: gid,
            itemId: "TX",
            xpCategory: .baseRegionDiscovery
        )
        #expect(k1.storageString == k2.storageString)
        #expect(k1.storageString == XpLedgerKeyBuilder.canonicalStorageString(from: k1))
    }

    @Test func differentCategoryChangesKey() {
        let sid = UUID()
        let gid = UUID()
        let a = XpUniquenessKey(userId: "u", sessionId: sid, gameInstanceId: gid, itemId: "CA", xpCategory: .baseRegionDiscovery)
        let b = XpUniquenessKey(userId: "u", sessionId: sid, gameInstanceId: gid, itemId: "CA", xpCategory: .tripCompletion)
        #expect(a.storageString != b.storageString)
    }
}
