//
//  RegionRemovalCooldownService.swift
//  LicensePlateApp
//
//  Local anti-spam guard: after unfind, block immediate retap on same region
//  until the user taps a different region.
//

import Foundation

protocol RegionRemovalCooldownServiceProtocol: AnyObject {
    func registerConfirmedRemoval(regionId: String)
    func shouldBlockTap(regionId: String) -> Bool
}

/// Currently not used.
final class RegionRemovalCooldownService: RegionRemovalCooldownServiceProtocol {
    private var blockedRegionId: String?

    func registerConfirmedRemoval(regionId: String) {
        blockedRegionId = regionId
    }

    func shouldBlockTap(regionId: String) -> Bool {
        guard let blockedRegionId else { return false }
        if blockedRegionId == regionId {
            return true
        }
        // Any interaction on a different item clears the one-step cooldown.
        self.blockedRegionId = nil
        return false
    }
}
