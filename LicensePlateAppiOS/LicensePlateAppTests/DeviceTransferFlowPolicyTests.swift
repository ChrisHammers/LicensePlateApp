//
//  DeviceTransferFlowPolicyTests.swift
//  LicensePlateAppTests
//
//  FR-84 (F-41) owner device test 2026-09-10: the transfer "seemed to accept" but the device
//  never became the child, a second code errored, and the guardian's code vanished on a screen
//  refresh. Two of the client-side pieces are pure and pinned here: whose local play follows
//  the child onto the adopted account, and the guardian's memory of a live code.
//

import Foundation
import Testing
@testable import LicensePlateApp

struct DeviceTransferRebindPolicyTests {

    @Test func aLocalFirstChildsPlayFollowsThemOntoTheAdoptedAccount() {
        #expect(DeviceTransferAdoptionPolicy.rebindsLocalPlay(
            preRedeemSessionIsRegistered: false,
            previousPlayIdentity: "provisional-uid",
            adoptedUserId: "kid"
        ))
    }

    @Test func aRegisteredAdultsLocalPlayStaysTheirs() {
        // The hand-me-down phone: the parent's trips on it are the parent's.
        #expect(!DeviceTransferAdoptionPolicy.rebindsLocalPlay(
            preRedeemSessionIsRegistered: true,
            previousPlayIdentity: "parent",
            adoptedUserId: "kid"
        ))
    }

    @Test func nothingRebindsOntoItselfOrFromNowhere() {
        #expect(!DeviceTransferAdoptionPolicy.rebindsLocalPlay(
            preRedeemSessionIsRegistered: false,
            previousPlayIdentity: "kid",
            adoptedUserId: "kid"
        ))
        #expect(!DeviceTransferAdoptionPolicy.rebindsLocalPlay(
            preRedeemSessionIsRegistered: false,
            previousPlayIdentity: "",
            adoptedUserId: "kid"
        ))
    }
}

@MainActor
@Suite(.serialized)
struct DeviceTransferLiveCodeCacheTests {

    @Test func aLiveCodeIsRememberedPerChildUntilItExpires() {
        DeviceTransferLiveCodeCache.forgetAll()
        let now = Date()
        DeviceTransferLiveCodeCache.remember(code: "TRN111", expiresAt: now.addingTimeInterval(600), forChild: "kid")

        #expect(DeviceTransferLiveCodeCache.liveEntry(forChild: "kid", now: now)?.code == "TRN111")
        #expect(DeviceTransferLiveCodeCache.liveEntry(forChild: "other", now: now) == nil)
        #expect(DeviceTransferLiveCodeCache.liveEntry(forChild: "kid", now: now.addingTimeInterval(601)) == nil)
        #expect(DeviceTransferLiveCodeCache.liveEntry(forChild: "kid", now: now) == nil,
                "an expired entry is forgotten on read")
    }

    @Test func aNewCodeReplacesTheOldAndAdoptionForgetsIt() {
        DeviceTransferLiveCodeCache.forgetAll()
        let now = Date()
        DeviceTransferLiveCodeCache.remember(code: "OLD111", expiresAt: now.addingTimeInterval(600), forChild: "kid")
        DeviceTransferLiveCodeCache.remember(code: "NEW222", expiresAt: now.addingTimeInterval(900), forChild: "kid")
        #expect(DeviceTransferLiveCodeCache.liveEntry(forChild: "kid", now: now)?.code == "NEW222")

        DeviceTransferLiveCodeCache.forget(child: "kid")
        #expect(DeviceTransferLiveCodeCache.liveEntry(forChild: "kid", now: now) == nil)
    }
}
