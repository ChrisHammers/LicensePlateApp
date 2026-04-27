//
//  XpProgressViewModel.swift
//  LicensePlateApp
//
//  Profile: server snapshot XP (unlock authority) vs local ledger provisional (Step XP 03).
//

import Foundation
import Combine

@MainActor
final class XpProgressViewModel: ObservableObject {
    @Published private(set) var serverFinalXp: Int?
    @Published private(set) var ledgerProvisionalPending: Int = 0
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?

    var displayedTotalXp: Int {
        (serverFinalXp ?? 0) + ledgerProvisionalPending
    }

    var isUsingLocalFallback: Bool {
        serverFinalXp == nil
    }

    private let userId: String
    private let xpLedger: XpLedgerRepositoryProtocol
    private let snapshotProvider: () -> Int?

    init(
        userId: String,
        xpLedger: XpLedgerRepositoryProtocol = XpLedgerRepository.shared,
        snapshotProvider: (() -> Int?)? = nil
    ) {
        self.userId = userId
        self.xpLedger = xpLedger
        self.snapshotProvider = snapshotProvider ?? { UserProgressionRepository.shared.snapshot?.totalXp }
        refresh()
    }

    func refresh() {
        serverFinalXp = snapshotProvider()
        do {
            let events = try xpLedger.ledgerEvents(userId: userId)
            ledgerProvisionalPending = LedgerPendingXpTotals.fromLedgerEvents(events).provisionalSum
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            ledgerProvisionalPending = 0
        }
        lastUpdated = Date()
    }
}
