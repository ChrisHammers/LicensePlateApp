//
//  AppCheckWarmupTests.swift
//  LicensePlateAppTests
//
//  Bug B hardening (2026-08-30): the launch-time App Check warm-up must not depend on
//  Auth, must stop on first success, and must retry the fast-failure class a bounded
//  number of times. The live token request is injected out.
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct AppCheckWarmupTests {

    @Test func stopsOnTheFirstSuccessfulAttempt() async {
        var attempts = 0
        await AppCheckReadiness.warmStandardTokenWithRetries(
            attemptDelaysSeconds: [0, 0, 0],
            fetch: {
                attempts += 1
            }
        )
        #expect(attempts == 1)
    }

    @Test func retriesFastFailuresUntilSuccessThenStops() async {
        var attempts = 0
        await AppCheckReadiness.warmStandardTokenWithRetries(
            attemptDelaysSeconds: [0, 0, 0],
            fetch: {
                attempts += 1
                if attempts < 2 { throw NSError(domain: "test", code: 1) }
            }
        )
        #expect(attempts == 2)
    }

    @Test func aPersistentFailureIsBoundedByThePolicyAndNeverThrows() async {
        var attempts = 0
        await AppCheckReadiness.warmStandardTokenWithRetries(
            attemptDelaysSeconds: [0, 0, 0],
            fetch: {
                attempts += 1
                throw NSError(domain: "test", code: 1)
            }
        )
        #expect(attempts == 3)
    }

    @Test func theLivePolicyTriesEarlyThenBacksOff() {
        // First attempt immediate (win the race against the user's first family action),
        // then two spaced retries for a cold provider settling after launch.
        #expect(AppCheckReadiness.warmupAttemptDelaysSeconds == [0, 10, 60])
    }
}
