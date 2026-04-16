//
//  PublicLifetimeStatsCachePolicyTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct PublicLifetimeStatsCachePolicyTests {

    @Test func evictsNothingWhenAlreadyObservingIncomingFriend() {
        let victims = PublicLifetimeStatsCachePolicy.friendUserIdsToEvict(
            observedFriendIds: ["a", "b"],
            accessRecords: [
                (userId: "a", lastAccessedAt: Date(timeIntervalSince1970: 100)),
                (userId: "b", lastAccessedAt: Date(timeIntervalSince1970: 200)),
            ],
            incomingUserId: "a"
        )
        #expect(victims.isEmpty)
    }

    @Test func evictsOldestWhenOverCap() {
        let t0 = Date(timeIntervalSince1970: 0)
        let friends = Set((0..<50).map { "u\($0)" })
        var records: [(String, Date)] = []
        // Deterministic ordering: Set enumeration order is undefined, so assign
        // lastAccessedAt by stable friend id (u0 oldest, u49 newest).
        for i in 0..<50 {
            let uid = "u\(i)"
            records.append((uid, t0.addingTimeInterval(TimeInterval(i))))
        }
        let victims = PublicLifetimeStatsCachePolicy.friendUserIdsToEvict(
            observedFriendIds: friends,
            accessRecords: records,
            incomingUserId: "new"
        )
        #expect(victims.count == 1)
        #expect(victims[0] == "u0")
    }
}
