//
//  ProgressionAppendObserverChain.swift
//  LicensePlateApp
//
//  Forwards `TripActivityEventRecordingService` append notifications to progression and XP reconciliation.
//

import Foundation

@MainActor
final class ProgressionAppendObserverChain: ProgressionLocalAppendObserving {

    static let shared = ProgressionAppendObserverChain()

    private init() {}

    func progressionDidCommitLocalActivityEvent(_ event: TripActivityEvent) {
        UserProgressionService.shared.progressionDidCommitLocalActivityEvent(event)
        XpReconciliationService.shared.handleCommittedActivityEvent(event)
        _ = ReturnStreakService.shared.handleCommittedActivityEvent(event)
    }
}
