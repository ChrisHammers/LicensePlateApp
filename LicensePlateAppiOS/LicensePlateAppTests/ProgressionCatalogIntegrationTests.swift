//
//  ProgressionCatalogIntegrationTests.swift
//  LicensePlateAppTests
//
//  Phase 7 — rank ladder parity, license card alignment, key achievement goals.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct ProgressionCatalogIntegrationTests {

    private let ladder = ProgressionCatalogProjection.rankLadder(from: .bundledDefault)

    @Test func coastToCoastGoalIsSixtyThreeRegions() throws {
        let entry = try #require(ProgressionCatalog.bundledDefault.achievements.first { $0.id == "coast_to_coast" })
        #expect(entry.goal == ProgressionCatalogLegacyParity.coastToCoastGoal)
    }

    @Test func rankLadderBoundaryAt999And1000() {
        #expect(ladder.currentRank(xp: 999).level == 1)
        #expect(ladder.currentRank(xp: 1_000).level == 2)
    }

    @Test func rankLadderBoundaryAt89999And90000() {
        #expect(ladder.currentRank(xp: 89_999).level == 7)
        #expect(ladder.currentRank(xp: 90_000).level == 8)
    }

    @Test func rankLadderBoundaryAt219999And220000() {
        #expect(ladder.currentRank(xp: 219_999).level == 9)
        #expect(ladder.currentRank(xp: 220_000).level == 10)
        #expect(ladder.nextRank(xp: 220_000) == nil)
    }

    @Test func rankLadderAt86400XpIsHighwayLegend() {
        #expect(ladder.currentRank(xp: 86_400).level == 7)
    }

    @Test func licenseCardAndLadderAgreeAt86400Xp() {
        let user = AppUser(id: "u1", userName: "Tester", firebaseUID: "u1")
        let license = UserDriversLicenseBuilder.make(
            from: ProfileLicenseInputs(user: user, totalXp: 86_400),
            catalogProvider: FixedProgressionCatalogProvider()
        )
        #expect(license.rankLevel == ladder.currentRank(xp: 86_400).level)
        #expect(license.userName == "Tester")
    }

    @Test func licenseCardAndLadderAgreeAt90000Xp() {
        let user = AppUser(id: "u1", userName: "Tester", firebaseUID: "u1")
        let license = UserDriversLicenseBuilder.make(
            from: ProfileLicenseInputs(user: user, totalXp: 90_000),
            catalogProvider: FixedProgressionCatalogProvider()
        )
        #expect(license.rankLevel == 8)
        #expect(license.rankLevel == ladder.currentRank(xp: 90_000).level)
    }

    @Test func rankProgressUsesMonotonicFraction() {
        let midRankXp = 20_000
        let progress = ladder.progress(xp: midRankXp)
        #expect(progress > 0)
        #expect(progress < 1)
    }
}

/// Test-only catalog provider pinned to bundled defaults.
private final class FixedProgressionCatalogProvider: ProgressionCatalogProviding, @unchecked Sendable {
    var current: ProgressionCatalog { .bundledDefault }
    func refresh(presentationOverrideJSON: String?, xpToastOverrideJSON: String?) {}
}
