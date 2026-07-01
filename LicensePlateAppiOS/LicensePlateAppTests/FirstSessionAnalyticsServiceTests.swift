//
//  FirstSessionAnalyticsServiceTests.swift
//  LicensePlateAppTests
//

import Foundation
import Testing
@testable import LicensePlateApp

@MainActor
final class InMemoryFirstSessionState: FirstSessionStateStoring {
    var onboardingStartedAt: Date?
    var quickTripStartedAt: Date?
    var hasLoggedFirstFind = false
    var deferredSetupStepsCompleted: Set<String> = []
    var deferredSetupPromptDismissedAt: Date?
    var activeFlowVariant: FirstSessionFlowVariant?
    var lastOnboardingStepId: String?

    func elapsedMs(since anchor: Date?) -> Int {
        guard let anchor else { return 0 }
        return max(0, Int(Date().timeIntervalSince(anchor) * 1000))
    }
}

@MainActor
struct FirstSessionAnalyticsServiceTests {

    @Test func onboardingStartedLogsOnce() async throws {
        let spy = AnalyticsLoggingSpy()
        let state = InMemoryFirstSessionState()
        let service = FirstSessionAnalyticsService(analytics: spy, state: state)

        service.recordOnboardingStarted(flowVariant: .quickSolo, offline: false)
        service.recordOnboardingStarted(flowVariant: .quickSolo, offline: false)

        #expect(spy.loggedEvents.filter { $0.name == "onboarding_started" }.count == 1)
        #expect(state.onboardingStartedAt != nil)
    }

    @Test func firstFindCompletedLogsOnce() async throws {
        let spy = AnalyticsLoggingSpy()
        let state = InMemoryFirstSessionState()
        state.onboardingStartedAt = Date().addingTimeInterval(-5)
        let service = FirstSessionAnalyticsService(analytics: spy, state: state)

        let tripId = UUID()
        let gameId = UUID()
        service.recordFirstFindIfNeeded(
            tripSessionId: tripId,
            gameInstanceId: gameId,
            targetId: "us-ca",
            inputMethod: "list"
        )
        service.recordFirstFindIfNeeded(
            tripSessionId: tripId,
            gameInstanceId: gameId,
            targetId: "us-tx",
            inputMethod: "list"
        )

        #expect(spy.loggedEvents.filter { $0.name == "first_find_completed" }.count == 1)
        #expect(state.hasLoggedFirstFind == true)
    }

    @Test func onboardingCompletedIncludesElapsedMs() async throws {
        let spy = AnalyticsLoggingSpy()
        let state = InMemoryFirstSessionState()
        state.onboardingStartedAt = Date().addingTimeInterval(-2)
        let service = FirstSessionAnalyticsService(analytics: spy, state: state)

        service.recordOnboardingCompleted(flowVariant: .quickSolo, offline: true)

        let event = spy.loggedEvents.first { $0.name == "onboarding_completed" }
        #expect(event != nil)
        let elapsed = event?.parameters?["elapsed_ms"] as? Int
        #expect((elapsed ?? 0) >= 0)
        #expect(event?.parameters?["offline"] as? Bool == true)
    }
}
