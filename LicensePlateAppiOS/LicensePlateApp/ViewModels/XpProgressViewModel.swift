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
    @Published private(set) var verifiedServerXp: Int?
    @Published private(set) var isXpGrantLedgerVerified: Bool = false
    @Published private(set) var ledgerProvisionalPending: Int = 0
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?

    var displayedTotalXp: Int {
        let base = verifiedServerXp ?? serverFinalXp ?? 0
        return base + ledgerProvisionalPending
    }

    var isUsingLocalFallback: Bool {
        verifiedServerXp == nil && serverFinalXp == nil
    }

    private let userId: String
    private let xpLedger: XpLedgerRepositoryProtocol
    private let snapshotProvider: () -> Int?
    private let verifiedProvider: () -> (verified: Int?, matchesServerTotal: Bool)

    init(
        userId: String,
        xpLedger: XpLedgerRepositoryProtocol = XpLedgerRepository.shared,
        snapshotProvider: (() -> Int?)? = nil,
        verifiedProvider: (() -> (verified: Int?, matchesServerTotal: Bool))? = nil
    ) {
        self.userId = userId
        self.xpLedger = xpLedger
        self.snapshotProvider = snapshotProvider ?? { UserProgressionRepository.shared.snapshot?.totalXp }
        self.verifiedProvider = verifiedProvider ?? {
            let repo = XpGrantRemoteRepository.shared
            guard repo.hasReceivedInitialSnapshot else {
                return (nil, false)
            }
            let verified = repo.verifiedTotalXp
            let serverTotal = UserProgressionRepository.shared.snapshot?.totalXp ?? 0
            let matches = verified == serverTotal
            return (verified > 0 || serverTotal == 0 ? verified : nil, matches)
        }
        refresh()
    }

    func refresh() {
        serverFinalXp = snapshotProvider()
        let verified = verifiedProvider()
        verifiedServerXp = verified.verified
        isXpGrantLedgerVerified = verified.matchesServerTotal
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
