//
//  XpClawbackPresentationService.swift
//  LicensePlateApp
//
//  Presents clear “XP removed” feedback when provisional discovery XP is clawed back.
//

import Foundation

@MainActor
final class XpClawbackPresentationService {

    static let shared = XpClawbackPresentationService()

    private let rewardPresenter: RewardPresenter
    private var pending: [XpClawbackNotice] = []

    init(rewardPresenter: RewardPresenter = .shared) {
        self.rewardPresenter = rewardPresenter
    }

    func enqueue(_ notice: XpClawbackNotice) {
        guard notice.xpRemoved > 0 else { return }
        if pending.contains(where: { $0.sourceEventId == notice.sourceEventId }) { return }
        pending.append(notice)
        presentNext()
    }

    func resetForSignOut() {
        pending.removeAll()
    }

    private func presentNext() {
        guard !pending.isEmpty else { return }
        let notice = pending.removeFirst()
        let regionLabel = displayName(forRegionId: notice.regionId)
        rewardPresenter.show(
            .xpRemoved(
                regionLabel: regionLabel,
                xpAmount: notice.xpRemoved,
                sourceEventId: notice.sourceEventId
            )
        )
    }

    private func displayName(forRegionId regionId: String) -> String {
        PlateRegion.all.first { $0.id == regionId }?.name ?? regionId
    }
}
