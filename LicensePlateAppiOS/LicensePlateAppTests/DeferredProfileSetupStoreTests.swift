//
//  DeferredProfileSetupStoreTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
private final class StubAccountStateProvider: AccountStateProviding {
    var state: AccountState = .localGuest

    func currentAccountState(for user: AppUser?) -> AccountState {
        state
    }
}

@MainActor
struct DeferredProfileSetupStoreTests {

    @Test func guestPendingIncludesAccount() async throws {
        let state = InMemoryFirstSessionState()
        let accountProvider = StubAccountStateProvider()
        accountProvider.state = .localGuest
        let store = DeferredProfileSetupStore(state: state, accountStateProvider: accountProvider)

        let pending = store.pendingSteps(for: AppUser(id: "g1", userName: "Guest"))
        #expect(pending.contains(.avatar))
        #expect(pending.contains(.account))
        #expect(pending.contains(.notifications))
        #expect(!pending.contains(.family))
    }

    @Test func signedInWithoutFamilyPendingIncludesFamily() async throws {
        let state = InMemoryFirstSessionState()
        let accountProvider = StubAccountStateProvider()
        accountProvider.state = .signedIn
        let store = DeferredProfileSetupStore(state: state, accountStateProvider: accountProvider)

        let user = AppUser(id: "u1", userName: "User", firebaseUID: "u1")
        let pending = store.pendingSteps(for: user)
        #expect(pending.contains(.family))
        #expect(pending.contains(.avatar))
        #expect(pending.contains(.notifications))
        #expect(!pending.contains(.account))
    }

    @Test func signedInWithFamilyDoesNotIncludeFamily() async throws {
        let state = InMemoryFirstSessionState()
        let accountProvider = StubAccountStateProvider()
        accountProvider.state = .signedIn
        let store = DeferredProfileSetupStore(state: state, accountStateProvider: accountProvider)

        let user = AppUser(id: "u1", userName: "User", firebaseUID: "u1", activeFamilyId: "fam1")
        let pending = store.pendingSteps(for: user)
        #expect(!pending.contains(.family))
    }

    @Test func markTouchedRemovesStep() async throws {
        let state = InMemoryFirstSessionState()
        let store = DeferredProfileSetupStore(state: state, accountStateProvider: StubAccountStateProvider())

        store.markTouched(.avatar, source: "test")
        let pending = store.pendingSteps(for: nil)
        #expect(!pending.contains(.avatar))
    }

    @Test func markTouchedNotificationsRemovesFromPending() async throws {
        let state = InMemoryFirstSessionState()
        let store = DeferredProfileSetupStore(state: state, accountStateProvider: StubAccountStateProvider())

        store.markTouched(.notifications, source: "test")
        let pending = store.pendingSteps(for: nil)
        #expect(!pending.contains(.notifications))
    }
}
