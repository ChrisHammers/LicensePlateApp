//
//  XpGainToastService.swift
//  LicensePlateApp
//
//  Observes local XP ledger and remote xp_grants; presents aggregated auto-dismissing toasts.
//
//  TWO invariants, and neither may break the other:
//   • LOCAL: provisional gains toast immediately offline — the ledger half of the baseline is
//     sealed on the first refresh, with no remote gate of any kind.
//   • REMOTE (§3.1.1 item 12, 2026-09-16): the historical line for remote grants is NOT "the first
//     refresh" but "the first SERVER-CONFIRMED snapshot of this listener binding". Until that seal
//     lands, every grant in view is absorbed silently; after it, every grant is a real gain.
//     `hasReceivedInitialSnapshot` is the wrong gate and is now only traced, never obeyed: the
//     repository sets it on an error callback too, and Firestore raises an empty from-cache snapshot
//     as soon as it goes offline, so it means "a callback happened", not "a snapshot arrived".
//     The seal is keyed `<uid>#<bindingGeneration>` so a rebind (reinstall, sign-in, FR-84 device
//     transfer, sign-out/in) re-earns it, and the service fails closed while the repository is
//     bound to another uid. The fix deliberately does NOT live at the RootView call sites:
//     reordering startListening/configure is not a fix, because an uncached uid has no cached
//     snapshot to win with at any ordering.
//     Accepted loss, by design: a grant that first becomes visible INSIDE the sealing snapshot never
//     toasts — i.e. anything written since this device's last server-confirmed snapshot: one round
//     trip on an online launch, the whole offline stretch on an offline launch. Anything that also
//     wrote a local ledger row toasted from the ledger anyway, so the exposure is an achievement or
//     a peer-authored competitive placement landing in that window (its XP still counts).
//

import Combine
import Foundation

