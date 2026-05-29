//
//  MockSyncCoordinator.swift
//  LicensePlateAppTests
//
//  Step 06 — Test double for SyncCoordinatorProtocol.
//

import Foundation
@testable import LicensePlateApp

@MainActor
final class MockSyncCoordinator: SyncCoordinatorProtocol {
    /// When set, the next `enqueueForSync` throws this error and clears itself (queue row not created).
    var pendingEnqueueForSyncError: Error?
    var enqueueCallCount = 0
    var enqueueSessionIds: [UUID] = []
    var enqueueEventIds: [String] = []
    /// Event ids still considered non-terminal for `ensureGameplayEventEnqueued` deduplication.
    private var nonTerminalGameplayEventIds: Set<String> = []
    var ensureGameplayEventEnqueuedCallCount = 0
    var enqueueUserProfileCallCount = 0
    var enqueueUserProfileIds: [String] = []
    var processPendingCallCount = 0
    var scheduleDebouncedGameplaySyncFlushCallCount = 0

    func enqueueForSync(sessionId: UUID, eventId: String) throws {
        if let err = pendingEnqueueForSyncError {
            pendingEnqueueForSyncError = nil
            throw err
        }
        enqueueCallCount += 1
        enqueueSessionIds.append(sessionId)
        enqueueEventIds.append(eventId)
        nonTerminalGameplayEventIds.insert(eventId)
    }

    func ensureGameplayEventEnqueued(sessionId: UUID, eventId: String) throws {
        ensureGameplayEventEnqueuedCallCount += 1
        if nonTerminalGameplayEventIds.contains(eventId) {
            return
        }
        try enqueueForSync(sessionId: sessionId, eventId: eventId)
    }

    /// Test helper: simulate upload success so a later `ensure` may enqueue again if required by a scenario.
    func markGameplayEventCompletedForTesting(eventId: String) {
        nonTerminalGameplayEventIds.remove(eventId)
    }

    func reset() {
        pendingEnqueueForSyncError = nil
        enqueueCallCount = 0
        enqueueSessionIds.removeAll()
        enqueueEventIds.removeAll()
        nonTerminalGameplayEventIds.removeAll()
        ensureGameplayEventEnqueuedCallCount = 0
        enqueueUserProfileCallCount = 0
        enqueueUserProfileIds.removeAll()
        processPendingCallCount = 0
        scheduleDebouncedGameplaySyncFlushCallCount = 0
    }

    func enqueueUserProfileSync(userId: String) throws {
        enqueueUserProfileCallCount += 1
        enqueueUserProfileIds.append(userId)
    }

    func processPendingSyncItems() async {
        processPendingCallCount += 1
    }

    func scheduleDebouncedGameplaySyncFlushIfOnline() {
        scheduleDebouncedGameplaySyncFlushCallCount += 1
    }
}
