//
//  RegionRemovalCooldownServiceTests.swift
//  LicensePlateAppTests
//

import Testing
@testable import LicensePlateApp

@MainActor
struct RegionRemovalCooldownServiceTests {

    @Test func immediateRetapIsBlockedAfterRemoval() {
        let service = RegionRemovalCooldownService()
        service.registerConfirmedRemoval(regionId: "US-CA")

        #expect(service.shouldBlockTap(regionId: "US-CA") == true)
    }

    @Test func tappingDifferentRegionClearsBlock() {
        let service = RegionRemovalCooldownService()
        service.registerConfirmedRemoval(regionId: "US-CA")

        #expect(service.shouldBlockTap(regionId: "US-NV") == false)
        #expect(service.shouldBlockTap(regionId: "US-CA") == false)
    }

    @Test func blockOnlyAffectsRemovedItem() {
        let service = RegionRemovalCooldownService()
        service.registerConfirmedRemoval(regionId: "US-CA")

        #expect(service.shouldBlockTap(regionId: "US-TX") == false)
        service.registerConfirmedRemoval(regionId: "US-CA")
        #expect(service.shouldBlockTap(regionId: "US-CA") == true)
    }
}