@MainActor
protocol XpGainToastRemoteReading: AnyObject {
    var grants: [UserXpGrant] { get }
    /// "A callback happened." Kept because XpDisplayedTotalResolver / XpProgressViewModel /
    /// ProgressionXpDriftAfterSyncReporter still key their verified totals off it; this service
    /// only traces it. Deliberately given NO protocol-extension default alongside the three below —
    /// a compile error in a future test double is the safe failure, a silently-wrong default is not.
    var hasReceivedInitialSnapshot: Bool { get }
    /// "The server confirmed a snapshot of the CURRENT binding." The remote history line.
    var hasReceivedServerSnapshot: Bool { get }
    var bindingGeneration: Int { get }
    var boundUserId: String? { get }
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
    /// `sourceEventId|reason` of completion awards already toasted from a local ledger row, so the
    /// server grant mirroring the same award does not toast a second time. Keyed per award rather than
    /// blanket-skipped by reason: a peer whose device never wrote the local row still gets its toast.
    private var acknowledgedLocalAwardKeys = Set<String>()
    /// §3.1.1 item 14 — the id-INDEPENDENT half of the dedup, in the local→remote direction.
    /// SERVER award scopes (`XpGainToastEligibility.mirroredServerScopeKey`) this device has already
    /// announced, or absorbed into the ledger baseline, from a LOCAL row. A grant whose
    /// `idempotencyKey` is in here is the server mirroring an award this device already showed, so it
    /// is acked and never enters `newEvents` (which also keeps the rank band's burst gain honest:
    /// mirror XP is already inside the displayed total).
    private var acknowledgedMirroredScopeKeys = Set<String>()
    /// The same join in the remote→local direction: `idempotencyKey`s of grants absorbed pre-seal,
    /// suppressed, or toasted. A local row that mirrors one of those scopes would announce XP the
    /// server has already paid and already told this device about (the other device / reinstall case).
    private var acknowledgedGrantScopeKeys = Set<String>()
    /// PROCESS-lifetime, deliberately NOT cleared by `configure` or `resetForSignOut`: ledger row ids
    /// this process has already presented. `configure` starts a new identity epoch and drops every ack
    /// set, while `establishLedgerBaseline` refuses to absorb provisional rows created in THIS process
    /// — so without this, a mid-session identity change (FR-60 provision-at-consent, guest → registered
    /// link, FR-84 device transfer) re-toasted rows the user had already seen seconds earlier. Safe to
    /// key on `id` because an identity rebind rewrites `userId` and `xpUniquenessKey` in place and
    /// never the row id (`Repositories/LocalPlayIdentityRepository.swift:218-232`,
    /// `XpLedgerRepository.repairKeysRetiredByIdentityRebind`).
    private var presentedLedgerRowIds = Set<String>()
    private var burstEvents: [XpGainToastIngestEvent] = []
    private var rankProgressBaselineXp: Int?
    /// The LOCAL half of the baseline: sealed on the first refresh of an identity epoch, never
    /// gated on anything remote (that is what keeps offline provisional gains toasting).
    private var hasLedgerBaseline = false
    /// The REMOTE half: `"<uid>#<bindingGeneration>"` of the binding whose server-confirmed
    /// snapshot became this epoch's history line. `nil` means unsealed — absorb, present nothing.
    private var remoteBaselineKey: String?
    private var timerGeneration = 0
    private let processLaunchDate: Date
    private var configuredAt: Date?
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
        acknowledgedLocalAwardKeys.removeAll()
        acknowledgedMirroredScopeKeys.removeAll()
        acknowledgedGrantScopeKeys.removeAll()
        burstEvents.removeAll()
        rankProgressBaselineXp = nil
        // A new identity epoch re-earns BOTH halves of the baseline.
        hasLedgerBaseline = false
        remoteBaselineKey = nil
        pausedForRewardPopup = false
        configuredAt = Date()
        activeUserId = userId?.isEmpty == false ? userId : nil
        XpToastDiagnostics.log(
            "configure uid=\(XpToastDiagnostics.shortUid(activeUserId)) repoUid=\(XpToastDiagnostics.shortUid(remoteReader.boundUserId)) gen=\(remoteReader.bindingGeneration) hasInitialSnapshot=\(remoteReader.hasReceivedInitialSnapshot ? 1 : 0) sealed=\(remoteReader.hasReceivedServerSnapshot ? 1 : 0) grants=\(remoteReader.grants.count)"
        )
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
        acknowledgedLocalAwardKeys.removeAll()
        acknowledgedMirroredScopeKeys.removeAll()
        acknowledgedGrantScopeKeys.removeAll()
        burstEvents.removeAll()
        rankProgressBaselineXp = nil
        hasLedgerBaseline = false
        remoteBaselineKey = nil
        configuredAt = nil
        pausedForRewardPopup = false
        XpToastDiagnostics.log("reset signOut")
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
        let remoteGrants = remoteReader.grants

        XpToastDiagnostics.log(
            "refresh gen=\(remoteReader.bindingGeneration) sealed=\(remoteBaselineKey != nil ? 1 : 0) ledgerBaseline=\(hasLedgerBaseline ? 1 : 0) ledgerRows=\(ledgerRows.count) grants=\(remoteGrants.count) ackIds=\(acknowledgedIds.count)"
        )

        if !hasLedgerBaseline {
            establishLedgerBaseline(ledgerRows: ledgerRows)
            hasLedgerBaseline = true
        }

        // The remote half, decided before either loop runs.
        var mayPresentGrants = true
        let repoUserId = remoteReader.boundUserId
        if repoUserId != userId {
            // The repository is stopped, or bound to another identity: absorb nothing (those ids do
            // not belong to this epoch's ack set), present nothing. Fail closed.
            XpToastDiagnostics.log(
                "remote.skip reason=uid_mismatch svcUid=\(XpToastDiagnostics.shortUid(userId)) repoUid=\(XpToastDiagnostics.shortUid(repoUserId))"
            )
            mayPresentGrants = false
        } else {
            let key = "\(userId)#\(remoteReader.bindingGeneration)"
            if remoteBaselineKey != key {
                // Pre-seal absorption: whatever is in view is history, and the seal absorbs whatever
                // the server adds on top of a partial cache. Only a server-confirmed snapshot seals.
                absorbRemoteGrantHistory(
                    remoteGrants,
                    sealKey: remoteReader.hasReceivedServerSnapshot ? key : nil,
                    catalog: catalog
                )
                mayPresentGrants = false
            }
        }
        let grants = mayPresentGrants ? remoteGrants : []

