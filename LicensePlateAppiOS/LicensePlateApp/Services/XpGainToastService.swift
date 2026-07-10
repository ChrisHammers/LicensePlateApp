//
//  XpGainToastService.swift
//  LicensePlateApp
//
//  Observes local XP ledger and remote xp_grants; presents aggregated auto-dismissing toasts.
//

import Combine
import Foundation

@MainActor
protocol XpGainToastRemoteReading: AnyObject {
    var grants: [UserXpGrant] { get }
    var hasReceivedInitialSnapshot: Bool { get }
}

extension XpGrantRemoteRepository: XpGainToastRemoteReading {}

@MainActor
final class XpGainToastService: ObservableObject {

    static let shared = XpGainToastService()

    @Published private(set) var presentation: XpGainToastPresentation?

    private let xpLedger: XpLedgerRepositoryProtocol
    private let remoteReader: XpGainToastRemoteReading
    private let catalogProvider: ProgressionCatalogProviding
    private var cancellables = Set<AnyCancellable>()
    private var refreshWorkItem: DispatchWorkItem?
    private var dismissTask: Task<Void, Never>?

    private var activeUserId: String?
    private var acknowledgedIds = Set<String>()
    private var burstEvents: [XpGainToastIngestEvent] = []
    private var rankProgressBaselineXp: Int?
    private var hasBaseline = false
    private var timerGeneration = 0

    init(
        xpLedger: XpLedgerRepositoryProtocol = XpLedgerRepository.shared,
        remoteReader: XpGainToastRemoteReading = XpGrantRemoteRepository.shared,
        catalogProvider: ProgressionCatalogProviding = ProgressionCatalogProvider.shared,
        wiresLiveUpdates: Bool = true
    ) {
        self.xpLedger = xpLedger
        self.remoteReader = remoteReader
        self.catalogProvider = catalogProvider

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
        burstEvents.removeAll()
        rankProgressBaselineXp = nil
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
        burstEvents.removeAll()
        rankProgressBaselineXp = nil
        hasBaseline = false
    }

    func dismissManually() {
        guard presentation != nil else { return }
        timerGeneration += 1
        dismissTask?.cancel()
        dismissTask = nil
        presentation = nil
        burstEvents.removeAll()
        rankProgressBaselineXp = nil
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

        let catalog = catalogProvider.current
        let ledgerRows = (try? xpLedger.ledgerEvents(userId: userId)) ?? []
        let grants = remoteReader.grants

        if !hasBaseline {
            establishBaseline(ledgerRows: ledgerRows, grants: grants)
            return
        }

        var newEvents: [XpGainToastIngestEvent] = []
        var sourceMix = Set<String>()

        for row in ledgerRows {
            let key = "ledger|\(row.id)"
            guard !acknowledgedIds.contains(key) else { continue }
            guard let event = XpGainToastSourceMapper.ingestEvent(from: row, catalog: catalog) else { continue }
            acknowledgedIds.insert(key)
            newEvents.append(event)
            sourceMix.insert("ledger")
        }

        for grant in grants {
            let key = "grant|\(grant.grantId)"
            guard !acknowledgedIds.contains(key) else { continue }
            guard let event = XpGainToastSourceMapper.ingestEvent(from: grant, catalog: catalog) else { continue }
            acknowledgedIds.insert(key)
            newEvents.append(event)
            sourceMix.insert("remote")
        }

        guard !newEvents.isEmpty else { return }
        presentBurst(newEvents: newEvents, sourceMix: sourceMix.sorted().joined(separator: "+"))
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

    private func presentBurst(newEvents: [XpGainToastIngestEvent], sourceMix: String) {
        let coalesced = presentation != nil
        burstEvents.append(contentsOf: newEvents)

        let catalog = catalogProvider.current
        let duration = TimeInterval(catalog.xpToast.burstDurationSeconds)

        if !coalesced, let userId = activeUserId {
            rankProgressBaselineXp = XpDisplayedTotalResolver.totalXp(
                userId: userId,
                xpLedger: xpLedger,
                remoteReader: remoteReader
            )
        }

        let baselineXp = rankProgressBaselineXp ?? 0
        let burstGain = burstEvents.reduce(0) { $0 + $1.xpAmount }
        var aggregated = XpGainToastAggregator.aggregate(
            events: burstEvents,
            catalog: catalog,
            dismissDuration: duration
        )
        aggregated.rankBand = XpGainToastRankBandBuilder.build(
            totalXpBeforeBurst: baselineXp,
            burstXpGained: burstGain,
            catalog: catalog
        )
        presentation = aggregated

        if !coalesced {
            FeedbackService.shared.actionSuccess()
        }

        let groupIds = aggregated.lines.map(\.id).joined(separator: ",")
        AnalyticsService.shared.log(
            .xpGainToastPresented(
                lineCount: aggregated.lines.count,
                totalXp: aggregated.totalXp,
                coalesced: coalesced,
                sourceMix: sourceMix,
                groupIds: groupIds
            )
        )

        scheduleAutoDismiss(duration: duration)
    }

    private func scheduleAutoDismiss(duration: TimeInterval) {
        timerGeneration += 1
        let generation = timerGeneration
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
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
        burstEvents.removeAll()
        rankProgressBaselineXp = nil
        AnalyticsService.shared.log(.xpGainToastDismissed(reason: "auto"))
    }
}
