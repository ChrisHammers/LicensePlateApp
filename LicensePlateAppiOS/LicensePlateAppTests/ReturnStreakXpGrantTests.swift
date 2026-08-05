//
//  ReturnStreakXpGrantTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
private final class ReturnStreakRemoteConfigStub: RemoteConfigValueProviding {
    var returnStreakEnabled = true

    func bool(for key: RemoteConfigService.Key) -> Bool {
        switch key {
        case .returnStreakEnabled: return returnStreakEnabled
        default: return false
        }
    }

    func int(for key: RemoteConfigService.Key) -> Int { 1 }
    func string(for key: RemoteConfigService.Key) -> String { "" }
}

@MainActor
struct ReturnStreakXpGrantTests {

    @Test func dayOneDoesNotAppendStreakXpLedgerRow() throws {
        let remote = ReturnStreakRemoteConfigStub()
        let ledger = MockXpLedgerRepository()
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 12))!
        let service = ReturnStreakService(
            remoteConfig: remote,
            calendar: calendar,
            now: { now },
            xpLedger: ledger,
            catalogProvider: ProgressionCatalogProvider()
        )

        let outcome = service.recordQualifyingFindIfNeeded(userId: "u1")
        #expect(outcome == .started(currentStreak: 1))
        #expect(try ledger.ledgerEvents(userId: "u1").isEmpty)
    }

    @Test func dayTwoAppendsIdempotentStreakXpLedgerRow() throws {
        let remote = ReturnStreakRemoteConfigStub()
        let ledger = MockXpLedgerRepository()
        let calendar = Calendar(identifier: .gregorian)
        var now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 12))!
        let service = ReturnStreakService(
            remoteConfig: remote,
            calendar: calendar,
            now: { now },
            xpLedger: ledger,
            catalogProvider: ProgressionCatalogProvider()
        )

        #expect(service.recordQualifyingFindIfNeeded(userId: "u1") == .started(currentStreak: 1))
        #expect(try ledger.ledgerEvents(userId: "u1").isEmpty)

        now = calendar.date(byAdding: .day, value: 1, to: now)!
        let continued = service.recordQualifyingFindIfNeeded(userId: "u1")
        #expect(continued == .continued(previousStreak: 1, currentStreak: 2))

        let rows = try ledger.ledgerEvents(userId: "u1")
        #expect(rows.count == 1)
        #expect(rows[0].reasonCode == .returnStreakDaily)
        #expect(rows[0].xpDelta == ProgressionCatalog.bundledDefault.xpToastGroup(id: "return_streak")?.xpReward)
        #expect(rows[0].metadata?[XpLedgerMetadataKey.returnStreakDayCount] == "2")

        let duplicate = service.recordQualifyingFindIfNeeded(userId: "u1")
        #expect(duplicate == .noOp(alreadyQualifiedToday: true))
        #expect(try ledger.ledgerEvents(userId: "u1").count == 1)
    }

    @Test func brokenRestartDoesNotGrantUntilSecondConsecutiveDay() throws {
        let remote = ReturnStreakRemoteConfigStub()
        let ledger = MockXpLedgerRepository()
        let calendar = Calendar(identifier: .gregorian)
        var now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 12))!
        let service = ReturnStreakService(
            remoteConfig: remote,
            calendar: calendar,
            now: { now },
            xpLedger: ledger,
            catalogProvider: ProgressionCatalogProvider()
        )

        #expect(service.recordQualifyingFindIfNeeded(userId: "u1") == .started(currentStreak: 1))
        now = calendar.date(byAdding: .day, value: 1, to: now)!
        #expect(service.recordQualifyingFindIfNeeded(userId: "u1") == .continued(previousStreak: 1, currentStreak: 2))
        #expect(try ledger.ledgerEvents(userId: "u1").count == 1)

        now = calendar.date(byAdding: .day, value: 2, to: now)!
        let restarted = service.recordQualifyingFindIfNeeded(userId: "u1")
        #expect(restarted == .brokenThenStarted(previousStreak: 2))
        #expect(try ledger.ledgerEvents(userId: "u1").count == 1)

        now = calendar.date(byAdding: .day, value: 1, to: now)!
        #expect(service.recordQualifyingFindIfNeeded(userId: "u1") == .continued(previousStreak: 1, currentStreak: 2))
        #expect(try ledger.ledgerEvents(userId: "u1").count == 2)
    }
}