        var newEvents: [XpGainToastIngestEvent] = []
        var sourceMix = Set<String>()
        var suppressedGrants = 0
        var suppressedRows = 0

        for row in ledgerRows {
            let key = "ledger|\(row.id)"
            guard !acknowledgedIds.contains(key) else { continue }
            if row.status == .voided || row.xpDelta <= 0 {
                acknowledgedIds.insert(key)
                continue
            }
            // §3.1.1 item 14. Registered for every positive, non-voided row INDEPENDENT of whether
            // the mapper produces a line: a row whose catalog group is missing or renamed still
            // announces nothing, and its server mirror must still not announce it twice.
            let mirroredScope = XpGainToastEligibility.mirroredServerScopeKey(for: row)
            if let mirroredScope, acknowledgedMirroredScopeKeys.insert(mirroredScope).inserted {
                XpToastDiagnostics.log(
                    "ledger.scopeAck reason=\(row.reasonCode.rawValue) scope=\(XpToastDiagnostics.redactedScope(mirroredScope)) src=live"
                )
            }
            // The symmetric direction: the server already granted this award and this device already
            // saw the grant (another device of the account, or a reinstall's absorbed history). The
            // local row would announce XP the server will not pay again.
            if let mirroredScope, acknowledgedGrantScopeKeys.contains(mirroredScope) {
                acknowledgedIds.insert(key)
                // Handled for this process, exactly like a presented row: a mid-session identity
                // change must not re-expose it (its award was already announced from the grant).
                presentedLedgerRowIds.insert(row.id)
                suppressedRows += 1
                XpToastDiagnostics.log(
                    "ledger.dedup row=\(row.id.suffix(8)) reason=\(row.reasonCode.rawValue) via=grantScope scope=\(XpToastDiagnostics.redactedScope(mirroredScope))"
                )
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
            if let awardKey = XpGainToastEligibility.localAwardKey(for: row) {
                acknowledgedLocalAwardKeys.insert(awardKey)
            }
            presentedLedgerRowIds.insert(row.id)
            newEvents.append(event)
            sourceMix.insert("ledger")
        }

        for grant in grants {
            let key = "grant|\(grant.grantId)"
            guard !acknowledgedIds.contains(key) else { continue }
            // §3.1.1 item 14: seen once, in whatever way — suppressed, dropped or toasted.
            acknowledgedGrantScopeKeys.insert(grant.idempotencyKey)
            // Already toasted from this device's local provisional row for the same award.
            if acknowledgedLocalAwardKeys.contains(XpGainToastEligibility.localAwardKey(for: grant)) {
                acknowledgedIds.insert(key)
                suppressedGrants += 1
                XpToastDiagnostics.log(
                    "remote.dedup idTail=\(grant.grantId.suffix(10)) reason=\(grant.reason) via=awardKey key=\(XpGainToastEligibility.localAwardKey(for: grant))"
                )
                continue
            }
            // §3.1.1 item 14: the same award, joined on the SERVER scope rather than on either
            // side's event id. Acked here rather than mapped, so it never reaches `newEvents` and
            // never moves the rank band by XP that is already inside the displayed total.
            if acknowledgedMirroredScopeKeys.contains(grant.idempotencyKey) {
                acknowledgedIds.insert(key)
                suppressedGrants += 1
                XpToastDiagnostics.log(
                    "remote.dedup idTail=\(grant.grantId.suffix(10)) reason=\(grant.reason) via=scopeKey scope=\(XpToastDiagnostics.redactedScope(grant.idempotencyKey))"
                )
                continue
            }
            guard let event = XpGainToastSourceMapper.ingestEvent(from: grant, catalog: catalog) else {
                acknowledgedIds.insert(key)
                continue
            }
            acknowledgedIds.insert(key)
            newEvents.append(event)
            sourceMix.insert("remote")
        }

        // Traced after the loop so the loop above stays byte-identical to the pre-item-12 code.
        XpToastDiagnostics.logNewRemoteGrants(
            generation: remoteReader.bindingGeneration,
            grants: grants,
            newEvents: newEvents
        )
        if suppressedGrants > 0 || suppressedRows > 0 {
            XpToastDiagnostics.log(
                "dedup suppressedGrants=\(suppressedGrants) suppressedRows=\(suppressedRows) scopeAcks=\(acknowledgedMirroredScopeKeys.count) grantScopes=\(acknowledgedGrantScopeKeys.count)"
            )
        }

        guard !newEvents.isEmpty else { return }
        presentBurst(newEvents: newEvents, sourceMix: sourceMix.sorted().joined(separator: "+"))
    }

