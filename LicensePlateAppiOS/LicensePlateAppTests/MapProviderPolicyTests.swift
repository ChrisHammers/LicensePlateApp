//
//  MapProviderPolicyTests.swift
//  LicensePlateAppTests
//
//  COPPA F-37 (FR-81(e), OD-6 keep-and-gate): the Google Maps provider is reachable only
//  in a DEBUG build, with the switch on Google, in a confirmed-adult session; the SDK
//  is never given a key unless asked.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct MapProviderPolicyTests {

    private let allPostures: [ChildSessionPosture] = [
        .childDirected, .ratchetedAnonymous, .unresolved, .confirmedNonChild
    ]
    private let allStored: [String?] = [nil, "", "Unknown", AppMapProvider.apple.rawValue, AppMapProvider.google.rawValue]

    @Test func releaseBuildIsAlwaysApple() {
        for posture in allPostures {
            for stored in allStored {
                #expect(MapProviderPolicy.effectiveProvider(storedRaw: stored, posture: posture, isDebugBuild: false) == .apple)
            }
        }
    }

    @Test func debugWithAppleStoredIsApple() {
        for posture in allPostures {
            #expect(MapProviderPolicy.effectiveProvider(
                storedRaw: AppMapProvider.apple.rawValue, posture: posture, isDebugBuild: true
            ) == .apple)
        }
    }

    @Test func debugWithGoogleStoredAndConfirmedAdultIsGoogle() {
        #expect(MapProviderPolicy.effectiveProvider(
            storedRaw: AppMapProvider.google.rawValue, posture: .confirmedNonChild, isDebugBuild: true
        ) == .google)
    }

    @Test(arguments: [ChildSessionPosture.childDirected, .ratchetedAnonymous, .unresolved])
    func debugWithGoogleStoredButNotConfirmedAdultIsApple(posture: ChildSessionPosture) {
        #expect(MapProviderPolicy.effectiveProvider(
            storedRaw: AppMapProvider.google.rawValue, posture: posture, isDebugBuild: true
        ) == .apple)
    }

    @Test func missingOrUnknownStoredValueIsApple() {
        for stored in [nil, "", "Unknown"] as [String?] {
            #expect(MapProviderPolicy.effectiveProvider(storedRaw: stored, posture: .confirmedNonChild, isDebugBuild: true) == .apple)
        }
    }

    @Test func defaultProviderIsApple() {
        #expect(AppPreferences.defaultMapProvider() == .apple)
    }

    // The test target builds in Debug, so `resolvedProvider` sees isDebugBuild == true.

    @Test func resolvedFallsBackToAppleWhenTheSDKCannotStart() {
        var starts = 0
        let provider = MapProviderPolicy.resolvedProvider(
            storedRaw: AppMapProvider.google.rawValue, posture: .confirmedNonChild,
            start: { starts += 1; return false }
        )
        #expect(provider == .apple)
        #expect(starts == 1)
    }

    @Test func resolvedIsGoogleWhenTheSDKStarts() {
        let provider = MapProviderPolicy.resolvedProvider(
            storedRaw: AppMapProvider.google.rawValue, posture: .confirmedNonChild,
            start: { true }
        )
        #expect(provider == .google)
    }

    @Test(arguments: [ChildSessionPosture.childDirected, .ratchetedAnonymous, .unresolved])
    func resolvedNeverStartsTheSDKForANonAdultSession(posture: ChildSessionPosture) {
        var starts = 0
        let provider = MapProviderPolicy.resolvedProvider(
            storedRaw: AppMapProvider.google.rawValue, posture: posture,
            start: { starts += 1; return true }
        )
        #expect(provider == .apple)
        #expect(starts == 0)
    }

    @Test func resolvedNeverStartsTheSDKWhenAppleIsStored() {
        var starts = 0
        let provider = MapProviderPolicy.resolvedProvider(
            storedRaw: AppMapProvider.apple.rawValue, posture: .confirmedNonChild,
            start: { starts += 1; return true }
        )
        #expect(provider == .apple)
        #expect(starts == 0)
    }
}

@MainActor
struct GoogleMapsServiceStartTests {

    private final class Probe {
        var loads = 0
        var provided: [String] = []
    }

    private func makeService(key: String?, providesResult: Bool = true, probe: Probe) -> GoogleMapsService {
        GoogleMapsService(
            loadAPIKey: { probe.loads += 1; return key },
            provideAPIKey: { probe.provided.append($0); return providesResult }
        )
    }

    @Test func doesNotStartUnlessAsked() {
        let probe = Probe()
        let service = makeService(key: "test-key", probe: probe)
        #expect(probe.loads == 0)
        #expect(probe.provided.isEmpty)
        #expect(service.isStarted == false)
    }

    @Test func startsExactlyOnce() {
        let probe = Probe()
        let service = makeService(key: "test-key", probe: probe)
        #expect(service.startIfNeeded() == true)
        #expect(service.startIfNeeded() == true)
        #expect(probe.loads == 1)
        #expect(probe.provided == ["test-key"])
        #expect(service.isStarted)
    }

    @Test(arguments: [nil, "", "   \n"] as [String?])
    func unusableKeyNeverReachesTheSDK(key: String?) {
        let probe = Probe()
        let service = makeService(key: key, probe: probe)
        #expect(service.startIfNeeded() == false)
        #expect(service.startIfNeeded() == false)
        #expect(probe.loads == 1)
        #expect(probe.provided.isEmpty)
    }

    @Test func sdkRefusalIsReportedAndNotRetried() {
        let probe = Probe()
        let service = makeService(key: "test-key", providesResult: false, probe: probe)
        #expect(service.startIfNeeded() == false)
        #expect(service.startIfNeeded() == false)
        #expect(probe.provided.count == 1)
    }

    @Test func usableKeyTrimsAndRejectsBlank() {
        #expect(GoogleMapsService.usableKey(nil) == nil)
        #expect(GoogleMapsService.usableKey("") == nil)
        #expect(GoogleMapsService.usableKey("  ") == nil)
        #expect(GoogleMapsService.usableKey(" abc ") == "abc")
    }
}
