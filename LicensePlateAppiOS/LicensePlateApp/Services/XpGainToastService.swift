//
//  XpGainToastService.swift
//  LicensePlateApp
//
//  Observes local XP ledger and remote xp_grants; presents aggregated auto-dismissing toasts.
//  Local provisional gains toast immediately offline (no remote snapshot gate).
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
    private let rewardPresenter: RewardPresenter
    private var cancellables = Set<AnyCancellable>()
    private var refreshWorkItem: DispatchWorkItem?
    private var dismissTask: Task<Void, Never>?

    private var activeUserId: String?
    private var acknowledgedIds = Set<String>()
    private var acknowledgedScopeKeys = Set<String>()
    private var burstEvents: [XpGainToastIngestEvent] = []
    private var rankProgressBaselineXp: Int?
    private var hasBaseline = false
    private var timerGeneration = 0
    private let processLaunchDate: Date
    private var pausedForRewardPopup = false

    init(
        xpLedger: XpLedgerRepositoryProtocol = XpLedgerRepository.shared,
        remoteReader: XpGainToastRemoteReading = XpGrantRemoteRepository.shared,
        catalogProvider: ProgressionCatalogProviding = ProgressionCatalogProvider.shared,
        rewardPresenter: RewardPresenter = .shared,
        processLaunchDate: Date = Date(),
        wiresLiveUpdates: Bool = true
    ) {
        self.xpLedger = xpLedger
        self.remoteReader = remoteReader
        self.catalogProvider = catalogProvider
        self.rewardPresenter = rewardPresenter
        self.processLaunchDate = processLaunchDate

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

        rewardPresenter.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncRewardPopupPause() }
            .store(in: &cancellables)
    }

    func configure(userId: String?) {
        refreshWorkItem?.cancel()
        dismissTask?.cancel()
        dismissTask = nil
        presentation = nil
        timerGeneration += 1
        acknowledgedIds.removeAll()
        acknowledgedScopeKeys.removeAll()
        burstEvents.removeAll()
        rankProgressBaselineXp = nil
        hasBaseline = false
        pausedForRewardPopup = false
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
        acknowledgedScopeKeys.removeAll()
        burstEvents.removeAll()
        rankProgressBaselineXp = nil
        hasBaseline = false
        pausedForRewardPopup = false
    }

    func dismissManually() {
        guard presentation != nil else { return }
        timerGeneration += 1
        dismissTask?.cancel()
        dismissTask = nil
        presentation = nil
        burstEvents.removeAll()
        rankProgressBaselineXp = nil
        pausedForRewardPopup = false
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

        let catalog = catalogProvider.current
        let ledgerRows = (try? xpLedger.ledgerEvents(userId: userId)) ?? []
        let grants = remoteReader.hasReceivedInitialSnapshot ? remoteReader.grants : []

        if !hasBaseline {
            establishBaseline(ledgerRows: ledgerRows, grants: grants)
        }

        var newEvents: [XpGainToastIngestEvent] = []
        var sourceMix = Set<String>()

        for row in ledgerRows {
            let key = "ledger|\(row.id)"
            guard !acknowledgedIds.contains(key) else { continue }
            if row.status == .voided || row.xpDelta <= 0 {
                acknowledgedIds.insert(key)
                continue
            }
            // Final mirrors of already-toasted provisional awards must not re-toast.
            if acknowledgedScopeKeys.contains(row.xpUniquenessKey),
               row.grantKind == .finalDiscoveryAward || row.grantKind == .reconciliationAdjustment {
                acknowledgedIds.insert(key)
                continue
            }
            guard let event = XpGainToastSourceMapper.ingestEvent(from: row, catalog: catalog) else {
                acknowledgedIds.insert(key)
                continue
            }
            acknowledgedIds.insert(key)
            acknowledgedScopeKeys.insert(row.xpUniquenessKey)
            newEvents.append(event)
            sourceMix.insert("ledger")
        }

        for grant in grants {
            let key = "grant|\(grant.grantId)"
            guard !acknowledgedIds.contains(key) else { continue }
            guard let event = XpGainToastSourceMapper.ingestEvent(from: grant, catalog: catalog) else {
                acknowledgedIds.insert(key)
                continue
            }
            acknowledgedIds.insert(key)
            newEvents.append(event)
            sourceMix.insert("remote")
        }

        guard !newEvents.isEmpty else { return }
        presentBurst(newEvents: newEvents, sourceMix: sourceMix.sorted().joined(separator: "+"))
    }

    private func establishBaseline(ledgerRows: [XpLedgerEvent], grants: [UserXpGrant]) {
        for row in ledgerRows {
            // Never absorb provisional rows created in this process into the historical baseline.
            if row.status == .provisional, row.createdAt >= processLaunchDate {
                continue
            }
            acknowledgedIds.insert("ledger|\(row.id)")
            if row.xpDelta > 0 {
                acknowledgedScopeKeys.insert(row.xpUniquenessKey)
            }
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
            // Rank band: total before this burst = current display total minus the new burst.
            let currentTotal = XpDisplayedTotalResolver.totalXp(
                userId: userId,
                xpLedger: xpLedger,
                remoteReader: remoteReader
            )
            let incomingGain = newEvents.reduce(0) { $0 + $1.xpAmount }
            rankProgressBaselineXp = max(0, currentTotal - incomingGain)
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
        syncRewardPopupPause()
    }

    private func syncRewardPopupPause() {
        let blocking = rewardPresenter.current != nil
        if blocking, !pausedForRewardPopup, presentation != nil {
            pausedForRewardPopup = true
            dismissTask?.cancel()
            dismissTask = nil
        } else if !blocking, pausedForRewardPopup, presentation != nil {
            pausedForRewardPopup = false
            let catalog = catalogProvider.current
            let duration = TimeInterval(catalog.xpToast.burstDurationSeconds)
            scheduleAutoDismiss(duration: duration)
        }
    }

    private func scheduleAutoDismiss(duration: TimeInterval) {
        if rewardPresenter.current != nil {
            pausedForRewardPopup = true
            dismissTask?.cancel()
            dismissTask = nil
            return
        }
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
        pausedForRewardPopup = false
        AnalyticsService.shared.log(.xpGainToastDismissed(reason: "auto"))
    }
}