    /// The ledger half of the historical baseline. Verbatim from the pre-item-12 `establishBaseline`,
    /// including the in-process provisional carve-out; never gated on anything remote.
    private func establishLedgerBaseline(ledgerRows: [XpLedgerEvent]) {
        var absorbed = 0
        var skipped = 0
        for row in ledgerRows {
            // Never absorb provisional rows created in this process into the historical baseline —
            // unless this process already PRESENTED them (§3.1.1 item 14). A mid-session identity
            // change re-runs `configure`, and without the carve-out's carve-out the rows the user
            // just saw toast a second time under the new uid.
            if row.status == .provisional,
               row.createdAt >= processLaunchDate,
               !presentedLedgerRowIds.contains(row.id) {
                skipped += 1
                continue
            }
            acknowledgedIds.insert("ledger|\(row.id)")
            absorbed += 1
            if row.xpDelta > 0 {
                acknowledgedScopeKeys.insert(row.xpUniquenessKey)
                if let awardKey = XpGainToastEligibility.localAwardKey(for: row) {
                    acknowledgedLocalAwardKeys.insert(awardKey)
                }
                // §3.1.1 item 14. Unlike the two lines above this one checks `status`: a VOIDED bonus
                // row (clawed back by `XpReconciliationService.voidLocalFindBonuses`) keeps a positive
                // `xpDelta`, and registering its scope after a relaunch would swallow the only
                // announcement of a later, genuine server grant for that same scope.
                if row.status != .voided,
                   let scope = XpGainToastEligibility.mirroredServerScopeKey(for: row),
                   acknowledgedMirroredScopeKeys.insert(scope).inserted {
                    XpToastDiagnostics.log(
                        "ledger.scopeAck reason=\(row.reasonCode.rawValue) scope=\(XpToastDiagnostics.redactedScope(scope)) src=baseline"
                    )
                }
            }
        }
        XpToastDiagnostics.log(
            "ledgerBaseline absorbed=\(absorbed) rows=\(ledgerRows.count) skippedInProcessProvisional=\(skipped)"
        )
    }

    /// The remote half. Every grant in view becomes history; `sealKey` non-nil (a server-confirmed
    /// snapshot of the CURRENT binding) closes the watermark so later grants toast.
    private func absorbRemoteGrantHistory(
        _ grants: [UserXpGrant],
        sealKey: String?,
        catalog: ProgressionCatalog
    ) {
        var absorbed = 0
        for grant in grants {
            // §3.1.1 item 14: absorbed history is still proof the server has paid this scope, so a
            // local row mirroring it must not announce it (the reinstall / second-device direction).
            acknowledgedGrantScopeKeys.insert(grant.idempotencyKey)
            if acknowledgedIds.insert("grant|\(grant.grantId)").inserted {
                absorbed += 1
            }
        }
        guard let sealKey else {
            XpToastDiagnostics.log(
                "remote.absorb gen=\(remoteReader.bindingGeneration) sealed=0 absorbed=\(absorbed) ackTotal=\(acknowledgedIds.count)"
            )
            return
        }
        remoteBaselineKey = sealKey
        XpToastDiagnostics.log(
            XpToastDiagnostics.sealLine(
                generation: remoteReader.bindingGeneration,
                userId: activeUserId,
                absorbed: absorbed,
                grants: grants,
                catalog: catalog,
                msSinceConfigure: configuredAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
            )
        )
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
        XpToastDiagnostics.log(
            "present lines=\(aggregated.lines.count) total=\(aggregated.totalXp) coalesced=\(coalesced ? 1 : 0) sourceMix=\(sourceMix) groupIds=\(groupIds) newLedger=\(newEvents.filter { $0.sourceId.hasPrefix("ledger|") }.count) newGrants=\(newEvents.filter { $0.sourceId.hasPrefix("grant|") }.count)"
        )
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
