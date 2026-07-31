//
//  XpProgressViewModel.swift
//  LicensePlateApp
//
//  Profile: server progression XP + open provisional ledger (settlement-aware).
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
        ProgressionDisplayTotalsResolver.resolve(
            userId: userId,
            ledgerEvents: (try? xpLedger.ledgerEvents(userId: userId)) ?? [],
            serverSnapshot: UserProgressionRepository.shared.snapshot,
            verifiedGrantSum: verifiedProvider().verified,
            hasReceivedGrantSnapshot: XpGrantRemoteRepository.shared.hasReceivedInitialSnapshot
        ).displayedTotalXp
    }

    var isUsingLocalFallback: Bool {
        UserProgressionRepository.shared.snapshot == nil
    }

    private let userId: String
    private let xpLedger: XpLedgerRepositoryProtocol
    private let snapshotProvider: () -> Int?
    private let verifiedProvider: () -> (verified: Int?, matchesServerTotal: Bool)
    private var cancellables = Set<AnyCancellable>()

    init(
        userId: String,
        xpLedger: XpLedgerRepositoryProtocol = XpLedgerRepository.shared,
        snapshotProvider: (() -> Int?)? = nil,
        verifiedProvider: (() -> (verified: Int?, matchesServerTotal: Bool))? = nil,
        wiresLiveUpdates: Bool = true
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
            // Audit only — never override mismatched progression totals.
            return (matches || serverTotal == 0 ? verified : nil, matches)
        }
        refresh()
        if wiresLiveUpdates {
            subscribeToLiveUpdates()
        }
    }

    private func subscribeToLiveUpdates() {
        UserProgressionRepository.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        XpGrantRemoteRepository.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        if let ledger = xpLedger as? XpLedgerRepository {
            ledger.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &cancellables)
        }
    }

    func refresh() {
        let snapshot = UserProgressionRepository.shared.snapshot
        serverFinalXp = snapshotProvider() ?? snapshot?.totalXp
        let verified = verifiedProvider()
        verifiedServerXp = verified.verified
        isXpGrantLedgerVerified = verified.matchesServerTotal
        do {
            let events = try xpLedger.ledgerEvents(userId: userId)
            let totals = ProgressionDisplayTotalsResolver.resolve(
                userId: userId,
                ledgerEvents: events,
                serverSnapshot: snapshot,
                verifiedGrantSum: verified.verified,
                hasReceivedGrantSnapshot: XpGrantRemoteRepository.shared.hasReceivedInitialSnapshot
            )
            ledgerProvisionalPending = totals.openProvisionalXp
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            ledgerProvisionalPending = 0
        }
        lastUpdated = Date()
    }
}
