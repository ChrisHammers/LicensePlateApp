//
//  XpLedgerConstants.swift
//  LicensePlateApp
//
//  MVP XP amounts for discovery ledger (aligned with progression server constants where applicable).
//

import Foundation

enum XpLedgerConstants {
    static let baseDiscoveryProvisionalOrFull: Int = GameProgressionXPRewards.baseDiscoveryXp
    // Step 16.4 policy: no local clawback; late accepted remains full base XP.
    static let competitiveLateFinderNet: Int = GameProgressionXPRewards.baseDiscoveryXp
}
