//
//  XpLedgerConstants.swift
//  LicensePlateApp
//
//  Deprecated shim — forwards to ProgressionRewardsConfigProvider.
//

import Foundation

enum XpLedgerConstants {
    static var baseDiscoveryProvisionalOrFull: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.baseDiscoveryXp
    }
    // Step 16.4 policy: no local clawback; late accepted remains full base XP.
    static var competitiveLateFinderNet: Int {
        ProgressionRewardsConfigProvider.shared.current.xp.baseDiscoveryXp
    }
}
