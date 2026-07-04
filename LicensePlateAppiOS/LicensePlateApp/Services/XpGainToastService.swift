//
//  XpGainToastService.swift
//  LicensePlateApp
//
//  Observes local XP ledger and remote xp_grants; presents coalesced auto-dismissing toasts.
//

import Combine
import Foundation

struct XpGainToastPresentation: Equatable {
    var lines: [XpGainToastLine]
    var expiresAt: Date
    var dismissDuration: TimeInterval
}

@MainActor
protocol XpGainToastRemoteReading: AnyObject {
    var grants: [UserXpGrant] { get }
    var hasReceivedInitialSnapshot: Bool { get }
}

extension XpGrantRemoteRepository: XpGainToastRemoteReading {}

@MainActor
final class XpGainToastService: ObservableObject {

    static let shared = XpGainToastService()

    static let defaultDismissDuration: TimeInterval = 4.0

    @Published private(set) var presentation: XpGainToastPresentation?

    private let xpLedger: XpLedgerRepositoryProtocol
    private let remoteReader: XpGainToastRemoteReading
    private var cancellables = Set<AnyCancellable>()
    private var refreshWorkItem: DispatchWorkItem?
    private var dismissTask: Task<Void, Never>?

    private var activeUserId: String?
    private var acknowledgedIds = Set<String>()
    private var hasBaseline = false
    private var timerGeneration = 0

    init(
        xpLedger: XpLedgerRepositoryProtocol = XpLedgerRepository.shared,
        remoteReader: XpGainToastRemoteReading = XpGrantRemoteRepository.shared,
        wiresLiveUpdates: Bool = true
    ) {
        self.xpLedger = xpLedger
        self.remoteReader = remoteReader

        guard wiresLiveUpdates else { return }

        if let ledger = xpLedger as? XpLedgerRepository {
            ledger.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.scheduleRefresh() }
                .store(in: &cancellables)
        }

        if let remote = remoteReader as? XpGrantRemoteRepository {
            remote.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.scheduleRefresh() }
                .store(in: &cancellables)
        }
    }

    func configure(userId: String?) {
        refreshWorkItem?.cancel()
        dismissTask?.cancel()
        dismissTask = nil
        presentation = nil
        timerGeneration += 1
        acknowledgedIds.removeAll()
        hasBaseline = false
        activeUserId = userId?.isEmpty == false ? userId : nil
        guard activeUserId != nil else { return }
        scheduleRefresh()
    }

    func resetForSignOut() {
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        dismissTask?.cancel()
        dismissTask = nil
        presentation = nil
        timerGeneration += 1
        activeUserId = nil
        acknowledgedIds.removeAll()
        hasBaseline = false
    }

    func dismissManually() {
        guard presentation != nil else { return }
        timerGeneration += 1
        dismissTask?.cancel()
        dismissTask = nil
        presentation = nil
        AnalyticsService.shared.log(.xpGainToastDismissed(reason: "manual"))
    }

    internal func performImmediateRefresh() {
        refreshWorkItem?.cancel()
        refresh()
    }

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func refresh() {
        guard let userId = activeUserId, !userId.isEmpty else { return }
        guard remoteReader.hasReceivedInitialSnapshot else { return }

        let ledgerRows = (try? xpLedger.ledgerEvents(userId: userId)) ?? []
        let grants = remoteReader.grants

        if !hasBaseline {
            establishBaseline(ledgerRows: ledgerRows, grants: grants)
            return
        }

        var newLines: [XpGainToastLine] = []
        var sourceMix = Set<String>()

        for row in ledgerRows {
            let key = "ledger|\(row.id)"
            guard !acknowledgedIds.contains(key) else { continue }
            guard let line = XpGainToastLineBuilder.line(from: row) else { continue }
            acknowledgedIds.insert(key)
            newLines.append(line)
            sourceMix.insert("ledger")
        }

        for grant in grants {
            let key = "grant|\(grant.grantId)"
            guard !acknowledgedIds.contains(key) else { continue }
            guard let line = XpGainToastLineBuilder.line(from: grant) else { continue }
            acknowledgedIds.insert(key)
            newLines.append(line)
            sourceMix.insert("remote")
        }

        guard !newLines.isEmpty else { return }
        present(newLines: newLines, sourceMix: sourceMix.sorted().joined(separator: "+"))
    }

    private func establishBaseline(ledgerRows: [XpLedgerEvent], grants: [UserXpGrant]) {
        for row in ledgerRows {
            acknowledgedIds.insert("ledger|\(row.id)")
        }
        for grant in grants {
            acknowledgedIds.insert("grant|\(grant.grantId)")
        }
        hasBaseline = true
    }

    private func present(newLines: [XpGainToastLine], sourceMix: String) {
        let coalesced = presentation != nil
        var merged = presentation?.lines ?? []
        var existingIds = Set(merged.map(\.id))
        for line in newLines where !existingIds.contains(line.id) {
            merged.append(line)
            existingIds.insert(line.id)
        }

        let duration = Self.defaultDismissDuration
        presentation = XpGainToastPresentation(
            lines: merged,
            expiresAt: Date().addingTimeInterval(duration),
            dismissDuration: duration
        )

        if !coalesced {
            FeedbackService.shared.actionSuccess()
        }

        let totalXp = merged.compactMap { parsePositiveXp(from: $0.xpDisplayText) }.reduce(0, +)
        AnalyticsService.shared.log(
            .xpGainToastPresented(
                lineCount: merged.count,
                totalXp: totalXp,
                coalesced: coalesced,
                sourceMix: sourceMix
            )
        )

        scheduleAutoDismiss()
    }

    private func scheduleAutoDismiss() {
        timerGeneration += 1
        let generation = timerGeneration
        let delay = Self.defaultDismissDuration
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.timerGeneration == generation else { return }
                self.dismissAutomatically()
            }
        }
    }

    private func dismissAutomatically() {
        guard presentation != nil else { return }
        presentation = nil
        AnalyticsService.shared.log(.xpGainToastDismissed(reason: "auto"))
    }

    private func parsePositiveXp(from displayText: String) -> Int? {
        let digits = displayText.filter { $0.isNumber }
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }
}
