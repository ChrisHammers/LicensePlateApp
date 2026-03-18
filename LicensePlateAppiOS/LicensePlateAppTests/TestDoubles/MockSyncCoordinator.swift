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
    var enqueueCallCount = 0
    var enqueueSessionIds: [UUID] = []
    var enqueueEventIds: [String] = []
    var enqueueUserProfileCallCount = 0
    var enqueueUserProfileIds: [String] = []
    var processPendingCallCount = 0

    func enqueueForSync(sessionId: UUID, eventId: String) throws {
        enqueueCallCount += 1
        enqueueSessionIds.append(sessionId)
        enqueueEventIds.append(eventId)
    }

    func enqueueUserProfileSync(userId: String) throws {
        enqueueUserProfileCallCount += 1
        enqueueUserProfileIds.append(userId)
    }

    func processPendingSyncItems() async {
        processPendingCallCount += 1
    }
}
