//
//  RankProgressPendingStateTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

struct RankProgressPendingStateTests {

    @Test func noUnlockCelebrationFromPendingAlone() {
        let boundary = 100
        let serverXp = 40
        let pending = 80
        let prev = 30
        #expect(RankProgressPresentation.wouldCrossBoundaryFromPendingOnly(
            serverXp: serverXp,
            pendingXp: pending,
            tierBoundary: boundary
        ))
        #expect(!RankProgressPresentation.shouldCelebrateTierUnlock(
            serverXp: serverXp,
            previousServerXp: prev,
            tierBoundary: boundary
        ))
    }

    @Test func unlockCelebrationWhenServerCrossesBoundary() {
        let boundary = 100
        #expect(RankProgressPresentation.shouldCelebrateTierUnlock(
            serverXp: 105,
            previousServerXp: 90,
            tierBoundary: boundary
        ))
    }
}
