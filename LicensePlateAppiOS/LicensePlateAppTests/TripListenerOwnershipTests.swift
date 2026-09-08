//
//  TripListenerOwnershipTests.swift
//  LicensePlateAppTests
//
//  Trip-end propagation, owner regression 2026-09-07 (device trace 2026-09-08): the launch
//  re-assert registered a live trip's canonical listeners, and they never fired — not a
//  snapshot, not an error. `TripInviteRepository.startListening` begins with
//  `stopListening`, which used to retire EVERY canonical trip listener one main-actor hop
//  later; in `bootstrapHomeScreen` the invite listener starts one line before the trip
//  re-assert, so the deferred teardown landed right after registration and a device on
//  Home never heard a remote trip end. These pin that the invite repository no longer
//  touches listeners it does not own. Hosted: needs the app's Firebase configuration.
//

import FirebaseCore
import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
struct TripListenerOwnershipTests {

    /// The old teardown was `Task { @MainActor in … }` — one hop. Several hops make sure a
    /// deferred removal would have landed before the assertion.
    private func settleDeferredMainActorWork() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    @Test func restartingInviteListeningKeepsCanonicalTripListeners() async {
        guard FirebaseApp.app() != nil else {
            Issue.record("Firebase is not configured in the test host; listener ownership cannot be exercised")
            return
        }
        let sync = TripCanonicalRemoteSyncService.shared
        let sessionId = UUID()
        sync.startIncrementalListeningIfNeeded(sessionId: sessionId)
        defer { sync.removeIncrementalListeners(sessionId: sessionId) }
        #expect(sync.isIncrementallyListening(sessionId: sessionId))

        // Exactly what `PendingTripsViewModel.loadIfNeeded` does at launch and on identity settle.
        TripInviteRepository.shared.startListening(userId: "listener-ownership-test")
        await settleDeferredMainActorWork()
        #expect(sync.isIncrementallyListening(sessionId: sessionId),
                "restarting invite listening must not retire canonical trip listeners")

        TripInviteRepository.shared.stopListening()
        await settleDeferredMainActorWork()
        #expect(sync.isIncrementallyListening(sessionId: sessionId),
                "stopping invite listening must not retire canonical trip listeners")
    }

    @Test func removingListenersIsExplicitAndScoped() {
        guard FirebaseApp.app() != nil else {
            Issue.record("Firebase is not configured in the test host; listener ownership cannot be exercised")
            return
        }
        let sync = TripCanonicalRemoteSyncService.shared
        let a = UUID()
        let b = UUID()
        sync.startIncrementalListeningIfNeeded(sessionId: a)
        sync.startIncrementalListeningIfNeeded(sessionId: b)
        defer { sync.removeAllIncrementalListeners() }

        sync.removeIncrementalListeners(sessionId: a)
        #expect(!sync.isIncrementallyListening(sessionId: a))
        #expect(sync.isIncrementallyListening(sessionId: b), "a per-session removal leaves other sessions listening")

        sync.removeAllIncrementalListeners()
        #expect(!sync.isIncrementallyListening(sessionId: b))
        // Re-registration after a full teardown is what the identity-settle re-assert relies on.
        sync.startIncrementalListeningIfNeeded(sessionId: b)
        #expect(sync.isIncrementallyListening(sessionId: b))
    }
}
